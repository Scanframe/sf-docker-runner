#!/bin/bash

# Exit immediately if a command exits with a non-zero status. (is the same as '-o errexit')
set -e
# Make sure the 'tee pipes' fail correctly. Don't hide errors within pipes.
set -o pipefail

# Get the scripts run directory weather it is a symlink or not.
run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Base zip-file name containing the Linux Qt library.
qt_lnx_filename="qt-lnx"
# Qt version to compile.
qt_ver="6.7.2"
# Qt repository URL.
qt_repo=https://code.qt.io/qt/qt5.git
# Directory to eventually ZIP.
lib_dir="${run_dir}/lib-$(uname -m)"
# Install directory for cmake.
install_dir="${lib_dir}/${qt_ver}/gcc_64"
# Build directory.
build_dir="${run_dir}/build-$(uname -m)"
# Form the zip-filepath using the found or set Qt version.
zip_file_base="${run_dir}/${qt_lnx_filename}-$(uname -m)-${qt_ver}"
zip_file="${zip_file_base}.zip"

function report {
	echo "
Qt Repository     : v${qt_repo}
Qt Version Branch : v${qt_ver}
Library Directory : ${lib_dir}
Build Directory   : ${build_dir}
Install Directory : ${install_dir}
Zip file          : ${zip_file}
"
}

function show_help {
	echo "Used to build the Qt framework libraries from source."
	report
	echo "Available commands:
  help         : Shows this help.
  doc          : Open documentation web-pages.
  deps-aarch64 : Install needed packages for cross-compiling 'aarch64' on 'x86_64'.
  deps         : Install dependencies needed to build.
  clone        : Clone the Qt repository from '${qt_repo}' at branch 'v${qt_ver}'.
  init         : Initialize the Git repositories.
  conf-help    : Show configure help.
  feat-help    : Show all possible features.
  conf         : Configure cmake.
  sum          : Show the summary of enabled features.
  check        : Check if the features are set (e.g. 'system_xcb_xinput') and if 'fix' command is to be called.
  fix          : Sets the feature(s) by modifying 'CMakeCache.txt' still not being set using the -feature-???? option.
  check        : Shows the required features from CMakeCache.txt and allows checking for 'ON'.
                 Also displays the '${install_dir}/plugins/platforms/' to see if 'libqxcb.so' is build.
  redo         : Calls the configuration with the '-redo' option where previous are used.
  ccmake       : Run 'ccmake' command in the build directory.
  build        : Calls the cmake build to compile the libraries/framework
  install      : Install the build in the reported library directory.
  zip          : Creates a zip-file from the library directory for upload to Nexus for download in Docker images.
"
}

case $1 in

	doc)
		report
		xdg-open "https://wiki.qt.io/Cross-Compile_Qt_6_for_Raspberry_Pi"
		;;

	deps-aarch64)
		if [[ "$(uname -m)" != 'aarch64' ]]; then
			sudo apt update && sudo apt install g++-aarch64-linux-gnu
		else
			echo "Not possible since this already an 'aarch64' platform."
		fi
		;;

	clone)
		report
		git clone --branch v${qt_ver} "${qt_repo}" qt
		;;

	deps)
		report
		sudo apt-get update && sudo apt-get --yes install \
			build-essential \
			git \
			cmake \
			ninja-build \
			perl \
			python3 \
			clang \
			cmake \
			cmake-curses-gui \
			libasound2-dev \
			libatspi2.0-dev \
			libavcodec-dev \
			libavformat-dev \
			libavutil-dev \
			libclang-dev \
			libcups2-dev \
			libcurl4-openssl-dev \
			libfontconfig1-dev \
			libfreetype-dev \
			libgl-dev \
			libglib2.0-dev \
			libglu1-mesa-dev \
			libgstreamer-plugins-base1.0-dev \
			libgstreamer1.0-dev \
			libgtest-dev \
			libicu-dev \
			libmtdev-dev \
			libpulse-dev \
			libsqlite3-dev \
			libssl-dev \
			libswscale-dev \
			libudev-dev \
			libvulkan-dev \
			libwayland-dev \
			libx11-dev \
			libx11-xcb-dev \
			libx11-xcb1 \
			libxcb-xinput-dev \
			libxcb-cursor-dev \
			libxcb-glx0-dev \
			libxcb-icccm4-dev \
			libxcb-image0-dev \
			libxcb-keysyms1-dev \
			libxcb-randr0-dev \
			libxcb-render-util0-dev \
			libxcb-shape0-dev \
			libxcb-shm0-dev \
			libxcb-sync-dev \
			libxcb-util-dev \
			libxcb-xfixes0-dev \
			libxcb-xinerama0 \
			libxcb-xinerama0-dev \
			libxcb1 \
			libxcb1-dev \
			libxext-dev \
			libxi-dev \
			libxkbcommon-dev \
			libxkbcommon-x11-0 \
			libxkbcommon-x11-dev \
			libxrandr-dev \
			libxrender-dev \
			mesa-common-dev \
			ninja-build \
			perl \
			python3 wayland-protocols \
			zlib1g-dev \
			libsm-dev
		;;

	init)
		report
		pushd qt
		#./init-repository --force --branch --module-subset=essential
		#./init-repository --force --branch --module-subset=default
		./init-repository --force --branch
		popd
		;;

	clean)
		report
		if [[ -d "${build_dir}" ]]; then
			echo "Removing build directory '${build_dir}'."
			rm -r "${lib_dir}"
		fi
		;;

	conf-help)
		mkdir -p "${build_dir}"
		pushd "${build_dir}"
		qt/configure -help 2>&1
		popd
		;;

	feat-help)
		mkdir -p "${build_dir}"
		pushd "${build_dir}"
		qt/configure -list-features 2>&1
		echo "
