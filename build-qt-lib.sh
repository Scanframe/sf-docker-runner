#!/bin/bash

# Exit immediately if a command exits with a non-zero status. (is the same as '-o errexit')
set -e
# Make sure the 'tee pipes' fail correctly. Don't hide errors within pipes.
set -o pipefail

# Get the scripts run directory weather it is a symlink or not.
run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_dir="$(realpath "${run_dir}")"
# Move to it.
cd "${run_dir}"

# Determine the OS name.
os_name="$(uname -o)"

if [[ "${os_name}" == "Cygwin" ]]; then
	os_code="w64"
	repo_dir="qt-win"
	# Qt version to compile.
	qt_ver="6.8.1"
	git_cmd='/cygdrive/c/Program Files/Git/cmd/git.exe'
else
	os_code="lnx"
	repo_dir="qt-lnx"
	qt_ver="6.8.1"
	#qt_ver="6.7.2"
	git_cmd='git'
fi

# Qt repository URL.
qt_repo=https://code.qt.io/qt/qt5.git
# Directory to eventually ZIP.
lib_dir="$(realpath "${run_dir}/../${os_code}-$(uname -m)")"
# Install directory for cmake.
if [[ "${os_name}" == "Cygwin" ]]; then
	install_dir="${lib_dir}/${qt_ver}/mingw_64"
else
	install_dir="${lib_dir}/${qt_ver}/gcc_64"
fi
# Build directory.
build_dir="${run_dir}/build-${os_code}-$(uname -m)"
# Form the zip-filepath using the found or set Qt version.
zip_file_base="${run_dir}/qt-${os_code}-$(uname -m)-${qt_ver}"
zip_file="${zip_file_base}.zip"

function WriteLog {
	echo "$@" 1>&2
}

function report {
	echo "
Operating System  : ${os_name}
Qt Repository     : ${qt_repo}
Qt Version Branch : v${qt_ver}
Run directory     : ${run_dir}
Build Directory   : ${build_dir}
Library Directory : ${lib_dir}
Install Directory : ${install_dir}
Zip file          : ${zip_file}
Git:              : ${git_cmd}
"
}

function show_help {
	echo "Used to build the Qt framework libraries from source."
	report
	echo "Available commands:
  help         : Shows this help.
  run          : Run the Docker container for this script to execute.
  start        : Start the Docker container for this script to execute in the background.
  stop         : Stop the Docker container for this script to execute in the background.
  attach       : Attach to the Docker container for this script to execute in the background.
  doc          : Open documentation web-pages.
  deps         : Install dependencies needed to build.
  clone        : Clone the Qt repository from '${qt_repo}' at branch 'v${qt_ver}'.
  update       : Update the existing repository.
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

Steps to build Qt v${qt_ver} in order are:
  deps, clone, init, conf, build, install ,zip
"
}

# List of WinGet packages to install.
declare -A wg_pkgs
wg_pkgs["CMake C++ build tool"]="Kitware.CMake"
wg_pkgs["Ninja build system"]="Ninja-build.Ninja"
wg_pkgs["Git"]="Git.Git"

