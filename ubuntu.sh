#!/bin/bash
#set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Set the image name to be used.
IMG_NAME="nexus.scanframe.com/ubuntu:22.04"
# Name of the container to be used.
CONTAINER_NAME="apt-repo"
# Hostname for the docker container.
HOSTNAME="apt-repo"

##
# Function to get the Docker container status.
#
function get_status {
	docker container list --all --format "{{.Status}}" --filter Name="${CONTAINER_NAME}"
}

##
# Start or attach to Docker container or create one when it does not exist yet.
#
function run_container {
	local STATUS
	# Get the container status.
	STATUS="$(get_status)"
	# When the container does not exists create it.
	if [[ -z "${STATUS}" ]]; then
		echo "Creating container '${CONTAINER_NAME}' starting."
		docker run \
			--name "${CONTAINER_NAME}" \
			--interactive \
			--tty \
			--privileged \
			--net=host \
			--host="${HOSTNAME}" \
			--env LOCAL_USER="$(id -u):$(id -g)" \
			--env DISPLAY \
			--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro" \
			--volume "${SCRIPT_DIR}/apt-repo:/root/apt-repo:ro" \
			--detach \
			"${IMG_NAME}"
	# When the container exists and is not running restart it.
	elif [[ "${STATUS}" =~ ^Exited ]]; then
		echo "Restarting container '${CONTAINER_NAME}'."
		docker restart "${CONTAINER_NAME}"
	elif [[ "${STATUS}" =~ ^Up ]]; then
		echo "Container '${CONTAINER_NAME}' is running '${STATUS}'."
	else
		echo "Container '${CONTAINER_NAME}' has unexpected status '${STATUS}'!"
		exit 1
	fi
	# Get the container status again and it needs to be 'Up' to b enable to attach to it.
	if [[ "$(get_status)" =~ ^Up ]]; then
		docker exec \
			--interactive \
			--tty \
			--env LOCAL_USER="$(id -u):$(id -g)" \
			--env DISPLAY \
			"${CONTAINER_NAME}" "${@}"
	else
		echo "Failed to attach to container '${CONTAINER_NAME}'."
	fi
}

# Stop or kill the container.
if [[ $# -eq 1 && ("${1}" == "stop" || "${1}" == "kill") ]]; then
	# Stop this docker container only.
	cntr_id="$(docker ps --filter name="${CONTAINER_NAME}" --quiet)"
	if [[ -n "${cntr_id}" ]]; then
		echo "Container ID is '${cntr_id}' and performing '${1}' command."
		docker "${1}" "${cntr_id}"
	else
		echo "Container '${CONTAINER_NAME}' is not running."
	fi
else
	# By default run bash.
	if [[ $# -eq 0 ]]; then
		# Execute the build script from the Docker image.
		run_container /bin/bash
	else
		# Execute the build script from the Docker image.
		run_container /bin/bash -c "${*}"
	fi
fi
