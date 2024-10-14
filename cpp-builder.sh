#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Set the base image tag of the FROM statement used.
base_img_tag="24.04"
# Set the base image name of the FROM statement used.
base_img_name="ubuntu"
# The image tag for displaying in help for now.
img_tag="${base_img_tag}-<qt-ver>"
# Set the image name to be used.
img_name="gnu-cpp"
# Set container name to be used.
container_name="gnu-cpp"
# Hostname for the docker container.
hostname="cpp-builder"
# Get temporary directory of this OS.
temp_dir="$(dirname "$(mktemp tmp.XXXXXXXXXX -ut)")"
# Location of the libraries (Qt)
lib_dir="${HOME}/lib"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"
# Initialize empty Qt version library to use.
qt_ver=""

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
    --base-ver    : Version/tag of the base image which defaults to '${base_img_tag}' for image '${base_img_name}'.
    --qt-ver      : Version of the the Qt library to instead of newest one available.

  Commands:
    build           : Builds the docker image tagged '${img_name}:${img_tag}' for self-hosted Nexus repository and requires zipped Qt libraries.
    push            : Pushes the docker image to the self-hosted Nexus repository.
    pull            : Pulls the docker image from the self-hosted Nexus repository.
    base-pull       : Pulls the base image '${base_img_name}:${base_img_tag}' and tags it for the self-hosted docker registry.
    base-push       : Pulls the base image '${base_img_name}:${base_img_tag}' when not there and pushes it to the self-hosted Nexus docker registry.
    qt-lnx          : Generates the 'qt-lnx.zip' from the current user's Linux Qt library.
    qt-win          : Generates the qt-win.zip from the current user's Cross Windows Qt library.
    qt-w64          : Generates the qt-w64.zip from the Windows Qt library relative to the current user's Qt.
    qt-w64-tools    : Generates the qt-tools.zip from the Windows Qt library relative to the current user's Qt.
    qt-lnx-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt-lnx-<qt-ver>.zip'.
    qt-win-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt-win-<qt-ver>.zip'.
    qt-w64-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt-w64-<qt-ver>.zip'.
    qt-w64-tools-up : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt-w64-tools.zip'.
    run             : Runs the docker container named '${container_name}' in the foreground mounting the passed project directory using the host's X-server.
    runx            : Same as 'runx' using a fake X-server.
    stop            : Stops the container named '${container_name}' running in the background.
    start           : Starts the container named '${container_name}' running in the background with sshd service enabled.
    kill            : Kills the container named '${container_name}' running in the background.
    status          : Return the status of named '${container_name}' the container running in the background.
    attach          : Attaches to the  in the background running container named '${container_name}'.
    versions        : Shows versions of most installed applications within the container.
    docker-push     : Push '${container_name}' to userspace '${DOCKER_USER}' on docker.com."
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
# Location of the project files when externally provided.
project_dir="$(realpath "${script_dir}")/project"
# Get the work directory.
work_dir="$(realpath "${script_dir}")/builder"
# The absolute docker file location.
docker_file="${work_dir}/cpp.Dockerfile"
# Base zip-file name containing the Linux Qt library.
qt_lnx_filename="qt-lnx"
# Base zip-file name containing the Windows Qt library.
qt_win_filename="qt-win"
# Base zip-file name containing the Windows Qt library.
qt_w64_filename="qt-w64"
# Base zip-file name containing the Windows Qt library.
qt_w64_tools_filename="qt-w64-tools"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'hp:' --long 'help,project:,base-ver:,qt-ver:' -n "$(basename "${0}")" -- "$@")
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

		--base-ver)
			base_img_tag="${2}"
			shift 2
			continue
			;;

		--qt-ver)
			qt_ver="${2}"
			shift 2
			continue
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

# When no Qt version given find the newest one.
if [[ -z "${qt_ver}" ]]; then
	qt_ver="$(basename "$(find "${lib_dir}/Qt/" -maxdepth 1 -type d -regex ".*\/[0-9]\\.[0-9]+\\.[0-9]+$" | sort --reverse --version-sort | head -n 1)")"
	if [[ -z "${qt_ver}" ]]; then
		echo "No Qt version directory found in '${lib_dir}/Qt'!"
	fi
fi

# Assign the correct image tag.
img_tag="${base_img_tag}-${qt_ver}"

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

