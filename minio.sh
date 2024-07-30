#!/usr/bin/env bash

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [start | stop | run | mc]
  Execute a MinIO docker commands for server and command-line control.
  Depends on the file '.minio-credentials' used as include file and contains
  variables named MINIO_SERVER_URL, MINIO_ACCESS_KEY and MINIO_SECRET_KEY.

  Options:
    -h, --help    : Show this help.

  Commands:
    run    : Runs the docker server container interactively.
    start  : Runs the docker server container in the background as a daemon.
    stop   : Stops the server running in the background.
    kill   : Kills the server running in the background.
    login  : Creates a CLI configuration in the 'minio/config' directory adding
             the host/alias named 'vps'.
    bash   : Like login but the entrypoint is '/bin/bash' to investigate errors.
    mc     : Runs the Minio CLI command.
             To list entries on host 'vps': '$(basename "$0") -- ls -r vps'.
             To remove entries on host 'vps': '$(basename "$0") -- ls -r vps/my-bucket/my-path'.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	ShowHelp
	exit 1
fi

# Read the credentials from non repository file.
source "${script_dir}/.minio-credentials"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'h' --long 'help' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	ShowHelp
	exit 1
fi

eval set -- "${temp}"
unset temp
while true; do
	case "$1" in

		-h | --help)
			ShowHelp
			exit 0
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

# Container name of the minio server.
container_name="minio-server"
# Container name of the minio control.
container_name_mc="minio-mc"
# Set the image name to be used.
img_name="minio/minio:latest"
# Image name for the CLI.
img_name_mc="minio/mc:latest"
# Directory in the container where the data is stored.
mount_dir="/data"
# Configuration directory inside the CLI container.
mc_cfg_dir="/tmp/mc"

# Process subcommand.
case "${cmd}" in
	run)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# --net=host \
		docker run \
			--rm \
			--name "${container_name}" \
			--publish 9000:9000 \
			--publish 9001:9001 \
			--user "$(id -u):$(id -g)" \
			--volume "${script_dir}/minio/data:${mount_dir}" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			"${img_name}" server "${mount_dir}" --console-address ":9001"
		;;

	start)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		#	--net=host \
		docker run \
			--rm \
			--detach \
			--name "${container_name}" \
			--publish 9000:9000 \
			--publish 9001:9001 \
			--user "$(id -u):$(id -g)" \
			--volume "${script_dir}/minio/data:${mount_dir}" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			"${img_name}" server "${mount_dir}" --console-address ":9001"
		;;

	stop | kill)
		# Stop this docker container only.
		cntr_id="$(docker ps --filter name="${container_name}" --quiet)"
		if [[ -n "${cntr_id}" ]]; then
			echo "Container ID is '${cntr_id}' and performing '${cmd}' command."
			docker "${cmd}" "${cntr_id}"
		else
			echo "Container '${container_name}' is not running."
		fi
		;;

	bash)
		docker run \
			--rm \
			--name "${container_name_mc}" \
			--interactive --tty \
			--hostname="mino-ctl" \
			--user "$(id -u):$(id -g)" \
			--volume "${script_dir}/minio/bin/login.sh:/usr/local/bin/mc-login:ro" \
			--volume "${script_dir}/minio/config:${mc_cfg_dir}:rw" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			--env "MINIO_URL=${MINIO_URL}" \
			--env "mc_cfg_dir=${mc_cfg_dir}" \
			--net=host \
			--entrypoint="bash" \
			"${img_name_mc}"
		;;

	login)
		docker run \
			--rm \
			--name "${container_name_mc}" \
			--interactive --tty \
			--hostname="mino-ctl" \
			--user "$(id -u):$(id -g)" \
			--volume "${script_dir}/minio/bin/login.sh:/usr/local/bin/mc-login:ro" \
			--volume "${script_dir}/minio/config:${mc_cfg_dir}:rw" \
			--env "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
			--env "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
			--env "MINIO_URL=${MINIO_URL}" \
			--env "mc_cfg_dir=${mc_cfg_dir}" \
			--net=host \
			--entrypoint="mc-login" \
			"${img_name_mc}"
		;;

	mc)
		docker run \
			--rm \
			--name "${container_name_mc}" \
			--interactive --tty \
			--hostname="mino-ctl" \
			--user "$(id -u):$(id -g)" \
			--volume "${script_dir}/minio/bin/entrypoint.sh:/usr/local/bin/mc-entrypoint:ro" \
			--volume "${script_dir}/minio/config:${mc_cfg_dir}:rw" \
			--env "mc_cfg_dir=${mc_cfg_dir}" \
			--net=host \
			--entrypoint="mc-entrypoint" \
			"${img_name_mc}" "$@"
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;
esac