# List of Apt packages to install.
lnx_pkgs=(build-essential)
lnx_pkgs+=(git)
lnx_pkgs+=(cmake)
lnx_pkgs+=(ninja-build)
lnx_pkgs+=(perl)
lnx_pkgs+=(python3)
lnx_pkgs+=(clang)
lnx_pkgs+=(cmake)
lnx_pkgs+=(cmake-curses-gui)
lnx_pkgs+=(libasound2-dev)
lnx_pkgs+=(libatspi2.0-dev)
lnx_pkgs+=(libavcodec-dev)
lnx_pkgs+=(libavformat-dev)
lnx_pkgs+=(libavutil-dev)
lnx_pkgs+=(libclang-dev)
lnx_pkgs+=(libcups2-dev)
lnx_pkgs+=(libcurl4-openssl-dev)
lnx_pkgs+=(libfontconfig1-dev)
lnx_pkgs+=(libassimp-dev)
lnx_pkgs+=(libfreetype-dev)
lnx_pkgs+=(libgl-dev)
lnx_pkgs+=(libglib2.0-dev)
lnx_pkgs+=(libglu1-mesa-dev)
lnx_pkgs+=(libgstreamer-plugins-base1.0-dev)
lnx_pkgs+=(libgstreamer1.0-dev)
lnx_pkgs+=(libgtest-dev)
lnx_pkgs+=(libicu-dev)
lnx_pkgs+=(libmtdev-dev)
lnx_pkgs+=(libpulse-dev)
lnx_pkgs+=(libsqlite3-dev)
lnx_pkgs+=(libssl-dev)
lnx_pkgs+=(libswscale-dev)
lnx_pkgs+=(libudev-dev)
lnx_pkgs+=(libvulkan-dev)
lnx_pkgs+=(libwayland-dev)
lnx_pkgs+=(libx11-dev)
lnx_pkgs+=(libx11-xcb-dev)
lnx_pkgs+=(libx11-xcb1)
lnx_pkgs+=(x11-apps)
lnx_pkgs+=(xcb)
lnx_pkgs+=(libxkbcommon-x11-0)
lnx_pkgs+=(libxcb-xinput0)
lnx_pkgs+=(libxcb-cursor0)
lnx_pkgs+=(libxcb-shape0)
lnx_pkgs+=(libxcb-icccm4)
lnx_pkgs+=(libxcb-image0)
lnx_pkgs+=(libxcb-xinput-dev)
lnx_pkgs+=(libxcb-cursor-dev)
lnx_pkgs+=(libxcb-glx0-dev)
lnx_pkgs+=(libxcb-icccm4-dev)
lnx_pkgs+=(libxcb-image0-dev)
lnx_pkgs+=(libxcb-keysyms1-dev)
lnx_pkgs+=(libxcb-randr0-dev)
lnx_pkgs+=(libxcb-render-util0-dev)
lnx_pkgs+=(libxcb-shape0-dev)
lnx_pkgs+=(libxcb-shm0-dev)
lnx_pkgs+=(libxcb-sync-dev)
lnx_pkgs+=(libxcb-util-dev)
lnx_pkgs+=(libxcb-xfixes0-dev)
lnx_pkgs+=(libxcb-xinerama0)
lnx_pkgs+=(libxcb-xinerama0-dev)
lnx_pkgs+=(libxcb1)
lnx_pkgs+=(libxcb1-dev)
lnx_pkgs+=(libxext-dev)
lnx_pkgs+=(libxi-dev)
lnx_pkgs+=(libxkbcommon-dev)
lnx_pkgs+=(libxkbcommon-x11-0)
lnx_pkgs+=(libxkbcommon-x11-dev)
lnx_pkgs+=(libxrandr-dev)
lnx_pkgs+=(libxrender-dev)
lnx_pkgs+=(mesa-common-dev)
lnx_pkgs+=(ninja-build)
lnx_pkgs+=(perl)
lnx_pkgs+=(python3)
lnx_pkgs+=(wayland-protocols)
lnx_pkgs+=(zlib1g-dev)
lnx_pkgs+=(libsm-dev)

# Detect windows using the cygwin 'uname' command.
if [[ "${os_name}" == "Cygwin" ]]; then
	tools_dir_file="${run_dir}/.tools-dir-$(uname -n)"
	WriteLog "# Cygwin tools location file: $(basename "${tools_dir_file}")"
	# Check if the tools directory file exists.
	if [[ -f "${tools_dir_file}" ]]; then
		# Read the first line of the file and strip the newline.
		tools_dir="$(head -n 1 "${tools_dir_file}" | tr -d '\n' | tr -d '\n' | tr -d '\r')"
		if [[ -d "${tools_dir}" ]]; then
			export PATH="${tools_dir}:${PATH}"
			WriteLog "# Tools directory added to PATH: ${tools_dir}"
		else
			WriteLog "# Non-existing tools directory: ${tools_dir}"
		fi
	fi
elif [[ "${os_name}" == "GNU/Linux" ]]; then
	WriteLog "# Linux $(uname -m) detected"
else
	WriteLog "Targeted OS '${os_name}' not supported!"
fi

if [[ "$#" -eq 0 ]]; then
	show_help
	exit 0
fi

# Command available from outside Docker.
case $1 in

	cmd)
		cmd.exe
		;;

	run | start | stop | attach)
		# Run Docker image without a Qt version configured.
		"${run_dir}/cpp-builder.sh" --qt-ver '' --project "${run_dir}/../../../applications/library/qt" "$@"
		exit 0
		;;

	doc)
		report
		# xdg-open "https://wiki.qt.io/Cross-Compile_Qt_6_for_Raspberry_Pi"
		xdg-open "https://doc.qt.io/qt-6/build-sources.html"
		xdg-open "https://download.qt.io/development_releases/prebuilt/mingw_64/"
		xdg-open "https://stackoverflow.com/questions/42480831/configure-error-with-qt-5-8-and-sql-libraries"
		exit 0
		;;

