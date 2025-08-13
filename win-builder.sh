#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Set the base image tag of the FROM statement used.
base_img_tag="24.04"
# Default platform for this.
platform="amd64"
# Set the base image name of the FROM statement used.
base_img_name="amd64/ubuntu:${base_img_tag}"
# Set the image name to be used.
img_name="wine"
# Set container name to be used.
container_name="wine-borland"
# Hostname for the docker container.
hostname="wine-borland"
# Get temporary directory of this OS.
temp_dir="$(dirname "$(mktemp tmp.XXXXXXXXXX -ut)")"
# Location of the Borland C++ application.
win_apps_dir="${HOME}/windows"
# The image tag for displaying in help for now.
img_tag="${base_img_tag}-borland"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"
# Offset of the Nexus server URL to the zipped application.
raw_app_offset="repository/shared/application/windows"
# When running from a 'aarch64' machine set some other defaults.
if [[ "$(uname -m)" != 'x86_64' ]]; then
	echo "Can only build from a x86_64 machine."
fi

# Prints the help.
#
function ShowHelp {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command> [<arguments...>]
  Execute an action for docker and/or it's container.

  Options:
    -h, --help    : Show this help.
    -p, --project : Project directory which is mounted in '/mnt/project' and has a symlink '~/project'.
    --platform    : Platform defaults to '${platform}' available is also 'arm64'.

  Commands:
    app-zip     : Compresses the application directories specified by the other arguments into a zip-files.
    app-zip-up  : Upload compressed application directories specified by the other arguments into a zip-files to the Nexus repository.
    build       : Builds the docker image prefix named and tagged like '${platform}/${img_name}:${img_tag}'.
    push        : Pushes the docker image to the self-hosted Nexus repository.
    pull        : Pulls the docker image from the self-hosted Nexus repository.
    base-push   : Pushes the base image '${base_img_name}' to the self-hosted Nexus repository.
    runx        : Runs the docker container named '${container_name}' in the foreground mounting the passed project directory using the host's X-server.
    run         : Same as 'runx' using a fake X-server.
    stop        : Stops the container named '${container_name}' running in the background.
    kill        : Kills the container named '${container_name}' running in the background.
    status      : Return the status of named '${container_name}' the container running in the background.
    attach      : Attaches to the  in the background running container named '${container_name}'.
    versions    : Shows versions of most installed applications within the container.
    docker-push : Push '${container_name}' to userspace '${DOCKER_USER}' on docker.com.

  Notes:
    The file '.win-app-dir' overrides the default application location of '${win_apps_dir}'."
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
docker_file="${work_dir}/win.Dockerfile"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'hp:' --long 'help,platform:,project:' -n "$(basename "${0}")" -- "$@")
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

# Location for the BCB application other then the default.
if [[ ! -d win_apps_dir && ! -L win_apps_dir ]]; then
	win_apps_dir_file=".win-app-dir"
	# Check if the qt libs directory file exists.
	if [[ -f "${script_dir}/${win_apps_dir_file}" ]]; then
		# Read the first line of the file and strip the newline.
		win_apps_dir="$(head -n 1 "${script_dir}/${win_apps_dir_file}" | tr -d '\n' | tr -d '\n' | tr -d '\r')"
		if [[ ! -d "${win_apps_dir}/" ]]; then
			WriteLog "# BCB application directory given in '${win_apps_dir_file}' does not exist!"
		fi
	fi
fi

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

