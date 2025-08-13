#!/bin/bash
#set -x
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Set the image name to be used.
img_name="nexus.scanframe.com/amd64/ubuntu:24.04"
# Name of the container to be used.
container_name="ubuntu-24.04"
# Hostname for the docker container.
host_name="ubuntu"

##
# Function to get the Docker container status.
#
function get_status {
	docker container list --all --format "{{.Status}}" --filter Name="${container_name}"
}

##
# Start or attach to Docker container or create one when it does not exist yet.
#
function run_container {
	local status
	# Get the container status.
	status="$(get_status)"
	# When the container does not exists create it.
	if [[ -z "${status}" ]]; then
		echo "Creating container '${container_name}' starting."
		docker run \
			--name "${container_name}" \
			--interactive \
			--tty \
			--privileged \
			--net=host \
			--hostname="${host_name}" \
			--user="$(id -u):$(id -g)" \
			--env DISPLAY \
			--volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro" \
			--volume "${script_dir}/project:/project:rw" \
			--detach \
			"${img_name}"
	# When the container exists and is not running restart it.
	elif [[ "${status}" =~ ^Exited ]]; then
		echo "Restarting container '${container_name}'."
		docker restart "${container_name}"
	elif [[ "${status}" =~ ^Up ]]; then
		echo "Container '${container_name}' is running '${status}'."
	else
		echo "Container '${container_name}' has unexpected status '${status}'!"
		exit 1
	fi
	# Get the container status again and it needs to be 'Up' to b enable to attach to it.
	if [[ "$(get_status)" =~ ^Up ]]; then
		docker exec \
			--interactive \
			--tty \
			--env DISPLAY \
			"${container_name}" "${@}"
	else
		echo "Failed to attach to container '${container_name}'."
	fi
}

# Stop or kill the container.
if [[ $# -eq 1 && ("${1}" == "stop" || "${1}" == "kill") ]]; then
	# Stop this docker container only.
	cntr_id="$(docker ps --filter name="${container_name}" --quiet)"
	if [[ -n "${cntr_id}" ]]; then
		echo "Container ID is '${cntr_id}' and performing '${1}' command."
		docker "${1}" "${cntr_id}"
	else
		echo "Container '${container_name}' is not running."
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
