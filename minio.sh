#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Read the credentials from non repository file.
source "${SCRIPT_DIR}/.minio-credentials"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [start | stop | run | mc]
  Execute a single or multiple actions for docker and/or it's container.

  Options:
    -h, --help    : Show this help.

  Commands:
    start  : Runs the docker server container in the background.
    stop   : Stops a background running server.
    run    : Runs the docker server container interactively.
    mc     : Runs the Minio control command line.
"
}


# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	ShowHelp
	exit 1
fi

# Change to the current script directory.
cd "${SCRIPT_DIR}" || exit 1

# Container name of the minio server.
CONTAINER_NAME="minio-server"

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

#		-f | --file)
#			FILE="${2}"
#			shift 2
#			continue
#			;;

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

# Set the image name to be used.
IMG_NAME="minio/minio:latest"

# Process subcommand.
case "${cmd}" in
	run)
		docker run \
			--rm \
			--name "${CONTAINER_NAME}" \
			--publish 9000:9000 \
			--user "$(id -u):$(id -g)" \
			--volume "${SCRIPT_DIR}/minio/data:/mnt/data" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			--net=host \
			"${IMG_NAME}" server "/mnt/data"
		;;

	start)
		docker run \
			--detach \
			--name "${CONTAINER_NAME}" \
			--publish 9000:9000 \
			--user "$(id -u):$(id -g)" \
			--volume "${SCRIPT_DIR}/minio/data:/mnt/data" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			--net=host \
			"${IMG_NAME}" server "/mnt/data"
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

	mc)
		docker run \
			--interactive --tty \
			--net=host \
			--hostname="mino-ctl" \
			--volume "${SCRIPT_DIR}/minio/bin:/root/bin" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			--env "MINIO_URL=${MINIO_URL}" \
			--entrypoint="/bin/bash" \
			minio/mc
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;
esac
