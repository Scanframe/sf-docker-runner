#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Read the credentials from non repository file.
source "${SCRIPT_DIR}/.nexus-credentials"
# Location of the project files when externally provided.
PROJECT_DIR="$(realpath "${SCRIPT_DIR}")"
# Set the image name to be used.
IMG_NAME="gnu-cpp:dev"
# Set container name to be used.
CNTR_NAME="gnu-cpp"
# Location project file.
PROJECT=""
# Hostname for the docker container.
HOSTNAME="c++build"

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
      build  : Builds the docker image '${IMG_NAME}'.
      make   : Makes/runs the project file set with option '-p' or '--project'.
    Additional:
      run    : Runs the docker container '${CNTR_NAME}' without an x-server connected.
      stop   : Stops the container '${CNTR_NAME}' by name.
      kill   : Kills the container '${CNTR_NAME}' by name.
      status : Return the status of the container '${CNTR_NAME}' by name.
      attach : Attaches to the running container '${CNTR_NAME}'.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	ShowHelp
	exit 1
fi

# Get the work directory.
WORK_DIR="$(realpath "${SCRIPT_DIR}")"
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
				-u "${DOCKER_USER}:${DOCKER_PASSWORD}" \
				-X 'GET' \
				-H 'accept: application/json' \
				"${NEXUS_SERVER_URL}/service/rest/v1/repositories/docker/hosted/docker-image"
			;;

		list)
			# docker image ls --all "*"
			curl -v \
			-u "${DOCKER_USER}:${DOCKER_PASSWORD}" \
			-X 'GET' \
			"${NEXUS_SERVER_URL}/service/rest/v1/search/assets?repository=docker-image&format=docker"
			;;

		search)
			docker search "${DOCKER_REPOSITORY}/t*" --format "{{.Name}}"
			;;

		tag)
			# Add a tag as when it was uploaded.
			docker tag "${DOCKER_REPOSITORY}/${IMG_NAME}" "${IMG_NAME}"
			;;

		login)
			docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}" "${DOCKER_REPOSITORY}"
			;;

		logout)
			docker logout "${DOCKER_REPOSITORY}"
			;;

		rm | remove)
			echo "Must still be implemented."
    ;;

		del | delete)
			echo "Must still be implemented."
    ;;

		push)
			docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}" login "${DOCKER_REPOSITORY}"
			docker push "${DOCKER_REPOSITORY}/${IMG_NAME}"
			;;

		pull)
			# Logout from any current server.
			docker logout
			# Pull the image from the Nexus server.
			docker pull "${DOCKER_REPOSITORY}/${IMG_NAME}"
			# Add tag without the Nexus server prefix.
			docker tag "${DOCKER_REPOSITORY}/${IMG_NAME}" "${IMG_NAME}"
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
				--build-arg DOCKER_USER_ID="$(id -u)" \
				--progress=plain \
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
				--build-arg DOCKER_USER_ID="$(id -u)" \
				--progress=plain \
				--file "${DOCKER_FILE}" \
				--tag "${IMG_NAME}" \
				--network host \
				"${WORK_DIR}"
			;;

		run)
			docker run \
				--rm \
				--interactive \
				--tty \
				--name="${CNTR_NAME}" \
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
			cntr_id="$(docker ps --filter name="${CNTR_NAME}" --quiet)"
			if [[ -n "${cntr_id}" ]]; then
				echo "Container ID is '${cntr_id}' and performing '${cmd}' command."
				docker "${cmd}" "${cntr_id}"
			else
				echo "Container '${CNTR_NAME}' is not running."
			fi
			;;

		status)
			# Show the status of the container.
			docker ps --filter name="${CNTR_NAME}"
			;;

		attach)
			# Connect to the last started container using new bash shell.
			#docker start "${CNTR_NAME}"
			docker exec -it "${CNTR_NAME}" /bin/bash
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
				--name="${CNTR_NAME}" \
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
