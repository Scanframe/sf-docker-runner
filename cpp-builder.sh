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
# Set the base image name of the FROM statement used.
base_img_name="amd64/ubuntu"
# Default platform for this.
platform="amd64"
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
qt_lib_dir="${HOME}/lib/qt"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"
# Initialize Qt version library to find the highest version available.
qt_ver='max'
# Pauses the script before executing a command.
flag_pause=true
# Set the default architecture.
architecture="$(uname -m)"
# When running from a 'aarch64' machine set some other defaults.
if [[ "${architecture}" == 'aarch64' ]]; then
	base_img_name='arm64v8/ubuntu'
	platform='arm64'
fi
# Optional timestamp file to make it stop loading compressed files and use the cache.
timestamp_file="/tmp/docker-import-timestamp.txt"
# Default is tar+gzip.
zip_format=false

# Prints the help.
#
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command>
  Execute an action for docker and/or it's container.

  Options:
    -h, --help      : Show this help.
    -p, --project   : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.
    --base-image    : Defaults to '${base_img_name}' available is also 'arm64v8/ubuntu'.
    --base-ver      : Version/tag of the base image which defaults to '${base_img_tag}' for base image '${base_img_name}'.
    --platform      : Platform defaults to '${platform}' available is also 'arm64'.
    --qt-ver        : Version of the the Qt library to instead of newest one available.
    --zip           : Compress files using the zip-format, by default is uses tar + gzip.
    -y, --yes       : No questions asked to perform the command.

  Commands:
    timestamp       : Create or update the timestamp file '${timestamp_file}' to make it fixed so those layers are not recreated.
    build           : Builds the docker image tagged '${img_name}:${img_tag}' for self-hosted Nexus repository and requires zipped Qt libraries.
    push            : Pushes the docker image to the self-hosted Nexus repository.
    pull            : Pulls the docker image from the self-hosted Nexus repository.
    base-pull       : Pulls the base image '${base_img_name}:${base_img_tag}' and tags it for the self-hosted docker registry.
    base-push       : Pulls the base image '${base_img_name}:${base_img_tag}' when not there and pushes it to the self-hosted Nexus docker registry.
    qt-lnx          : Generates the 'qt-lnx.tar.gz' from the current user's Linux Qt framework/library location.
    qt-win          : Generates the 'qt-win.tar.gz' from the current user's Cross Windows Qt framework/library location.
    qt-w64          : Generates the 'qt-w64.tar.gz' from the Windows Qt library relative to the current user's Qt.
    qt-w64-tools    : Generates the 'qt-tools.tar.gz' from the Windows Qt library relative to the current user's Qt.
    wine-tools      : Generates the 'win-x86_64-cmake-4.2-combi.tar.gz'.
    qt-lnx-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt/qt-lnx-<architecture>-<qt-ver>.tar.gz'.
    qt-win-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt/qt-win-<architecture>-<qt-ver>.tar.gz'.
    qt-w64-up       : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt/qt-w64-<architecture>-<qt-ver>.tar.gz'.
    qt-w64-tools-up : Uploads the generated zip-file to the Nexus server as '${raw_lib_offset}/qt/qt-w64-tools.zip'.
    wine-tools-up   : Uploads the generated zip-file to the Nexus server'.
    run             : Runs the docker container named '${container_name}' in the foreground mounting without passing the hosts X11 server.
    runx            : Same as 'run' passing the hosts X11 server.
    stop            : Stops the container named '${container_name}' running in the background.
    start           : Starts the container named '${container_name}' running in the background with sshd service enabled at port 3022.
    startx          : Same as 'start' passing the hosts X11 server.
    kill            : Kills the container named '${container_name}' running in the background.
    status          : Return the status of named '${container_name}' the container running in the background.
    attach          : Attaches to the  in the background running container named '${container_name}'.
    versions        : Shows versions of most installed applications within the container.
    docker-push     : Push '${container_name}:${base_img_tag}' to userspace '${DOCKER_USER}' on docker.com.
    docker-latest   : Push '${container_name}' getting the tag 'latest' to the userspace '${DOCKER_USER}' on Docker Hub."
	"${script_dir}/nexus-docker.sh" --help-short
	echo "  Examples:
    ARM 64-bit no Qt library installed.
     ./${cmd_name} --base-image arm64v8/ubuntu --platform arm64 --qt-ver '' build
    AMD 64-bit with Qt max available version library installed.
     ./${cmd_name} build
    The same as above but not using the defaults.
      ./${cmd_name} --base-image amd64/ubuntu --platform amd64 --qt-ver 'max' build

  Notes:
     The file '.qt-lib-dir' overrides the default Qt framework's location of '${qt_lib_dir}'.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	show_help
	exit 1
