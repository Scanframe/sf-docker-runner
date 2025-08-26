#!/bin/bash

sources_file="/etc/apt/sources.list.d/docker-ce.sources"
# Check if the sources file exists when not create it.
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