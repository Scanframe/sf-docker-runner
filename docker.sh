#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Location of the project files when externally provided.
#PROJECT_DIR="$(realpath "${SCRIPT_DIR}/project")"
PROJECT_DIR="$(realpath "${SCRIPT_DIR}")"
# Nexus Server URL.
NEXUS_PROTO="http://"
NEXUS_SRV="10.0.3.210:8084"
# Set the image name to be used.
IMG_NAME="test:dev"
# Set container name to be used.
CNTR_NAME="test-dev"
# Location project file.
PROJECT=""
CREDENTIALS="arjan:xs4nexus!"
HOSTNAME="c++build"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [info | push | pull build | buildx | run | make | stop | kill | status | attach]
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

		repository)
			curl \
				-u "${CREDENTIALS}" \
				-X 'GET' 'https://nexus.scanframe.com/service/rest/v1/repositories/docker/hosted/docker-image' \
				-H 'accept: application/json' \
				-H 'NX-ANTI-CSRF-TOKEN: 0.49084790528129085' \
				-H 'X-Nexus-UI: true'
			;;

		list)
			docker image ls --all "${NEXUS_SRV}/*"
			;;

		search)
			docker search "${NEXUS_SRV}/t*" --format "{{.Name}}"
			;;

		info)
			docker system df
			# sudo ~/bin/disk-usage.sh 1 /var/lib/docker
			;;

		prune)
			# Prune build cache.
			docker buildx prune --all
			;;

		tag)
			# Add a tag as when it was uploaded.
			docker tag "${NEXUS_SRV}/${IMG_NAME}" "${IMG_NAME}"
			;;

		login)
			docker login "${NEXUS_SRV}"
			;;

		remove)
			#docker run --rm registry-cli:1.0.1 -l "${CREDENTIALS}" -r "http://{$NEXUS_SRV}" "test"
			docker run --rm "anoxis/registry-cli" -l "${CREDENTIALS}" -r "http://{$NEXUS_SRV}" "test"
			#	-H 'accept: application/json' \
			#docker image ls --all "${NEXUS_SRV}/*" --format "{{.Repository}}"
			#curl -u "${CREDENTIALS}" -I -X GET "http://{$NEXUS_SRV}/v2/"
			#curl -u "${CREDENTIALS}" -I -X DELETE "http://{$NEXUS_SRV}/v2/docker-image/images/test/dev/"
			echo "Exit code $?"
#			if [[ $? -ne 0 ]]; then
#				echo "Remove remote image failed!"
#			fi
    ;;

		push)
			#docker login -u arjan -p "xs4nexus!" nexus.scanframe.com:443
			docker login "${NEXUS_SRV}"
			docker push "${NEXUS_SRV}/${IMG_NAME}"
			;;

		pull)
			docker logout
			docker pull "${NEXUS_SRV}/${IMG_NAME}"
			docker tag "${IMG_NAME}" "${NEXUS_SRV}/${IMG_NAME}"
			;;

		docker)
#			--privileged \
			docker run \
			--rm \
			--interactive \
			--tty \
			--name="docker-docker" \
			--volume /var/run/docker.sock:/var/run/docker.sock \
			--volume "${PROJECT_DIR}:/root/project:ro" \
			--net=host \
			--hostname "${HOSTNAME}" \
			docker:stable \
			/bin/sh -c 'source ~/project/bin/.profile && /bin/sh'
			#'docker:dind'
			;;

		buildx)
			# Stop all containers using this image.
			# shellcheck disable=SC2046
			if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
				echo "Stopping containers using image '${IMG_NAME}'."
				docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
			fi
			# Build the image using the 'docker' subdirectory as the context.
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
			#--no-cache
			# Build the image using the 'docker' subdirectory as the context.
			docker build \
				--build-arg DOCKER_USER_ID="$(id -u)" \
				--progress=plain \
				--file "${DOCKER_FILE}" \
				--tag "${IMG_NAME}" \
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
			# Stop this docker container only.
			docker ps --filter name="${CNTR_NAME}"
			;;

		attach)
			# Connect to the last started container using new bash shell.
			docker start "${CNTR_NAME}"
			docker exec -it "${CNTR_NAME}" /bin/bash
			;;

		*)
			echo "Command '${cmd}' is invalid!"
			ShowHelp
			exit 1
			;;

	esac
done