fi

# Check if the required credential file exists.
if [[ ! -f "${script_dir}/.nexus-credentials" ]]; then
	WriteLog "! File '${script_dir}/.nexus-credentials' is required!"
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

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'hp:y' --long 'help,platform:,base-image:,project:,base-ver:,qt-ver:,zip,yes' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi

eval set -- "${temp}"
unset temp
while true; do
	case "$1" in

		-h | --help)
			show_help
			exit 0
			;;

		-y | --yes)
			flag_pause=false
			shift
			;;

		--base-image)
			base_img_name="${2}"
			shift 2
			continue
			;;

		--base-ver)
			base_img_tag="${2}"
			shift 2
			continue
			;;

		--platform)
			platform="${2}"
			shift 2
			# When the platform does not match the default base image modify it.
			if [[ "${platform}" == 'arm64' && "${base_img_name}" =~ ^amd64 ]]; then
				base_img_name='arm64v8/ubuntu'
				WriteLog "# Defaulting platform '${platform}' to base image '${base_img_name}'."
				architecture='aarch64'
			elif [[ "${platform}" == 'amd64' && "${base_img_name}" =~ ^arm64 ]]; then
				base_img_name='amd64/ubuntu'
				WriteLog "# Defaulting platform '${platform}' to base image '${base_img_name}'."
				architecture='x86_64'
			fi
			continue
			;;

		--zip)
			zip_format=true
			shift 1
			continue
			;;

		--qt-ver)
			qt_ver="${2}"
			shift 2
			continue
			;;

		-p | --project)
			if [[ ! -d "${2}" ]]; then
				WriteLog "! Project directory '${2}' does not exist!"
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

# Determine the used file compression.
if ${zip_format}; then
	# File compression with zip.
	compress_suffix=".zip"
	compress_exclude="-x"
	compress_cmd=(zip)
	! $flag_pause && compress_cmd+=(--quiet)
	compress_cmd+=(--display-bytes --recurse-paths)
	# Command storing symlinks.
	compress_cmd_lnk=("${compress_cmd[@]}" --symlinks)
else
	# File compression with tar and gzip.
	compress_suffix=".tar.gz"
	compress_exclude="--exclude"
	compress_cmd_lnk=(tar)
	$flag_pause && compress_cmd_lnk+=(--verbose)
	compress_cmd_lnk+=(--owner=0 --group=0)
	compress_cmd_lnk+=(--create --gzip)
	compress_cmd=("${compress_cmd_lnk[@]}")
	compress_cmd_lnk+=(--file)
	# Command storing symlinks as thew file they point to.
	compress_cmd+=(--dereference --file)
fi

# Location for the Qt libraries other then the default.
if [[ ! -d qt_lib_dir && ! -L qt_lib_dir ]]; then
	qt_lib_dir_file=".qt-lib-dir"
	# Check if the qt libs directory file exists.
	if [[ -f "${script_dir}/${qt_lib_dir_file}" ]]; then
		# Read the first line of the file and strip the newline.
		qt_lib_dir="$(head -n 1 "${script_dir}/${qt_lib_dir_file}" | tr -d '\n' | tr -d '\n' | tr -d '\r')"
		if [[ ! -d "${qt_lib_dir}/" ]]; then
			WriteLog "# Qt Library directory given in '${qt_lib_dir_file}' does not exist!"
		fi
	fi
fi

# When no Qt version given find the newest one.
if [[ "${qt_ver}" == 'max' ]]; then
	qt_ver="$(basename "$(find "${qt_lib_dir}/lnx-${architecture}/" -maxdepth 1 -regextype posix-extended \
		-regex '^.*[0-9]+\.[0-9]+\.[0-9]+$' | sort --reverse --version-sort | head -n 1)")"
	if [[ -z "${qt_ver}" ]]; then
		WriteLog "! No Qt version directory found in '${qt_lib_dir}/lnx-${architecture}'!"
	else
		WriteLog "# Qt version '${qt_ver}' found in directory '${qt_lib_dir}/lnx-${architecture}'."
	fi
fi

# Assign the correct image tag.
if [[ -n "${qt_ver}" ]]; then
	img_tag="${base_img_tag}-${qt_ver}"
else
	img_tag="${base_img_tag}"
fi

