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
  Execute a single or multiple actions for docker and/or it's container.

  Options:
    -h, --help    : Show this help.
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.

  Commands:
    build     : Builds the docker image tagged 'gnu-cpp:dev' for self-hosted Nexus repository and requires zipped Qt libraries.
    push      : Pushes the docker image to the self-hosted Nexus repository.
    pull      : Pulls the docker image from the self-hosted Nexus repository.
    base-push : Pushes the base image '${base_img_name}' to the self-hosted Nexus repository.
    qt-lnx    : Generates the 'qt-win.zip' from the current users Linux Qt library.
    qt-win    : Generates the qt-win-zip from the current users Windows Qt library.
    qt-lnx-up : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-lnx.zip'.
    qt-win-up : Uploads the generated zip-file to the Nexus server as 'repository/shared/library/qt-win.zip'.
    runx      : Runs the docker container named 'gnu-cpp' in the foreground mounting the passed project directory using the hosts X-server.
    run       : Same as 'runx' using a fake X-server.
    stop      : Stops the container named 'gnu-cpp' running in the background.
    kill      : Kills the container named 'gnu-cpp' running in the background.
    status    : Return the status of named 'gnu-cpp' the container running in the background.
    attach    : Attaches to the  in the background running container named 'gnu-cpp'.
    versions  : Shows versions of most installed applications within the container.
    login     : Login on Docker Nexus repository.
    logout    : Logout Docker from any repository.
"
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

	pull)
		# Logout from any current server.
		docker logout
		# Pull the image from the Nexus server.
		docker pull "${NEXUS_REPOSITORY}/${img_name}"
		# Add tag without the Nexus server prefix.
		docker tag "${NEXUS_REPOSITORY}/${img_name}" "${img_name}"
		;;

	buildx)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# Build the image.
		docker buildx build \
			--progress plain \
			--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}" \
			--build-arg "NEXUS_SERVER_URL=${NEXUS_SERVER_URL}" \
			--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}" \
			--file "${docker_file}" \
			--tag "${img_name}" \
			--network host \
			"${work_dir}"
		;;

	build)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			echo "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# Build the image.
		docker build \
			--progress plain \
			--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}" \
			--build-arg "NEXUS_SERVER_URL=${NEXUS_SERVER_URL}" \
			--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}" \
			--file "${docker_file}" \
			--tag "${img_name}" \
			--network host \
			"${work_dir}"
		# Add also the private repository tag.
		docker tag "${img_name}" "${NEXUS_REPOSITORY}/${img_name}"
		;;

	versions)
		# Just reenter the script using the the correct arguments.
		"${0}" run -- /usr/local/bin/test/versions.sh
		;;

	run)
		if [[ -z "${project_dir}" ]]; then
			echo "Project (option: -p) is required for this command."
			exit 1
		fi
		# Use option '--privileged' instead of '--device' and '--security-opt' when having fuse mounting problems.
		docker run \
			--rm \
			--interactive \
			--tty \
			--device /dev/fuse \
			--cap-add SYS_ADMIN \
			--security-opt apparmor:unconfined \
			--net=host \
			--name="${container_name}" \
			--env LOCAL_USER="$(id -u):$(id -g)" \
			--env DISPLAY \
			--env DEBUG=1 \
			--volume "${work_dir}/bin:/usr/local/bin/test:ro" \
			--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro" \
			--volume "${project_dir}:/mnt/project:rw" \
			--workdir "/mnt/project/" \
			"${img_name}" "${@}"
		;;

	runx)
		if [[ -z "${project_dir}" ]]; then
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
			--name="${container_name}" \
			--env LOCAL_USER="$(id -u):$(id -g)" \
			--env DEBUG=1 \
			--volume "${work_dir}/bin:/usr/local/bin/test:ro" \
			--volume "${project_dir}:/mnt/project:rw" \
			--workdir "/mnt/project/" \
			"${img_name}" "${@}"
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
			docker exec -it "${container_name}" sudo --login --user=user
		else
			docker exec -it "${container_name}" sudo --login --user=user -- "${@}"
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
