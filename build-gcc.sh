#!/bin/bash

# Exit immediately if a command exits with a non-zero status. (is the same as '-o errexit')
set -e
# Make sure the 'tee pipes' fail correctly. Don't hide errors within pipes.
set -o pipefail

#set -x

gcc_version="gcc-13.2.0"
src_dir="${HOME}/src"
zip_file="/tmp/${gcc_version}.tar.gz"

case "${1}" in
	
	required)
		sudo apt install wget build-essential gcc g++
		;;
		
	download)
		wget "http://ftp.gnu.org/gnu/gcc/${gcc_version}/${gcc_version}.tar.gz" -O "${zip_file}"
		;;

	unzip)
		mkdir -p "${src_dir}"
		tar -C "${src_dir}" -xzf "${zip_file}"
		;;

	config)
		pushd "${src_dir}/${gcc_version}"
		./contrib/download_prerequisites
		pushd "${src_dir}/${gcc_version}/build"
		../configure --prefix=/opt/gcc-13 --disable-multilib --enable-languages=c,c++
		popd
		popd
		;;

	build)
		pushd "${src_dir}/${gcc_version}/build"
		make -j"$(nproc)"
		popd
		;;

	install)
		pushd "${src_dir}/${gcc_version}/build"
		sudo make install
		popd
		;;
		
	*)
		echo "Invalid command '$1'."
		echo "Use: required, download, unzip, config, build, install"
		;;
		
esac