# Form the Windows 64 toolchain name.
w64_toolchains+=()
w64_toolchains+=("w64-x86_64-mingw-1320-posix")
w64_toolchains+=("w64-x86_64-msvc-2022")
w64_toolchains+=("w64-x86_64-msvc-2026")

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

if [[ -n "${cmd}" ]]; then
	WriteLog "#
  Qt version           : ${qt_ver}
  Targeted Platform    : ${platform}
  Architecture         : ${architecture}
  Base image tag       : ${base_img_tag}
  Base image name      : ${base_img_name}
  Image tag            : ${img_tag}
  Image name           : ${img_name}
  Container name       : ${container_name}
  Temporary directory  : ${temp_dir}
  Qt library directory : ${qt_lib_dir}
  Compression Suffix   : ${compress_suffix}
  Nexus relative path  : ${raw_lib_offset}
  Windows toolchains   : ${w64_toolchains[*]}
	"
	${flag_pause} && read -rp "Continue with command '${cmd}' [y/N]?" && if [[ $REPLY != [yY] ]]; then
		exit 0
	fi
fi

case "${cmd}" in

	timestamp)
		date +'%FT%T' >"${timestamp_file}"
		WriteLog "# Timestamp file set to: $(cat "${timestamp_file}")"
		;;

	build-push)
		"${0}" --qt-ver '' build
		"${0}" build
		"${0}" --qt-ver '' push
		"${0}" push
		;;

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

	qt-lnx)
		# Check if the Qt version library directory exists.
		ver_dir="${qt_lib_dir}/lnx-${architecture}/${qt_ver}"
		if [[ ! -d "${ver_dir}" ]]; then
			WriteLog "! Qt version directory '${ver_dir}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-lnx-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Compressing Qt Library to file: ${zip_file}"
		# Remove the current compressed file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for the compressed to store the correct path.
		pushd "${qt_lib_dir}/lnx-${architecture}/"
		"${compress_cmd_lnk[@]}" "${zip_file}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${zip_file}"
		;;

	qt-lnx-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-lnx-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Uploading Qt Library compressed file: ${zip_file}"
		# Upload file Linux Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/qt/"
		;;

	qt-win)
		# Check if the Qt version library directory exists.
		ver_dir="${qt_lib_dir}/win-${architecture}/${qt_ver}"
		if [[ ! -d "${ver_dir}" ]]; then
			WriteLog "! Qt version directory '${ver_dir}' does not exist."
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-win-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Compressing Qt Library to file: ${zip_file}"
		# Remove the current compressed file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for compressed file to store the correct path.
		pushd "${qt_lib_dir}/win-${architecture}/"
		# Compress all files except Windows executables.
		"${compress_cmd_lnk[@]}" "${zip_file}" "${qt_ver}/mingw_64/"{bin,lib,include,mkspecs,plugins}
		# "${compress_exclude}" '*.exe'
		popd
		ls -lah "${zip_file}"
		;;

	qt-win-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-win-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Uploading Qt Library compressed file: ${zip_file}"
		# Upload file Linux Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/qt/"
		;;

	qt-w64)
		# Check if the Qt version library directory exists.
		ver_dir="${qt_lib_dir}/w64-${architecture}/${qt_ver}"
		if [[ ! -d "${ver_dir}" ]]; then
			WriteLog "Qt version directory '${ver_dir}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-w64-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Compressing Qt Library to file: ${zip_file}"
		# Remove the current compressed file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for the compressed file to store the correct path.
		pushd "${qt_lib_dir}/w64-${architecture}/"
		# Fix the permissions on exe and dll and other files for Cygwin to make them executable.
		find . \( -iname "*.dll" -o -iname "*.exe" -o -iname "*.cmd" -o -iname "*.bat" \) -exec chmod +x {} \;
		# Compress the library files except 'libexec' since it does not exist for Windows.
		"${compress_cmd_lnk[@]}" "${zip_file}" "${qt_ver}"/{mingw_64,msvc_64}/{bin,lib,include,mkspecs,plugins}
		popd
		ls -lah "${zip_file}"
		;;

	qt-w64-up)
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/qt-w64-${architecture}-${qt_ver}${compress_suffix}"
		WriteLog "# Uploading Qt Library compressed file: ${zip_file}"
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/qt/"
		;;

	qt-w64-tools)
		# Check if the Qt version library directory exists for Windows.
		qt_tools_dir="${qt_lib_dir}/../toolchain"
		for w64_tc in "${w64_toolchains[@]}"; do
			if [[ ! -d "${qt_tools_dir}/${w64_tc}" ]]; then
				WriteLog "Qt Tools directory '${qt_tools_dir}/${w64_tc}' does not exist!"
				exit 1
			fi
			# Form the zip-filepath using the found or set Qt version.
			zip_file="${temp_dir}/${w64_tc}${compress_suffix}"
			# Remove the current compressed file.
			[[ -f "${zip_file}" ]] && rm "${zip_file}"
			# Change directory in order for the compressed file to store the correct path.
			pushd "${qt_tools_dir}"
			WriteLog "# Fixing permissions on exe and dll and other files to make them executable in Cygwin."
			# Fix the permissions on exe and dll and other files for Cygwin to make them executable.
			find . \( -iname "*.dll" -o -iname "*.exe" -o -iname "*.cmd" -o -iname "*.bat" \) -exec chmod +x {} \;
			WriteLog "# Compressing Windows toolchain '${w64_tc}'."
			# Compress the GNU compiler version.
			"${compress_cmd_lnk[@]}" "${zip_file}" "${w64_tc}"
			popd
		done
		# List the compressed files.
		for w64_tc in "${w64_toolchains[@]}"; do
			ls -lah "${temp_dir}/${w64_tc}${compress_suffix}"
		done
		;;

	qt-w64-tools-up)
		for w64_tc in "${w64_toolchains[@]}"; do
			# Form the zip-filepath using the found or set Qt version.
			zip_file="${temp_dir}/${w64_tc}${compress_suffix}"
			WriteLog "# Uploading Windows toolchain '${w64_tc}' compressed file: ${zip_file}"
			# Upload file Windows Qt library.
			curl \
				--progress-bar \
				--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
				--upload-file "${zip_file}" \
				"${NEXUS_SERVER_URL}/${raw_lib_offset}/toolchain/"
		done
		;;

	wine-tools)
		tool_combi="win-x86_64-cmake-4.2-combi"
		combi_dir="${qt_lib_dir}/../toolchain/${tool_combi}"
		if [[ ! -d "${combi_dir}" ]]; then
			WriteLog "! Tools directory '${combi_dir}' does not exist!"
			exit 1
		fi
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${tool_combi}${compress_suffix}"
		# Remove the current compressed file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for the compressed file to store the correct path.
		pushd "${combi_dir}"
		# Fix the permissions on exe and dll and other files for Cygwin to make them executable.
		WriteLog "# Compressing Tool Combination '${tool_combi}'."
		# Compress all symlinked files and directories as if the are actual.
		"${compress_cmd[@]}" "${zip_file}" ./
		popd
		ls -lah "${zip_file}"
		;;

	wine-tools-up)
		tool_combi="win-x86_64-cmake-4.2-combi"
		# Form the zip-filepath using the found or set Qt version.
		zip_file="${temp_dir}/${tool_combi}${compress_suffix}"
		WriteLog "# Uploading Wine tool combi compressed file: ${zip_file}"
		# Upload file Windows Qt library.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${zip_file}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/toolchain/"
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
			WriteLog "# Stopping containers using image '${platform}/${img_name}:${img_tag}'."
			docker stop $(docker ps -a -q --filter ancestor="${platform}/${img_name}:${img_tag}")
		fi
		build_args=("BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}:${base_img_tag}")
		build_args+=("PLATFORM=${platform}")
		build_args+=("NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
		build_args+=("NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
		build_args+=("QT_VERSION=${qt_ver}")
		build_args+=("NEXUS_TIMESTAMP=$(cat "${timestamp_file}" 2>/dev/null || date +'%FT%T')")
		build_args+=("COMPRESSION_SUFFIX=${compress_suffix}")
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
		"${0}" --yes --base-ver "${base_img_tag}" --qt-ver "${qt_ver}" run -- /home/user/bin/versions.sh
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
		dckr_cmd+=(--security-opt apparmor:unconfined)
		dckr_cmd+=(--network host)
		dckr_cmd+=(--hostname "${hostname}")
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
		#dckr_cmd+=(--volume "${work_dir}/bin:/usr/local/bin/test:ro")
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--volume "${script_dir}:/mnt/script:ro")
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
			WriteLog "# Container ID is '${cntr_id}' and performing '${cmd}' command."
			docker "${cmd}" "${cntr_id}"
		else
			WriteLog "# Container '${container_name}' is not running."
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
		# When a command is given.
		if [[ -n "${cmd}" ]]; then
			if "${script_dir}/nexus-docker.sh" "${cmd}"; then
				exit 0
			fi
			WriteLog "! Command '${cmd}' is invalid."
		fi
		show_help
		exit 1
		;;

esac
