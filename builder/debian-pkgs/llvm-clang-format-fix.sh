#!/usr/bin/env bash

# Get the script directory.
#script_dir="$(cd "$(dirname "${0}")" && pwd)"

if [[ "$1" == "download" ]]; then

	sudo apt-get update
	# 1. Download the meta-package from LLVM
	apt-get download clang-format

elif [[ "$1" == "unpack" ]]; then

	# 2. Extract the package contents and metadata into a directory
	dpkg-deb -R clang-format_*.deb custom-clang-format

elif [[ "$1" == "fix" ]]; then

	# 3. Change the dependency from clang-format-23 to clang-format-24 in the control file
	sed -i 's/clang-format-23 (>= 1:23~)/clang-format-24/g' custom-clang-format/DEBIAN/control
	sed -i '/^Version:/ { /+local1$/! s/$/+local1/ }' custom-clang-format/DEBIAN/control
	# 3. Update any physical symlink inside the extracted filesystem
	find custom-clang-format -type l -lname '*23*' -exec sh -c '
    for link; do
      target=$(readlink "$link" | sed "s/23/24/g")
      echo "Fixing: $target > $link"
      ln -sf "$target" "$link"
    done
  ' sh {} +


elif [[ "$1" == "pack" ]]; then

	# 4. Rebuild the updated .deb package
	dpkg-deb -b custom-clang-format clang-format-fix.deb

elif [[ "$1" == "install" ]]; then

	# 5. Install clang-format-24 first, then install your custom meta-package
	#apt-get install -y clang-format-24
	#sudo dpkg -i clang-format-fix.deb
	sudo apt-get install --yes ./clang-format-fix.deb

else

	echo "Commands: download, unpack, fix, pack, install"

fi