Enable/Disable feature using options:
  -feature-<feature>
  -no-feature-<feature>
"
		popd
		;;

	redo)
		report
		mkdir -p "${build_dir}"
		pushd "${build_dir}"
		../qt/configure -redo
		;;

	conf)
		report
		mkdir -p "${build_dir}"
		pushd "${build_dir}"
		../qt/configure \
			-prefix "${install_dir}" \
			-platform linux-g++ \
			-release \
			-opensource \
			-confirm-license \
			-ccache \
			-nomake examples \
			-nomake tests \
			-skip qtwebengine \
			-skip qtcharts \
			-skip qttools \
			-skip qtdoc \
			-skip qttranslations \
			-skip qtquick \
			-skip qtquick3d \
			-skip qtgraphs \
			-skip qtquickcontrols \
			-skip qtquick3dphysics \
			-skip qtquickeffectmaker \
			-skip qtquicktimeline \
			-skip qtwebview \
			-skip qtwebchannel \
			-feature-ccache \
			-no-feature-spatialaudio_quick3d
		# Next feature needs to be set in the CMakeCache.txt file.
		#	-feature-system_xcb_xinput
		popd
		;;

	sum)
		less "${build_dir}/config.summary"
		;;

	ccmake)
		ccmake "${build_dir}"
		;;

	fix)
		sed --in-place=-orginal \
			-e "s/^FEATURE_system_xcb_xinput:BOOL=OFF$/FEATURE_system_xcb_xinput:BOOL=ON/g" \
			-e "s/^FEATURE_ccache:BOOL=OFF$/FEATURE_ccache:BOOL=ON/g" \
			"${build_dir}/CMakeCache.txt"
		;;

	build)
		report
		pushd "${build_dir}"
		cmake --build . --parallel
		popd
		;;

	install)
		if [[ -d "${lib_dir}" ]]; then
			echo "Renaming library directory '${lib_dir}' first."
			echo mv "${lib_dir}" "${lib_dir}_$(date +'%FT%T')"
		fi
		pushd "${build_dir}"
		cmake --install .
		popd
		;;

	check)
		grep --perl-regexp "^(QT_|)FEATURE_(system_xcb_xinput|ccache):" "${build_dir}/CMakeCache.txt"
		if [[ -d "${install_dir}/plugins/platforms/" ]]; then
			ls -la "${install_dir}/plugins/platforms/"
		fi
		;;

	zip)
		report
		# Check if the Qt version library directory exists.
		if [[ ! -d "${install_dir}" ]]; then
			echo "Qt version directory '${install_dir}' does not exist!"
			exit 1
		fi
		# Rename the existing zip file using a time stamp.
		if [[ -f "${zip_file}" ]]; then
			echo "Renaming existing zip-file '${zip_file}' first."
			mv "${zip_file}" "${zip_file_base}_$(date +'%FT%T').zip"
		fi
		pushd "${lib_dir}"
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}"
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins}
		popd
		ls -lah "${zip_file}"
		popd
		;;

	help)
		show_help
		exit 0
		;;

	*)
		if [[ -n "$1" ]]; then
			echo "Invalid command '$1'."
		else
			show_help
			exit 1
		fi
		;;
esac
