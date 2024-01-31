#!/bin/bash

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

# Check if the required credential file exists.
if [[ ! -f "${SCRIPT_DIR}/.nexus-credentials" ]]; then
	echo "File '${SCRIPT_DIR}/.nexus-credentials' is required."
	exit 1
fi

# Read the credentials from non repository file.
source "${SCRIPT_DIR}/.nexus-credentials"

REPO_URL="${NEXUS_SERVER_URL}/repository/"
USER="${NEXUS_USER}"
PASSWORD="${NEXUS_PASSWORD}"
BUCKET="${NEXUS_REPO_NAME}"

KEEP_IMAGES=0

# Get the number of images.
IMAGES="$(curl --silent -X GET -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -u "${USER}:${PASSWORD}" "${REPO_URL}${BUCKET}/v2/_catalog" | jq .repositories | jq -r '.[]')"

echo "Docker Images: $(echo "${IMAGES}" | sed ':a;N;$!ba;s/\n/, /g')"

# Iterate through the images.
for IMAGE_NAME in ${IMAGES}; do

	echo "* Image: ${IMAGE_NAME}"

	TAGS=$(curl --silent -X GET -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -u "${USER}:${PASSWORD}" "${REPO_URL}${BUCKET}/v2/${IMAGE_NAME}/tags/list" | jq .tags | jq -r '.[]')
	TAG_COUNT=$(echo "${TAGS}" | wc -w)
	TAG_COUNT_DEL="$((TAG_COUNT - KEEP_IMAGES))"
	COUNTER=0

	echo "  Tags[${TAG_COUNT}]: $(echo "${TAGS}" | sed ':a;N;$!ba;s/\n/, /g')"

	# Skip removal when the images to keep is smaller then set.
	if [[ "${KEEP_IMAGES}" -gt "${TAG_COUNT}" ]]; then
		echo "  Nothing to delete."
		continue
	fi

	for TAG in ${TAGS}; do
		COUNTER=$((COUNTER + 1))
		# When the counter does not cross the threshold break.
		if [[ "${COUNTER}" -gt "${TAG_COUNT_DEL}" ]]; then
			break
		fi

		IMAGE_SHA=$(curl --silent -I -X GET -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -u "${USER}:${PASSWORD}" "${REPO_URL}${BUCKET}/v2/${IMAGE_NAME}/manifests/$TAG" | grep Docker-Content-Digest | cut -d ":" -f3 | tr -d '\r')
		echo "DELETE ${TAG} ${IMAGE_SHA}"
		DEL_URL="${REPO_URL}${BUCKET}/v2/${IMAGE_NAME}/manifests/sha256:${IMAGE_SHA}"
		# Uncomment next line to actual delete.
		#RET="$(curl --silent -k -X DELETE -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -u ${USER}:${PASSWORD} "${DEL_URL}")"
		echo curl --silent -k -X DELETE -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' "${DEL_URL}"

	done
done
