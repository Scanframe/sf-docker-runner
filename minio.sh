#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Read the credentials from non repository file.
source "${SCRIPT_DIR}/.nexus-credentials"

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

		-f | --file)
			FILE="${2}"
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

NEXUS_REPO="https:/nexus.scanframe.com"

case "${cmd}" in

	list)
		curl -v -X GET "${NEXUS_REPO}/service/rest/v1/search?repository=gitlab-runner-cache"
		;;

	upload)
		#	--fail --user user:password
		curl -v \
			--upload-file "${SCRIPT_DIR}/README.md" \
			"${NEXUS_REPO}/repository/gitlab-runner-cache/testing/test-README.md"
		;;

	minio)
		docker run \
			--rm \
			--name "minio-server" \
			--publish 9000:9000 \
			--user "$(id -u):$(id -g)" \
			--volume "${SCRIPT_DIR}/minio/data:/data" \
			--env "MINIO_ACCESS_KEY=access_key" \
			--env "MINIO_SECRET_KEY=access_key_secret" \
			--net=host \
			minio/minio server /data
		;;

	mc)
		docker run \
			--interactive --tty \
			--net=host \
			--hostname="mino-ctl" \
			--volume "${SCRIPT_DIR}/minio/bin:/root/bin" \
			--env "MINIO_ACCESS_KEY=access_key" \
			--env "MINIO_SECRET_KEY=access_key_secret" \
			--entrypoint=/bin/bash \
			minio/mc
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;

esac
