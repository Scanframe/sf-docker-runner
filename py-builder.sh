#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Include WriteLog function.
source "${script_dir}/inc/Miscellaneous.sh"
## Trap script exit with function.
trap 'ScriptExit "${BASH_SOURCE}" "${BASH_LINENO}" "${BASH_COMMAND}"' EXIT

# Set the base image tag of the FROM statement used.
base_img_tag="24.04"
# Default platform for this.
platform="amd64"
# Set the base image name of the FROM statement used.
base_img_name="amd64/ubuntu"
# Set the image name to be used.
img_name="python"
# Python version.
py_ver="3.12.3"
# The image tag.
img_tag="${base_img_tag}-${py_ver}"
# Set container name to be used.
container_name="python"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"
# Pauses the script before executing a command.
flag_pause=true
# Set the default architecture.
architecture="$(uname -m)"
# When running from a 'aarch64' machine set some other defaults.
if [[ "${architecture}" == 'aarch64' ]]; then
	base_img_name='arm64v8/ubuntu'
	platform='arm64'
fi

# Prints the help.
#
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command>
  Execute an action for docker and/or it's container.

  Options:
    -h, --help    : Show this help.
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.
    --platform    : Platform defaults to '${platform}' available is also 'arm64'.
    -y, --yes      : No questions asked to perform the command.

  Commands:
    build         : Builds the docker image named '${img_name}:${img_tag}' for self-hosted Nexus repository.
    push          : Pushes the docker image to the self-hosted Nexus repository.
    pull          : Pulls the docker image from the self-hosted Nexus repository.
    base-pull     : Pulls the base image '${base_img_name}:${base_img_tag}' and tags it for the self-hosted docker registry.
    base-push     : Pulls the base image '${base_img_name}:${base_img_tag}' when not there and pushes it to the self-hosted Nexus docker registry.
    runx          : Runs the docker container named '${container_name}' in the foreground mounting the passed project directory using the host's X-server.
    run           : Same as 'runx' using a fake X-server.
    stop          : Stops the container named '${container_name}' running in the background.
    start         : Starts the container named '${container_name}' running in the background with sshd service enabled at port 3022.
    startx        : Same as 'start' passing the hosts X11 server.
    kill          : Kills the container named '${container_name}' running in the background.
    status        : Return the status of named '${container_name}' the container running in the background.
    attach        : Attaches to the  in the background running container named '${container_name}'.
    versions      : Shows versions of most installed applications within the container.
    docker-push   : Push '${container_name}:${base_img_tag}' to userspace '${DOCKER_USER}' on docker.com.
    docker-latest : Push '${container_name}' getting the tag 'latest' to the userspace '${DOCKER_USER}' on Docker Hub."

  "${script_dir}/nexus-docker.sh" --help-short
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	show_help
	exit 1
fi

# Check if the required credential file exists.
if [[ ! -f "${script_dir}/.nexus-credentials" ]]; then
	WriteLog "! File '${script_dir}/.nexus-credentials' is required."
	exit 1
fi
# Read the credentials from non repository file.
source "${script_dir}/.nexus-credentials"
# Location of the project files when externally provided.
project_dir="$(realpath "${script_dir}")/project"
# Get the work directory.
work_dir="$(realpath "${script_dir}")/builder"
# The absolute docker file location.
docker_file="${work_dir}/python.Dockerfile"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'hyp:' --long 'help,yes,platform:,project:' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi

eval set -- "$temp"
unset temp
while true; do
	case "${1}" in

		-h | --help)
			show_help
			exit 0
			;;

		-y | --yes)
			flag_pause=false
			shift
			;;

		--platform)
			platform="${2}"
			shift 2
			# When the platform does not match the default base image modify it.
			if [[ "${platform}" == 'arm64' && "${base_img_name}" =~ ^amd64 ]]; then
				base_img_name='arm64v8/ubuntu'
				WriteLog "Defaulting platform '${platform}' to base image '${base_img_name}'."
			elif [[ "${platform}" == 'amd64' && "${base_img_name}" =~ ^arm64 ]]; then
				base_img_name='amd64/ubuntu'
				WriteLog "Defaulting platform '${platform}' to base image '${base_img_name}'."
			fi
			continue
			;;

		-p | --project)
			if [[ ! -d "${2}" ]]; then
				WriteLog "! Project directory '${2}' does not exist."
				exit 1
			fi
			project_dir="$(realpath "${2}")"
			shift 2
			continue
			;;

		'--')
			shift 1
			break
			;;

		*)
			WriteLog "! Internal error on argument (${1})"
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

if [[ -n "${cmd}" ]]; then
	WriteLog "
	Python version       : ${py_ver}
	Targeted Platform    : ${platform}
	Architecture         : ${architecture}
	Base image tag       : ${base_img_tag}
	Base image name      : ${base_img_name}
	Image tag            : ${img_tag}
	Image name           : ${img_name}
	Container name       : ${container_name}
	Nexus relative path  : ${raw_lib_offset}
	"
	${flag_pause} && read -rp "Continue with command '${cmd}' [y/N]?" && if [[ $REPLY != [yY] ]]; then
		exit 0
	fi
fi