case "${cmd}" in

	app-zip)
		# Check if app directories were given.
		if [[ $# -eq 0 ]]; then
			echo "No application directories given."
		else
			for app_subdir in "${@}"; do
				# Check if the application directory exists.
				if [[ ! -d "${win_apps_dir}/${app_subdir}" ]]; then
					echo "Application directory '${win_apps_dir}/${app_subdir}' does not exist!"
					exit 1
				fi
				# Form the zip-filepath using the application directory name.
				zip_file="${temp_dir}/${app_subdir}.zip"
				echo "Creating zip-file: ${zip_file}"
				# Remove the current zip file.
				[[ -f "${zip_file}" ]] && rm "${zip_file}"
				# Change directory in order for zip to store the correct path.
				pushd "${win_apps_dir}/${app_subdir}"
				zip --display-bytes --recurse-paths --symlinks "${zip_file}" ./*
				popd
				ls -lah "${zip_file}"
			done
		fi
		;;

	app-zip-up)
		# Check if app directories were given.
		if [[ $# -eq 0 ]]; then
			WriteLog "No application directories given."
		else
			for app_subdir in "${@}"; do
				# Form the zip-filepath using the application directory name.
				zip_file="${temp_dir}/${app_subdir}.zip"
				# Upload file of the application.
				curl \
					--progress-bar \
					--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
					--upload-file "${zip_file}" \
					"${NEXUS_SERVER_URL}/${raw_app_offset}/"
			done
		fi
		;;

	base-push)
		docker pull "${base_img_name}"
		docker tag "${base_img_name}" "${NEXUS_REPOSITORY}/${base_img_name}"
		docker image push "${NEXUS_REPOSITORY}/${base_img_name}"
		;;

	push)
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${img_name}"
		# Push the repository.
		docker image push "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}"
		;;

	docker-push)
		docker_img_name="${DOCKER_USER}/${img_name%%:*}"
		# Add tag to having the correct prefix so it can be pushed to a private repository.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${platform}/${docker_img_name}"
		# Push the repository.
		docker image push "${platform}/${docker_img_name}"
		;;

	pull)
		# Logout from any current server.
		docker logout
		# Pull the image from the Nexus server.
		docker pull "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}"
		# Add tag without the Nexus server prefix.
		docker tag "${NEXUS_REPOSITORY}/${platform}/${img_name}:${img_tag}" "${platform}/${img_name}:${img_tag}"
		;;

	build | buildx)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${platform}/${img_name}:${img_tag}")" ]]; then
			echo "Stopping containers using image '${platform}/${img_name}:${img_tag}'."
			docker stop $(docker ps -a -q --filter ancestor="${platform}/${img_name}:${img_tag}")
		fi
		# Build the image.
		dckr_cmd=(docker)
		dckr_cmd+=("${cmd}")
		dckr_cmd+=(--platform "linux/${platform}")
		dckr_cmd+=(--progress plain)
		dckr_cmd+=(--build-arg "PLATFORM=${platform}")
		dckr_cmd+=(--build-arg "BASE_IMG=${NEXUS_REPOSITORY}/${base_img_name}")
		dckr_cmd+=(--build-arg "NEXUS_SERVER_URL=${NEXUS_SERVER_URL}")
		dckr_cmd+=(--build-arg "NEXUS_RAW_LIB_URL=${NEXUS_SERVER_URL}/${raw_lib_offset}")
		dckr_cmd+=(--build-arg "NEXUS_WIN_APP_URL=${NEXUS_SERVER_URL}/${raw_app_offset}")
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
		"${0}" run -- /usr/local/bin/test/versions.sh
		;;

	run | runx)
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
		dckr_cmd+=(--platform "linux/${platform}")
		dckr_cmd+=(--device /dev/fuse)
		dckr_cmd+=(--cap-add SYS_ADMIN)
		dckr_cmd+=(--net=host)
		dckr_cmd+=(--hostname "${hostname}")
		dckr_cmd+=(--security-opt apparmor:unconfined)
		dckr_cmd+=(--name="${container_name}")
		# Script home/user/bin/entrypoint.sh picks this up or uses the id' from the mounted project user.
		dckr_cmd+=(--env LOCAL_USER="$(id -u):$(id -g)")
		dckr_cmd+=(--user user:user)
		dckr_cmd+=(--env DEBUG=1)
		dckr_cmd+=(--volume "${work_dir}/bin:/usr/local/bin/test:ro")
		if [[ "${cmd}" == "runx" ]]; then
			dckr_cmd+=(--env DISPLAY)
			dckr_cmd+=(--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro")
		fi
		if true; then
			dckr_cmd+=(--volume "${win_apps_dir}:/mnt/drive_p:ro")
		fi
		dckr_cmd+=(--volume "${project_dir}:/mnt/project:rw")
		dckr_cmd+=(--workdir "/mnt/project/")
		dckr_cmd+=("${platform}/${img_name}:${img_tag}")
		dckr_cmd+=("${@}")
		"${dckr_cmd[@]}"
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
