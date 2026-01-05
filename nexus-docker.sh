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
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	if [[ "$#" -eq 0 ]]; then
		echo "Usage: ${cmd_name} [<options>] <command>
  Execute an actions for docker and/or it's container.

  Options:
    -h, --help    : Show this help.

  Commands:"
	else
		echo -n "
  Command passed to 'nexus-docker.sh':"
	fi
	echo -e "
    required    : Installs the required dependent packages.
    du          : Show docker disk usage.
    local       : Docker client list local images.
    list        : List remote images on Nexus server.
    login       : Log Docker in on the self hosted Nexus registry repository.
    docker-login: Log Docker in on docker.com registry as '${DOCKER_USER}'.
    docker-list : List Docker images and tags from the docker.com registry from user '${DOCKER_USER}'.
    logout      : Log docker out from any repository.
    prune       : Removes build cache and internal/frontend images.
    remove      : Removes a local image. (not implemented)
    wine-reg    : Compress registry files from common/wine-reg.
    wine-reg-up : Upload compressed registry files to Nexus raw repository.

  Docker credentials are finally stored in: ${HOME}/.docker/config.json

"
}

# Installs required packages.
#
function install_required {
	local pkgs pkg sources_file
	# Packages needed to be installed.
	pkgs=("docker-ce" "qemu-user-static")
	# Iterate through the packages one by one. ()
	for pkg in "${pkgs[@]}"; do
		# Check if a package is installed by checking the package listing string.
		if [[ "$(apt -qq list "${pkg}" 2>/dev/null | head -n 1)" =~ (\[installed\]) ]]; then
			echo "Package '${pkg}' already installed..."
			continue
		fi
		# Docker CE needs its own repository.
		if [[ "${pkg}" == "docker-ce" ]]; then
			# Check if the sources file exists when not create it.
			sources_file="/etc/apt/sources.list.d/docker-ce.sources"
			if [[ ! -f "${sources_file}" ]]; then
				echo "Installing file: ${sources_file}"
				# Create the sources file.
				cat <<EOD | sudo tee "${sources_file}" >/dev/null
Types: deb
URIs: https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')
Suites: $(lsb_release -cs)
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By:
$(wget -qO- "https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg" | sed 's/^/ /')
EOD
			fi
		fi
		# Perform the install of the package.
		if ! sudo apt-get --yes install "${pkg}"; then
			echo "Install of package '${pkg}' failed!"
			exit 1
		fi
	done
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	show_help
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
temp=$(getopt -o 'hp:' --long 'help,help-short,project:' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi

eval set -- "$temp"
unset temp
while true; do
	case "$1" in

		-h | --help)
			show_help
			exit 0
			;;

		--help-short)
			show_help 1
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

	required)
		install_required
		;;

	du)
		docker system df
		;;

	prune)
		# Prune build cache.
		docker buildx prune --all
		;;

	local)
		docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}"
		;;

	list)
		curl --silent \
			--user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
			-X 'GET' \
			"${NEXUS_SERVER_URL}/service/rest/v1/components?repository=${NEXUS_REPO_NAME}" |
			jq -r '.items[]|(.name + "|" + .version + "|" + .id + "|" + (.assets[0].fileSize / 1000.0 | tostring) + " GB" + "|" + (.assets[0].lastModified[:19] | gsub("T"; " ")))' |
			column --table --separator "|" --table-columns "Image/Name,Tag/Version,Id,Size,Modified At" --output-separator "  "
		;;

	login)
		echo "Login to private Nexus registry: ${NEXUS_REPOSITORY}"
		echo -n "${NEXUS_PASSWORD}" | docker login --username "${NEXUS_USER}" --password-stdin "${NEXUS_REPOSITORY}"
		;;

	docker-login)
		echo "Login to Docker.com registry"
		echo -n "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USER}" --password-stdin
		;;

	docker-list)
		# Get list of repositories
		repos=$(curl --silent "https://hub.docker.com/v2/repositories/${DOCKER_USER}/?page_size=100" | jq -r '.results[].name')
		# Loop through each repository and get tags
		{
			for repo in $repos; do
				curl --silent "https://hub.docker.com/v2/repositories/${DOCKER_USER}/${repo}/tags?page_size=100" |
					jq -r "\"${DOCKER_USER}/${repo}:\" + (.results[] | .name + \"|\" + (.full_size / 1e9 | tostring) + \" GB\" + \"|\" + .digest + \"|\" + .tag_last_pushed)"
			done
		} | column --table --separator '|' --table-columns 'Image/Tag,Size,Digest,Last Pushed'
		;;

	logout)
		docker logout "${NEXUS_REPOSITORY}"
		;;

	remove)
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
		show_help
		exit 1
		;;

esac