case "${cmd}" in

	base-pull)
		dckr_cmd=(docker)
		dckr_cmd+=(pull)
		dckr_cmd+=(--platform "linux/${platform}")
		dckr_cmd+=("${base_img_name}:${base_img_tag}")
		"${dckr_cmd[@]}"
		docker tag "${base_img_name}:${base_img_tag}" "${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}"
		;;

	base-push)
		dckr_cmd=(docker)
		dckr_cmd+=(image)
		dckr_cmd+=(push)
		dckr_cmd+=("${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}")
		"${dckr_cmd[@]}"
		;;

	push)
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${platform}/${img_name}:${img_tag}"
		# Push the repository.
		docker image push "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}"
		;;

	pull)
		# Logout from any current server.
		docker logout
		# Pull the image from the Nexus server.
		docker pull "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}"
		# Add tag without the Nexus server prefix.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${platform}/${img_name}:${img_tag}"
		;;

	docker-push)
		docker_img_name="${DOCKER_USER}/${platform}-${img_name%%:*}"
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${docker_img_name}:${img_tag}"
		# Push the repository.
		docker image push "${docker_img_name}:${img_tag}"
		;;

	docker-latest)
		docker_img_name="${DOCKER_USER}/${platform}-${img_name%%:*}"
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${docker_img_name}"
		# Push the repository as latest.
		docker image push "${docker_img_name}"
		;;

	build | buildx)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${platform}/${img_name}:${img_tag}")" ]]; then
			WriteLog "Stopping containers using image '${platform}/${img_name}:${img_tag}'."
			docker stop $(docker ps -a -q --filter ancestor="${platform}/${img_name}:${img_tag}")
		fi
		# Build the image.
		build_args=("BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}")
		build_args+=("PLATFORM=${platform}")
		build_args+=("NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
		build_args+=("NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
		# Build the image.
		dckr_cmd=(docker)
		dckr_cmd+=("${cmd}")
		dckr_cmd+=(--platform "linux/${platform}")
		dckr_cmd+=(--progress plain)
		for arg in "${build_args[@]}"; do
			dckr_cmd+=(--build-arg "${arg}")
		done
		dckr_cmd+=(--file "${docker_file}")
		dckr_cmd+=(--tag "${platform}/${img_name}:${img_tag}")
		dckr_cmd+=(--network host)
		dckr_cmd+=("${work_dir}")
		"${dckr_cmd[@]}"
		# Add also the private repository tag.
		docker tag "${platform}/${img_name}:${img_tag}" "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}"
		;;

	versions)
		# Just reenter the script using the the correct arguments.
		"${0}" run --yes -- /usr/local/bin/test/versions.sh
		;;

	run | runx | start | startx)
		if [[ -z "${project_dir}" ]]; then
			WriteLog "! Project (option: -p) is required for this command."
			exit 1
		fi
		# Use option '--privileged' instead of '--device' and '--security-opt' when having fuse mounting problems.
		dckr_cmd=(docker)
		dckr_cmd+=(run)
		dckr_cmd+=(--rm)
		dckr_cmd+=(--interactive)
		dckr_cmd+=(--tty)
		dckr_cmd+=(--platform "linux/${platform}")
		dckr_cmd+=(--device /dev/fuse)
		dckr_cmd+=(--cap-add SYS_ADMIN)
		dckr_cmd+=(--net=host)
		dckr_cmd+=(--security-opt apparmor:unconfined)
		dckr_cmd+=(--name="${container_name}")
		# Script home/user/bin/entrypoint.sh picks this up or uses the id' from the mounted project user.
		dckr_cmd+=(--env LOCAL_USER="$(id -u):$(id -g)")
		dckr_cmd+=(--user user:user)
		dckr_cmd+=(--env DEBUG=1)
		if [[ "${cmd}" == "runx" || "${cmd}" == "startx" ]]; then
			# Check if the host has a X11 display running at all.
			if [[ -z "${DISPLAY}" || ! -f "${HOME}/.Xauthority" ]]; then
				WriteLog "! Cannot pass X11, DISPLAY or .Xauthority not available."
			fi
			dckr_cmd+=(--env DISPLAY)
			dckr_cmd+=(--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro")
		fi
		dckr_cmd+=(--volume "${work_dir}/bin:/usr/local/bin/test:ro")
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		if [[ "${cmd}" == "start" || "${cmd}" == "startx" ]]; then
			dckr_cmd+=(--detach)
			"${dckr_cmd[@]}" "${platform}/${img_name}:${img_tag}" sudo -- /usr/sbin/sshd -e -D -p 3022
		else
			"${dckr_cmd[@]}" "${platform}/${img_name}:${img_tag}" "${@}"
		fi
		;;

	stop | kill)
		# Stop this docker container only.
		cntr_id="$(docker ps --filter name="${container_name}" --quiet)"
		if [[ -n "${cntr_id}" ]]; then
			WriteLog "Container ID is '${cntr_id}' and performing '${cmd}' command."
			docker "${cmd}" "${cntr_id}"
		else
			WriteLog "Container '${container_name}' is not running."
		fi
		;;

	status)
		# Show the status of the container.
		docker ps --filter name="${container_name}"
		;;

	attach)
		# Connect to the last started container as user 'user'.
		if [[ $# -eq 0 ]]; then
			docker exec --interactive --tty "${container_name}" sudo --login --user=user
		else
			docker exec --interactive --tty "${container_name}" sudo --login --user=user -- "${@}"
		fi
		;;

	*)
		if "${script_dir}/nexus-docker.sh" "${cmd}"; then
			exit 0
		fi
		WriteLog "! Command '${cmd}' is invalid."
		show_help
		exit 1
		;;

esac
