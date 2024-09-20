#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Set the base image name of the FROM statement used.
base_img_name="ubuntu:22.04"
# Set the image name to be used.
img_name="gnu-cpp:dev"
# Set container name to be used.
container_name="gnu-cpp"
# Hostname for the docker container.
hostname="cpp-builder"

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command>
  Execute an actions for docker and/or it's container.

  Options:
    -h, --help    : Show this help.
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.

  Commands:
    build       : Builds the docker image tagged '${img_name}' for self-hosted Nexus repository and requires zipped Qt libraries.
    push        : Pushes the docker image to the self-hosted Nexus repository.
    pull        : Pulls the docker image from the self-hosted Nexus repository.
    base-push   : Pushes the base image '${base_img_name}' to the self-hosted Nexus repository.
    qt-lnx      : Generates the 'qt-win.zip' from the current users Linux Qt library.
    qt-win      : Generates the qt-win-zip from the current users Windows Qt library.
    qt-lnx-up   : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-lnx.zip'.
    qt-win-up   : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-win.zip'.
    runx        : Runs the docker container named '${container_name}' in the foreground mounting the passed project directory using the host's X-server.
    run         : Same as 'runx' using a fake X-server.
    stop        : Stops the container named '${container_name}' running in the background.
    kill        : Kills the container named '${container_name}' running in the background.
    status      : Return the status of named '${container_name}' the container running in the background.
    attach      : Attaches to the  in the background running container named '${container_name}'.
    versions    : Shows versions of most installed applications within the container.
    docker-push : Push '${container_name}' to userspace '${DOCKER_USER}' on docker.com."
    "${script_dir}/nexus-docker.sh" --help-short
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	ShowHelp
	exit 1
fi

# Check if the required credential file exists.
if [[ ! -f "${script_dir}/.nexus-credentials" ]]; then
	echo "File '${script_dir}/.nexus-credentials' is required."
	exit 1
fi
# Read the credentials from non repository file.
source "${script_dir}/.nexus-credentials"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"
# Location of the project files when externally provided.
project_dir="$(realpath "${script_dir}")/project"
# Get the work directory.
work_dir="$(realpath "${script_dir}")/builder"
# The absolute docker file location.
docker_file="${work_dir}/cpp.Dockerfile"
# Zip file containing thw Qt library.
qt_lnx_zip="/tmp/qt-lnx.zip"
# Zip file containing thw Qt library.
qt_win_zip="/tmp/qt-win.zip"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'hp:' --long 'help,project:' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	ShowHelp
	exit 1
fi

eval set -- "$temp"
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

case "${cmd}" in

	base-push)
		docker pull "${base_img_name}"
		docker tag "${base_img_name}" "${NEXUS_REPOSITORY}/${base_img_name}"
		docker image push "${NEXUS_REPOSITORY}/${base_img_name}"
		;;

	qt-lnx)
		lib_dir="${HOME}/lib"
		qt_ver="$(basename "$(find "${lib_dir}/Qt/" -maxdepth 1 -type d -regex ".*\/[0-9]\\.[0-9]+\\.[0-9]+$" | sort --reverse --version-sort | head -n 1)")"
		if [[ -z "${qt_ver}" ]]; then
			echo "No Qt version directory found in '${lib_dir}/Qt/'."
			exit 1
		fi
		# Remove the current zip file.
		[[ -f "${qt_lnx_zip}" ]] && rm "${qt_lnx_zip}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}/Qt"
		zip --display-bytes --recurse-paths --symlinks "${qt_lnx_zip}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${qt_lnx_zip}"
		;;

	qt-lnx-up)
		# Upload file Linux Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${qt_lnx_zip}" \
			"${NEXUS_SERVER_URL}/repository/shared/library/qt-lnx.zip"
		;;

	qt-win)
		lib_dir="${HOME}/lib"
		# Find the Linux Qt version since the Windows version is linked to Linux one with symlinks.
		qt_ver="$(basename "$(find "${lib_dir}/Qt/" -maxdepth 1 -type d -regex ".*\/[0-9]\\.[0-9]+\\.[0-9]+$" | sort --reverse --version-sort | head -n 1)")"
		if [[ -z "${qt_ver}" ]]; then
			echo "No Qt version directory found in '${lib_dir}/Qt/'."
			exit 1
		fi
		# Remove the current zip file.
		[[ -f "${qt_win_zip}" ]] && rm "${qt_win_zip}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}/QtWin"
		# Zip all files except Windows executables.
		zip --display-bytes --recurse-paths --symlinks "${qt_win_zip}" "${qt_ver}/mingw_64/"{bin,lib,include,libexec,mkspecs,plugins} -x '*.exe'
		popd
		ls -lah "${qt_win_zip}"
		;;

	qt-win-up)
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${qt_win_zip}" \
			"${NEXUS_SERVER_URL}/repository/shared/library/qt-win.zip"
		;;

	push)
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${img_name}" "${img_name}"
		# Push the repository.
		docker image push "${NEXUS_REPOSITORY}/${img_name}"
		;;

	docker-push)
		docker_img_name="${DOCKER_USER}/${img_name%%:*}"
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${img_name}" "${docker_img_name}"
		# Push the repository.
		docker image push "${docker_img_name}"
		;;

	pull)
		# Logout from any current server.
		docker logout
		# Pull the image from the Nexus server.
		docker pull "${NEXUS_REPOSITORY}/${img_name}"
		# Add tag without the Nexus server prefix.
		docker tag "${NEXUS_REPOSITORY}/${img_name}" "${img_name}"
		;;

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
		dckr_cmd+=(--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}")
		dckr_cmd+=(--build-arg "NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
		dckr_cmd+=(--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
		dckr_cmd+=(--file "${docker_file}")
		dckr_cmd+=(--tag "${img_name}")
		dckr_cmd+=(--network host)
		dckr_cmd+=("${work_dir}")
		"${dckr_cmd[@]}"
		# Add also the private repository tag.
		docker tag "${img_name}" "${NEXUS_REPOSITORY}/${img_name}"
		;;

	versions)
		# Just reenter the script using the the correct arguments.
		"${0}" run -- /home/user/bin/versions.sh
		;;

	run | runx | start)
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
		dckr_cmd+=(--device /dev/fuse)
		dckr_cmd+=(--cap-add SYS_ADMIN)
		dckr_cmd+=(--security-opt apparmor:unconfined)
		dckr_cmd+=(--network host)
		dckr_cmd+=(--hostname "${hostname}")
		dckr_cmd+=(--name="${container_name}")
		# Script home/user/bin/entrypoint.sh picks this up or uses the id' from the mounted project user.
		dckr_cmd+=(--env LOCAL_USER="$(id -u):$(id -g)")
		dckr_cmd+=(--user user:user)
		#dckr_cmd+=(--env DEBUG=1)
		#dckr_cmd+=(--volume "${work_dir}/bin:/usr/local/bin/test:ro")
		if [[ "${cmd}" == "runx" ]]; then
			dckr_cmd+=(--env DISPLAY)
			dckr_cmd+=(--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro")
		fi
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		if [[ "${cmd}" == "start" ]]; then
			dckr_cmd+=(--detach)
			"${dckr_cmd[@]}" "${img_name}" sudo -- /usr/sbin/sshd -e -D -p 3022
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
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;

esac
