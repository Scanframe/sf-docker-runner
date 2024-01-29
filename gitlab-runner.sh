#!/usr/bin/env bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
# Set container name to be used.
CONTAINER_NAME="gitlab-runner"
# Set the image name to be used.
IMG_NAME="gitlab/gitlab-runner:latest"
# Location of the configuration directory.
CONFIG_DIR="$(realpath "${SCRIPT_DIR}")/gitlab-runner"
#CONFIG_DIR="/tmp/gitlab-runner"
# GitLab URL.
URL_GITLAB="https://git.scanframe.com"
# Registration token.
REG_TOKEN="<my token>"
# Hostname of the docker running gitlab-runner.
HOSTNAME="gitlab-runner"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [register | daemon | run | daemon| status | stop | kill]
  Execute a single or multiple actions for docker and/or it's container.

  Options:
    -h, --help  : Show this help.
    -t, --token : GitLab runner registration token.

  Commands/Steps:
    General:
      register,
      reg      : Register the GitLab runner (use token option).
      run      : Run the runner interactively.
      daemon   : Run the runner as a daemon.
      attach   : Attach to a console of the Docker container.
      stop,
      kill     : Stops a background running runner.
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
TEMP=$(getopt -o 'ht:' --long 'help,token:' -n "$(basename "${0}")" -- "$@")
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
			REG_TOKEN="${2}"
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

mkdir --parents "${CONFIG_DIR}" || exit 1

case "${cmd}" in

	reg | register)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
			echo "Stopping containers using image '${IMG_NAME}'."
			docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
		fi
		#	--device /dev/fuse --privileged
		docker run \
			--name "${CONTAINER_NAME}" --rm --tty --interactive \
			--user "0:$(id -g)" \
			--cap-add SYS_ADMIN --security-opt apparmor:unconfined \
			--volume "${CONFIG_DIR}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${HOSTNAME}" \
			"${IMG_NAME}" register \
			--url "${URL_GITLAB}" \
			--token "${REG_TOKEN}" \
			--executor "docker" \
			;;

	daemon)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
			echo "Stopping containers using image '${IMG_NAME}'."
			docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
		fi
		# --restart always
		# --env DATA_DIR="/tmp/config" \
		docker --debug run --rm --detach \
			--name "${CONTAINER_NAME}" \
			--user "0:$(id -g)" \
			--volume "${CONFIG_DIR}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${HOSTNAME}" \
			"${IMG_NAME}"
		;;

	run)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${IMG_NAME}")" ]]; then
			echo "Stopping containers using image '${IMG_NAME}'."
			docker stop $(docker ps -a -q --filter ancestor="${IMG_NAME}")
		fi
		# --restart always
		# --env DATA_DIR="/tmp/config" \
		docker --debug run --rm \
			--name "${CONTAINER_NAME}" \
			--user "0:$(id -g)" \
			--volume "${CONFIG_DIR}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${HOSTNAME}" \
			"${IMG_NAME}"
		;;

	attach)
		# Connect to the last started container using new bash shell.
		docker start "${CONTAINER_NAME}"
		docker exec --interactive --tty "${CONTAINER_NAME}" /bin/bash
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

	status | list)
		docker run --rm --tty --interactive \
			--name "${CONTAINER_NAME}" \
			--user "0:$(id -g)" \
			--volume "${CONFIG_DIR}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${HOSTNAME}" \
			"${IMG_NAME}" "${cmd}"
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;

esac
