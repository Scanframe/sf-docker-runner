#!/usr/bin/env bash
#set -x

# Get the script directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add local user. Either use the LOCAL_USER_ID if passed in at runtime or fallback.
USER_ID=${LOCAL_USER_ID:-9001}
GROUP_ID=${LOCAL_GROUP_ID:-9001}

echo "Setting user 'user' uid/gid to ${USER_ID}/${GROUP_ID}."
usermod -u "${USER_ID}" user || exit 1
groupmod -g "${GROUP_ID}" user || exit 1
usermod -aG sudo user || exit 1
usermod -aG "${WINE_USER}" user || exit 1

if [[ $# -ne 0 ]]; then
	# Execute CMD passed by the user when starting the image.
	sudo -u user -- "${@}"
fi
