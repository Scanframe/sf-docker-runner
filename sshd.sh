#!/usr/bin/env bash

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Set the base image name of the FROM statement used.
base_img_name="ubuntu:22.04"
# Set the image name to be used.
img_name="sshd:dev"
# Set container name to be used.
container_name="sshd"
# Hostname of the container.
hostname="sshd-server"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [start | stop | run | mc]
  Execute a PHP docker commands for server and command-line control.

  Options:
    -h, --help    : Show this help.
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.

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

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Location of the project files when externally provided.
project_dir="$(realpath "${script_dir}")/project"
# Get the work directory.
work_dir="$(realpath "${script_dir}")/sshd"
# The absolute docker file location.
docker_file="${work_dir}/sshd.Dockerfile"

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

		-p | --project)
			if [[ ! -d "${2}" ]]; then
				echo "Project directory '${2}' does not exist!"
				exit 1
			fi
			project_dir="$(realpath "${2}")"
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

# Process subcommand.
case "${cmd}" in

	build | buildx)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# Build the image.
		dckr_cmd=(docker)
		dckr_cmd+=("${cmd}")
		dckr_cmd+=(--progress plain)
		dckr_cmd+=(--build-arg "BASE_IMG=${base_img_name}")
		dckr_cmd+=(--file "${docker_file}")
		dckr_cmd+=(--tag "${img_name}")
		dckr_cmd+=(--network host)
		dckr_cmd+=("${work_dir}")
		"${dckr_cmd[@]}"
#		# Add also the private repository tag.
#		docker tag "${img_name}" "${NEXUS_REPOSITORY}/${img_name}"
		;;

	run)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		if [[ -z "${project_dir}" ]]; then
			echo "Project (option: -p) is required for this command."
			exit 1
		fi
		# Use option '--privileged' instead of '--device' and '--security-opt' when having fuse mounting problems.
		dckr_cmd=(docker)
		dckr_cmd+=(run)
		dckr_cmd+=(--rm)
		dckr_cmd+=(--interactive)
		dckr_cmd+=(--tty)
		dckr_cmd+=(--name="${container_name}")
		dckr_cmd+=(--hostname="${hostname}")
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		dckr_cmd+=(--network host)
		dckr_cmd+=(--privileged)
		"${dckr_cmd[@]}" "${img_name}" "${@}"
		;;

	start)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		if [[ -z "${project_dir}" ]]; then
			echo "Project (option: -p) is required for this command."
			exit 1
		fi
		# Use option '--privileged' instead of '--device' and '--security-opt' when having fuse mounting problems.
		dckr_cmd=(docker)
		dckr_cmd+=(run)
		dckr_cmd+=(--rm)
		dckr_cmd+=(--detach)
		dckr_cmd+=(--name="${container_name}")
		dckr_cmd+=(--hostname="${hostname}")
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		# Ports openend by container are open on the host so publishing is not need.
		dckr_cmd+=(--network host)
		dckr_cmd+=(--privileged)
		if [[ $# -eq 0 ]]; then
			"${dckr_cmd[@]}" "${img_name}" /usr/sbin/sshd -D -p 3022
		else
			"${dckr_cmd[@]}" "${img_name}" "${@}"
		fi
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

	status)
		# Show the status of the container.
		docker ps --filter name="${container_name}"
		;;

	attach)
		# Connect to the last started container as user 'user'.
		docker exec -it "${container_name}" bash
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;
esac
