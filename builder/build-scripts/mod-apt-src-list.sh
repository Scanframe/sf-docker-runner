#!/bin/bash

# On first error exit.
set -e

# Get the scripts directory.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only for x86_64 machines.
if [[ "$(uname -m)" != 'x86_64' ]]; then
	echo "Script is only applies to x86_64 machines."
	exit 0
fi

# Determine if this is for testing.
if [[ "${script_dir}" =~ build-scripts ]]; then
	sources_files=("${script_dir}/test/"*.sources)
	list_files=("${script_dir}/test/"*.list)
else
	sources_files=(/etc/apt/sources.list.d/*.sources)
	list_files=(/etc/apt/sources.list.d/*.list)
fi

# Iterate through the list files.
for fn in "${list_files[@]}"; do
	echo "Adding architecture to list file: ${fn}"
	sed --in-place --regexp-extended 's/^(deb|deb-src)\s+(http|ftp)/\1 [arch=amd64,i386] \2/' "${fn}"
done

# Iterate through the sources files.
for fn in "${sources_files[@]}"; do
	# Modify the file if 'Architectures:' is not present.
	if grep --quiet '^Architectures:' "${fn}"; then
		echo "Skipping setting 'Architectures:' on: ${fn}"
	else
		echo "Adding architecture to source file: ${fn}"
		sed --in-place '/^Types: deb$/a\Architectures: amd64 i386' "${fn}"
	fi
	#> "${fn}.tmp"
done