esac

# When not in docker bailout here.
if [[ ! -f /.dockerenv && "${os_name}" == "GNU/Linux" ]]; then
	WriteLog "Command '$1' only available from within the docker container."
	exit 1
fi

# Command available from within Docker.
case $1 in

	deps)
		report
		if [[ "${os_name}" == "Cygwin" ]]; then
			# Iterate through the associative array of subdirectories (key) and remotes (value).
			for name in "${!wg_pkgs[@]}"; do
				if winget list --disable-interactivity --accept-source-agreements --exact --id "${wg_pkgs["${name}"]}" >/dev/null; then
					echo "WinGet Package '${name}' already installed."
				else
					echo "Installing WinGet package'${name}' ..."
					winget install --disable-interactivity --accept-source-agreements --exact --id "${wg_pkgs["${name}"]}"
				fi
			done
		else
			sudo apt-get update && sudo apt-get --yes install "${lnx_pkgs[@]}"
		fi
		;;

	local)
		WriteLog "Creating symlink to tmp directory for repository directory for speed."
		# Create a symlink for the repository in the temp directory to speed up
		mkdir -p "/tmp/${repo_dir}" && ln -s "/tmp/${repo_dir}" "${repo_dir}"
		;;

	clone)
		report
		# Check if the directory is empty by checking the existence of the README.md file.
		if [[ -f "${repo_dir}/README.md" ]]; then
			WriteLog "Already cloned: v${qt_ver} ${qt_repo} ${repo_dir}"
		else
			"${git_cmd}" clone --branch v${qt_ver} "${qt_repo}" "${repo_dir}/"
		fi
		;;

	update)
		report
		# Update recursively.
		"${git_cmd}" -C "${repo_dir}" submodule update --init --recursive
		;;

	init)
		report
		pushd "${repo_dir}" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			WriteLog "Initializing repository sub modules..."
			cmd /c "$(cygpath -w "${PWD}/init-repository.bat")" --force --branch # --module-subset=essential
			# When in Windows the access control list needs to be fixed so batch files can be
			# called from cmake.exe when cloned using Cygwin git.
			[[ "${os_name}" == "Cygwin" ]] && read -rp "Granting 'Users' group full-access to cloned repository [y/N]?" &&
			if [[ $REPLY = [yY] ]]; then
				WriteLog "Granting 'Users' group full-access to '${repo_dir}'."
				# Reset the access control list changes made while cloning by Git form cygwin.
				icacls . /reset /T /C
			fi
		else
			./init-repository --force --branch
		fi
		popd >/dev/null
		;;

	clean)
		report
		if [[ -d "${build_dir}" ]]; then
			WriteLog "Removing build directory '${build_dir}'."
			rm --recursive --preserve-root "${build_dir}"
		fi
		;;

	conf-help)
		pushd "${repo_dir}" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			conf_cmd=(cmd /c "$(cygpath -w "${run_dir}/${repo_dir}/configure.bat")")
		else
			conf_cmd=("../${repo_dir}/configure")
		fi
		conf_cmd+=(-help)
		# Execute the configuration command.
		"${conf_cmd[@]}"
		popd >/dev/null
		;;

	feat-help)
		pushd "${run_dir}/${repo_dir}/" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			conf_cmd=(cmd /c "$(cygpath -w "${run_dir}/${repo_dir}/configure.bat")")
		else
			conf_cmd=("../${repo_dir}/configure")
		fi
		conf_cmd+=(-list-features)
		# Execute the configuration command.
		"${conf_cmd[@]}" 2>&1
		WriteLog "
Enable/Disable feature using options:
  -feature-<feature>
  -no-feature-<feature>
