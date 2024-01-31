#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Set the image name to be used.
IMG_NAME="gnu-cpp:dev"
# Set container name to be used.
CONTAINER_NAME="gnu-cpp"
# Hostname for the docker container.
HOSTNAME="cpp-builder"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [info | login | logout | push | pull | build | buildx | run | make | stop | kill | status | attach]
  Execute a single or multiple actions for docker and/or it's container.

  Options:
    -h, --help    : Show this help.
    -p, --project : Borland C++ Builder Project-file (.bpr|.bpk|.bat|.cmd)

  Commands/Steps:
    General:
      build  : Builds the docker image tagded for self hosted repository.
      push   : Pushes the docker image to the self hosted repository.
      pull   : Pulls the docker image from the self hosted repository.
    Additional:
      make   : Makes/runs the project file set with option '-p' or '--project'.
      run    : Runs the docker container in the foreground.
      stop   : Stops the container running in the background.
      kill   : Kills the container running in the background.
      status : Return the status of the container running in the background.
      attach : Attaches to the running container running in the background.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	ShowHelp
	exit 1
fi

# Check if the required credential file exists.
if [[ ! -f "${SCRIPT_DIR}/.nexus-credentials" ]]; then
	echo "File '${SCRIPT_DIR}/.nexus-credentials' is required."
	exit 1
fi
# Read the credentials from non repository file.
source "${SCRIPT_DIR}/.nexus-credentials"
# Location of the project files when externally provided.
PROJECT_DIR="$(realpath "${SCRIPT_DIR}")"
# Location project file.
PROJECT=""
# Get the work directory.
WORK_DIR="$(realpath "${SCRIPT_DIR}")/cpp-builder"
# The absolute docker file location.
DOCKER_FILE="${WORK_DIR}/Dockerfile"

# Change to the current script directory.
cd "${SCRIPT_DIR}" || exit 1

# Parse options.
TEMP=$(getopt -o 'hp:' --long 'help,project:' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	ShowHelp
	exit 1
fi

eval set -- "$TEMP"
unset TEMP
while true; do
	case "$1" in

		-h | --help)
			ShowHelp
			exit 0
			;;

		-p | --project)
			PROJECT="${2}"
			shift 2
			continue
			;;

		'--')
			shift
			break
			;;

		*)
			echo "Internal error on argument (${1}) !" >&2
			exit 1
			;;
	esac
done

# Get the arguments in an array.
argument=""
while [[ $# -gt 0 ]]; do
	argument="${argument} $1"
	shift
done

# Iterate over the command arguments.
for cmd in ${argument}; do
	case "${cmd}" in

		info)
			docker system df
			;;

		prune)
			# Prune build cache.
			docker buildx prune --all
			;;

		repo | repository)
			curl -v \
				-u "${NEXUS_USER}:${NEXUS_PASSWORD}" \
				-X 'GET' \
				-H 'accept: application/json' \
				"${NEXUS_SERVER_URL}/service/rest/v1/repositories/docker/hosted/docker-image"
			;;

		list)
			# docker image ls --all "*"
			curl -v \
			-u "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			-X 'GET' \
			"${NEXUS_SERVER_URL}/service/rest/v1/search/assets?repository=docker-image&format=docker"
			;;

		search)
			docker search "${NEXUS_REPOSITORY}/t*" --format "{{.Name}}"
			;;

		tag)
			# Add a tag as when it was uploaded.
			docker tag "${NEXUS_REPOSITORY}/${IMG_NAME}" "${IMG_NAME}"
			;;

		login)
			echo -n "${NEXUS_PASSWORD}" | docker login --username "${NEXUS_USER}" --password-stdin "${NEXUS_REPOSITORY}"
			;;

		logout)
			docker logout "${NEXUS_REPOSITORY}"
			;;

		rm | remove)
			echo "Must still be implemented."
    ;;

		del | delete)
			echo "Must still be implemented."
    ;;

		push)
			# First login and then push it.
			#echo -n "${NEXUS_PASSWORD}" | docker login --username "${NEXUS_USER}" --password-stdin "${NEXUS_REPOSITORY}" && \
			docker image push "${NEXUS_REPOSITORY}/${IMG_NAME}"
			;;

		pull)
			# Logout from any current server.
			docker logout
			# Pull the image from the Nexus server.
			docker pull "${NEXUS_REPOSITORY}/${IMG_NAME}"
			# Add tag without the Nexus server prefix.
			docker tag "${NEXUS_REPOSITORY}/${IMG_NAME}" "${IMG_NAME}"
			;;

		buildx)
			# Stop all containers using this image.
			# shellcheck disable=SC2046
			if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
				echo "Stopping containers using image '${IMG_NAME}'."
				docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
			fi
			# Build the image.
			docker buildx build \
				--build-arg NEXUS_USER_ID="$(id -u)" \
				--file "${DOCKER_FILE}" \
				--tag "${IMG_NAME}" \
				--network host \
				"${WORK_DIR}"
			;;

		build)
			# Stop all containers using this image.
			# shellcheck disable=SC2046
			if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
				echo "Stopping containers using image '${IMG_NAME}'."
				docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
			fi
			# Build the image.
			docker build \
				--build-arg NEXUS_USER_ID="$(id -u)" \
				--file "${DOCKER_FILE}" \
				--tag "${NEXUS_REPOSITORY}/${IMG_NAME}" \
				--network host \
				"${WORK_DIR}"
			;;

		run)
			docker run \
				--rm \
				--interactive \
				--tty \
				--name="${CONTAINER_NAME}" \
				--env LOCAL_USER_ID="$(id -u "${USER}")" \
				--env LOCAL_GROUP_ID="$(id -g "${USER}")" \
				--volume "${PROJECT_DIR}:/mnt/project:rw" \
				--net=host \
				--hostname "${HOSTNAME}" \
				"${IMG_NAME}" \
				/bin/bash --login
			;;

		stop | kill)
			# Stop this docker container only.
			cntr_id="$(docker ps --filter name="${CONTAINER_NAME}" --quiet)"
			if [[ -n "${cntr_id}" ]]; then
				echo "Container ID is '${cntr_id}' and performing '${cmd}' command."
				docker "${cmd}" "${cntr_id}"
			else
				echo "Container '${CONTAINER_NAME}' is not running."
			fi
			;;

		status)
			# Show the status of the container.
			docker ps --filter name="${CONTAINER_NAME}"
			;;

		attach)
			# Connect to the last started container using new bash shell.
			#docker start "${CONTAINER_NAME}"
			docker exec -it "${CONTAINER_NAME}" /bin/bash
			;;

		make)
			if [[ -z "${PROJECT}" ]]; then
				echo "Project (option: -p) is required for this command."
				exit 1
			fi
			docker run \
				--rm \
				--interactive \
				--tty \
				--name="${CONTAINER_NAME}" \
				--env LOCAL_USER_ID="$(id -u "${USER}")" \
				--env LOCAL_GROUP_ID="$(id -g "${USER}")" \
				--volume "${PROJECT_DIR}:/mnt/project:rw" \
				--net=host \
				--hostname "${HOSTNAME}" \
				"${IMG_NAME}" \
				/bin/bash --login -c "make-project.sh '${PROJECT}'"
			;;

		*)
			echo "Command '${cmd}' is invalid!"
			ShowHelp
			exit 1
			;;

	esac
done
