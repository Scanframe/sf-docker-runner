#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Set the base image name of the FROM statement used.
BASE_IMG_NAME="ubuntu:22.04"
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
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.

  Commands:
    build     : Builds the docker image tagged 'gnu-cpp:dev' for self-hosted Nexus repository and requires zipped Qt libraries.
    push      : Pushes the docker image to the self-hosted Nexus repository.
    pull      : Pulls the docker image from the self-hosted Nexus repository.
    base-push : Pushes the base image '${BASE_IMG_NAME}' to the self-hosted Nexus repository.
    info      : Show general docker information.
    prune     : Remove all Docker build cache.
    login     : Log Docker in on the Nexus repository.
    logout    : Log docker out from any repository.
    qt-lnx    : Generates the 'qt-win.zip' from the current users Linux Qt library.
    qt-win    : Generates the qt-win-zip from the current users Windows Qt library.
    qt-lnx-up : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-lnx.zip'.
    qt-win-up : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-win.zip'.
    run       : Runs the docker container named 'gnu-cpp' in the foreground mounting the passed project directory.
    stop      : Stops the container named 'gnu-cpp' running in the background.
    kill      : Kills the container named 'gnu-cpp' running in the background.
    status    : Return the status of named 'gnu-cpp' the container running in the background.
    attach    : Attaches to the  in the background running container named 'gnu-cpp'.
    versions  : Shows versions of most installed applications within the container.
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
# Offset of the Nexus server URL to the zipped libraries.
RAW_LIB_OFFSET="repository/shared/library"
# Location of the project files when externally provided.
PROJECT_DIR="$(realpath "${SCRIPT_DIR}")/project"
# Get the work directory.
WORK_DIR="$(realpath "${SCRIPT_DIR}")/cpp-builder"
# The absolute docker file location.
DOCKER_FILE="${WORK_DIR}/Dockerfile"
# Zip file containing thw Qt library.
QT_LNX_ZIP="/tmp/qt-lnx.zip"
# Zip file containing thw Qt library.
QT_WIN_ZIP="/tmp/qt-win.zip"

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
			if [[ ! -d "${2}" ]]; then
				echo "Project directory '${2}' does not exist!"
				exit 1
			fi
			PROJECT_DIR="$(realpath "${2}")"
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

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

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

	base-push)
		docker pull "${BASE_IMG_NAME}"
		docker tag "${BASE_IMG_NAME}" "${NEXUS_REPOSITORY}/${BASE_IMG_NAME}"
		docker image push "${NEXUS_REPOSITORY}/${BASE_IMG_NAME}"
		;;

	login)
		echo -n "${NEXUS_PASSWORD}" | docker login --username "${NEXUS_USER}" --password-stdin "${NEXUS_REPOSITORY}"
		;;

	logout)
		docker logout "${NEXUS_REPOSITORY}"
		;;

	qt-lnx)
		LIB_DIR="${HOME}/lib"
		QT_VER="$(basename "$(find "${LIB_DIR}/Qt/" -maxdepth 1 -type d -regex ".*\/[0-9]\\.[0-9]+\\.[0-9]+$" | sort --reverse --version-sort | head -n 1)")"
		if [[ -z "${QT_VER}" ]]; then
			echo "No Qt version directory found in '${LIB_DIR}/Qt/'."
			exit 1
		fi
		# Remove the current zip file.
		[[ -f "${QT_LNX_ZIP}" ]] && rm "${QT_LNX_ZIP}"
		# Change directory in order for zip to store the correct path.
		pushd "${LIB_DIR}/Qt"
		zip --display-bytes --recurse-paths --symlinks "${QT_LNX_ZIP}" "${QT_VER}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${QT_LNX_ZIP}"
		;;

	qt-lnx-up)
		# Upload file Linux Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${QT_LNX_ZIP}" \
			"${NEXUS_SERVER_URL}/repository/shared/library/qt-lnx.zip"
		;;

	qt-win)
		LIB_DIR="${HOME}/lib"
		# Find the Linux Qt version since the Windows version is linked to Linux one with symlinks.
		QT_VER="$(basename "$(find "${LIB_DIR}/Qt/" -maxdepth 1 -type d -regex ".*\/[0-9]\\.[0-9]+\\.[0-9]+$" | sort --reverse --version-sort | head -n 1)")"
		if [[ -z "${QT_VER}" ]]; then
			echo "No Qt version directory found in '${LIB_DIR}/Qt/'."
			exit 1
		fi
		# Remove the current zip file.
		[[ -f "${QT_WIN_ZIP}" ]] && rm "${QT_WIN_ZIP}"
		# Change directory in order for zip to store the correct path.
		pushd "${LIB_DIR}/QtWin"
		# Zip all files except Windows executables.
		zip --display-bytes --recurse-paths --symlinks "${QT_WIN_ZIP}" "${QT_VER}/mingw_64/"{bin,lib,include,libexec,mkspecs,plugins} -x '*.exe'
		popd
		ls -lah "${QT_WIN_ZIP}"
		;;

	qt-win-up)
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${QT_WIN_ZIP}" \
			"${NEXUS_SERVER_URL}/repository/shared/library/qt-win.zip"
		;;

	rm | remove)
		echo "Must still be implemented."
		;;

	del | delete)
		echo "Must still be implemented."
		;;

	push)
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${IMG_NAME}" "${IMG_NAME}"
		# Push the repository.
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
			--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${BASE_IMG_NAME}" \
			--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${RAW_LIB_OFFSET}" \
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
			--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${BASE_IMG_NAME}" \
			--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${RAW_LIB_OFFSET}" \
			--file "${DOCKER_FILE}" \
			--tag "${IMG_NAME}" \
			--network host \
			"${WORK_DIR}"
		# Add also the private repository tag.
		docker tag "${IMG_NAME}" "${NEXUS_REPOSITORY}/${IMG_NAME}"
		;;

	versions)
		# Just reenter the script using the the correct arguments.
		"${0}" run -- /bin/bash -c /home/user/bin/versions.sh
		;;

	run)
		if [[ -z "${PROJECT_DIR}" ]]; then
			echo "Project (option: -p) is required for this command."
			exit 1
		fi
		# Use option '--privileged' instead of '--device' and '--security-opt' when having fuse mounting problems.
		docker run \
			--rm \
			--interactive \
			--tty \
			--device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined \
			--net=host \
			--name="${CONTAINER_NAME}" \
			--env LOCAL_USER="$(id -u):$(id -g)" \
			--env DISPLAY \
			--env DEBUG=1 \
			--volume "${SCRIPT_DIR}/cpp-builder/build-bin:/root/bin:ro" \
			--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro" \
			--volume "${PROJECT_DIR}:/mnt/project:rw" \
			--workdir "/mnt/project/" \
			"${IMG_NAME}" "${@}"
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
		# Connect to the last started container as user 'user'.
		if [[ $# -eq 0 ]]; then
			docker exec -it "${CONTAINER_NAME}" sudo --login --user=user
		else
			docker exec -it "${CONTAINER_NAME}" sudo --login --user=user -- "${@}"
		fi
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;

esac