"
		popd >/dev/null
		;;

	redo)
		report
		mkdir -p "${build_dir}"
		pushd "${build_dir}" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			conf_cmd=(cmd /c "$(cygpath -w "${run_dir}/${repo_dir}/configure.bat")")
		else
			conf_cmd=("../${repo_dir}/configure")
		fi
		conf_cmd+=(-redo)
		# Execute the configuration command.
		"${conf_cmd[@]}"
		popd >/dev/null
		;;

	conf)
		report
		mkdir -p "${build_dir}"
		pushd "${build_dir}" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			conf_cmd=(cmd /c "$(cygpath -w "${run_dir}/${repo_dir}/configure.bat")")
			#conf_cmd=("../${repo_dir}/configure.bat")
			conf_cmd+=(-prefix "$(cygpath -w "${install_dir}")")
		else
			conf_cmd=("${run_dir}/${repo_dir}/configure")
			conf_cmd+=(-ccache)
			conf_cmd+=(-feature-ccache)
			conf_cmd+=(-qpa xcb)
			conf_cmd+=(-prefix "${install_dir}")
			conf_cmd+=(-platform linux-g++)
			conf_cmd+=(-no-feature-wayland-compositor-quick)
			# Next option need some additional packages installed.
			#conf_cmd+=(-qpa wayland)
		fi
		conf_cmd+=(-release)
		conf_cmd+=(-opensource)
		conf_cmd+=(-confirm-license)
		conf_cmd+=(-make libs)
		conf_cmd+=(-make tools)
		conf_cmd+=(-nomake examples)
		conf_cmd+=(-nomake tests)
		conf_cmd+=(-feature-designer)
		conf_cmd+=(-skip qtcharts)
		conf_cmd+=(-skip qtdoc)
		conf_cmd+=(-skip qtgraphs)
		conf_cmd+=(-skip qtmultimedia)
		conf_cmd+=(-skip qtquick)
		conf_cmd+=(-skip qtquick3d)
		conf_cmd+=(-skip qtquick3dphysics)
		conf_cmd+=(-skip qtquickcontrols)
		conf_cmd+=(-skip qtquickcontrols2)
		conf_cmd+=(-skip qtquickeffectmaker)
		conf_cmd+=(-skip qtquicktimeline)
		conf_cmd+=(-skip qtshadertools)
		conf_cmd+=(-skip qttranslations)
		conf_cmd+=(-skip qtwebchannel)
		conf_cmd+=(-skip qtwebengine)
		conf_cmd+=(-skip qtwebview)
		conf_cmd+=(-skip qtdeclarative)
		conf_cmd+=(-skip qtspeech)
		conf_cmd+=(-skip qtlocation)
		conf_cmd+=(-skip qtlottie)
		conf_cmd+=(-skip qtmqtt)
		conf_cmd+=(-skip qtopcua)
		conf_cmd+=(-skip qtvirtualkeyboard)
		conf_cmd+=(-no-feature-spatialaudio_quick3d)
		conf_cmd+=(-no-feature-qdoc)
		conf_cmd+=(-no-feature-clang)
		#conf_cmd+=(-qt3d-assimp)
		# Execute the configuration command.
		"${conf_cmd[@]}"
		popd >/dev/null
		;;

	sum)
		less "${build_dir}/config.summary"
		;;

	ccmake)
		if [[ "${os_name}" == "Cygwin" ]]; then
			WriteLog "There is no console version in Windows of application 'ccmake'."
		else
			ccmake "${build_dir}"
		fi
		;;

	fix)
		WriteLog "Fixing CMakeCache.txt for Linux only."
		sed --in-place=-orginal \
			-e "s/^FEATURE_system_xcb_xinput:BOOL=OFF$/FEATURE_system_xcb_xinput:BOOL=ON/g" \
			-e "s/^FEATURE_ccache:BOOL=OFF$/FEATURE_ccache:BOOL=ON/g" \
			"${build_dir}/CMakeCache.txt"
		;;

	targets)
		report
		pushd "${build_dir}" >/dev/null
		cmake --build . --target help
		popd >/dev/null
		;;

	build)
		report
		pushd "${build_dir}" >/dev/null
		cmake --build . --parallel
		popd >/dev/null
		;;

	tbuild)
		report
		pushd "${build_dir}" >/dev/null
		cmake --build . --parallel --target "libQt6Designer.so"
		popd >/dev/null
		;;

	install)
		if [[ -d "${lib_dir}/${qt_ver}" ]]; then
			echo "Renaming version directory '${lib_dir}/${qt_ver}' first."
			mv "${lib_dir}/${qt_ver}" "${lib_dir}/${qt_ver}_$(date +'%FT%T')"
		fi
		pushd "${build_dir}" >/dev/null
		cmake --install .
		popd >/dev/null
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
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}" >/dev/null
		# Zip only the the compiled version directory.
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins} ${qt_ver}
		ls -lah "${zip_file}"
		popd >/dev/null
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