case "${cmd}" in

	base-pull)
		docker pull "${base_img_name}:${base_img_tag}"
		docker tag "${base_img_name}:${base_img_tag}" "${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}"
		;;

	base-push)
		docker pull "${base_img_name}:${base_img_tag}"
		docker tag "${base_img_name}:${base_img_tag}" "${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}"
		docker image push "${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}"
		;;

	qt-lnx)
		# Check if the Qt version library directory exists.
		if [[ ! -d "${lib_dir}/Qt/${qt_ver}" ]]; then
			echo "Qt version directory '${lib_dir}/Qt/${qt_ver}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_lnx_filename}-${qt_ver}.zip"
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}/Qt"
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${zip_file}"
		;;

	qt-lnx-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_lnx_filename}-${qt_ver}.zip"
		# Upload file Linux Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/"
		;;

	qt-win)
		# Check if the Qt version library directory exists for Windows.
		if [[ ! -d "${lib_dir}/Qt/${qt_ver}" ]]; then
			echo "Qt version directory '${lib_dir}/QtWin/${qt_ver}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_win_filename}-${qt_ver}.zip"
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}/QtWin"
		# Zip all files except Windows executables.
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/mingw_64/"{bin,lib,include,libexec,mkspecs,plugins} -x '*.exe'
		popd
		ls -lah "${zip_file}"
		;;

	qt-win-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_win_filename}-${qt_ver}.zip"
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/"
		;;

	qt-w64)
		# Check if the Qt version library directory exists for Windows.
		qt_w64_dir="$(realpath "${lib_dir}/Qt")/../../windows/Qt"
		if [[ ! -d "${qt_w64_dir}/${qt_ver}" ]]; then
			echo "Qt version directory '${qt_w64_dir}/${qt_ver}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_w64_filename}-${qt_ver}.zip"
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${qt_w64_dir}"
		# Zip all files except Windows executables.
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/mingw_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${zip_file}"
		;;

	qt-w64-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_w64_filename}-${qt_ver}.zip"
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/"
		;;

	qt-w64-tools)
		# Check if the Qt version library directory exists for Windows.
		qt_w64_dir="$(realpath "${lib_dir}/Qt")/../../windows/Qt"
		if [[ ! -d "${qt_w64_dir}/Tools" ]]; then
			echo "Qt Tools directory '${qt_w64_dir}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_w64_tools_filename}.zip"
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${qt_w64_dir}"
		# Zip all files except Windows executables.
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "Tools/"{mingw*,QtCreator}
		popd
		ls -lah "${zip_file}"
		;;

	qt-w64-tools-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${qt_w64_tools_filename}.zip"
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/"
		;;

	push)
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${img_name}:${img_tag}" "${img_name}:${img_tag}"
		# Push the repository.
		docker image push "${NEXUS_REPOSITORY}/${img_name}:${img_tag}"
		;;

	docker-push)
		docker_img_name="${DOCKER_USER}/${img_name%%:*}"
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${img_name}:${img_tag}" "${docker_img_name}"
		# Push the repository.
		docker image push "${docker_img_name}"
		;;

	pull)
		# Logout from any current server.
		docker logout
		# Pull the image from the Nexus server.
		docker pull "${NEXUS_REPOSITORY}/${img_name}:${img_tag}"
		# Add tag without the Nexus server prefix.
		docker tag "${NEXUS_REPOSITORY}/${img_name}:${img_tag}" "${img_name}:${img_tag}"
		;;

	build | buildx)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}:${img_tag}")" ]]; then
			echo "Stopping containers using image '${img_name}:${img_tag}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}:${img_tag}")
		fi
		build_args=("BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}")
		build_args+=("NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
		build_args+=("NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
		build_args+=("QT_VERSION=${qt_ver}")
		# Build the image.
		dckr_cmd=(docker)
		dckr_cmd+=("${cmd}")
		dckr_cmd+=(--progress plain)
		for arg in "${build_args[@]}"; do
			dckr_cmd+=(--build-arg "${arg}")
		done
#		dckr_cmd+=(--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}")
#		dckr_cmd+=(--build-arg "NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
#		dckr_cmd+=(--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
#		dckr_cmd+=(--build-arg "QT_VER=${qt_ver}")
		dckr_cmd+=(--file "${docker_file}")
		dckr_cmd+=(--tag "${img_name}:${img_tag}")
		dckr_cmd+=(--network host)
		dckr_cmd+=("${work_dir}")
		"${dckr_cmd[@]}"
		# Add also the private repository tag.
		docker tag "${img_name}:${img_tag}" "${NEXUS_REPOSITORY}/${img_name}:${img_tag}"
		;;

	versions)
		# Just reenter the script using the the correct arguments.
		"${0}" --base-ver "${base_img_tag}" run -- /home/user/bin/versions.sh
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
		dckr_cmd+=(--env DEBUG=1)
		#dckr_cmd+=(--volume "${work_dir}/bin:/usr/local/bin/test:ro")
		if [[ "${cmd}" == "runx" ]]; then
			dckr_cmd+=(--env DISPLAY)
			dckr_cmd+=(--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro")
		fi
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		if [[ "${cmd}" == "start" ]]; then
			dckr_cmd+=(--detach)
			"${dckr_cmd[@]}" "${img_name}:${img_tag}" sudo -- /usr/sbin/sshd -e -D -p 3022
		else
			"${dckr_cmd[@]}" "${img_name}:${img_tag}" "${@}"
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
