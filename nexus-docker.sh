#!/usr/bin/env bash

# Exit at first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Temporary file used to upload wine registry.
wine_reg_tgz="/tmp/wine-reg.tgz"
# Offset of the Nexus server URL to the zipped libraries.
raw_lib_offset="repository/shared/library"

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

  Commands:
    du          : Show docker disk usage.
    local       : Docker client list local images.
    list        : List remote images on server.
    login       : Log Docker in on the Nexus repository.
    logout      : Log docker out from any repository.
    prune       : Remove all Docker build cache.
    login       : Log Docker in on the Nexus repository.
    logout      : Log docker out from any repository.
    remove      : Removes a local image. (not implemented)
    wine-reg    : Compress registry files from common/wine-reg.
    wine-reg-up : Upload compressed file to Nexus raw repository.
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

	du)
		docker system df
		;;

	prune)
		# Prune build cache.
		docker buildx prune --all
		;;

	local)
		docker image ls --all "*"
		;;

	list)
		curl --silent \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			-X 'GET' \
			"${NEXUS_SERVER_URL}/service/rest/v1/components?repository=${NEXUS_REPO_NAME}" |
			jq -r '.items[]|(.repository + " " + .name + " " + .version + " " + .id)' |
			column --table --separator " " --table-columns "Repository,Name,Version,Id" --output-separator " | "
#		curl --silent \
#			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
#			-X 'GET' \
#			"${NEXUS_SERVER_URL}/service/rest/v1/search/components?repository=${NEXUS_REPO_NAME}" |
#			jq -r '.items[]|(.path + " " + .uploader + " " + .lastModified)' |
#			column --table --separator " " --table-columns "Path,Uploader,Modified" --output-separator " | "
		;;

	login)
		echo "Login Docker registry: ${NEXUS_REPOSITORY}"
		echo -n "${NEXUS_PASSWORD}" | docker login --username "${NEXUS_USER}" --password-stdin "${NEXUS_REPOSITORY}"
		;;

	logout)
		docker logout "${NEXUS_REPOSITORY}"
		;;

	rm | remove)
		echo "Must still be implemented."
		;;

	wine-reg)
		# Compress the registry files.
		pushd "${script_dir}/builder/wine-reg" >/dev/null && tar -czf "${wine_reg_tgz}" system.reg user.reg userdef.reg
		popd >/dev/null
		echo "Compressed Wine registry files in: ${wine_reg_tgz}"
		;;

	wine-reg-up)
		# Upload Wine registry compressed file to Nexus.
		curl \
			--progress-bar \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			--upload-file "${wine_reg_tgz}" \
			"${NEXUS_SERVER_URL}/${raw_lib_offset}/wine-reg.tgz"
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		ShowHelp
		exit 1
		;;

esac
