#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status. (is the same as '-o errexit')
set -e
# Make sure the 'tee pipes' fail correctly. Don't hide errors within pipes.
set -o pipefail

# Get the scripts run directory weather it is a symlink or not.
script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_dir="$(realpath "${run_dir}")"

# Include WriteLog function.
source "${script_dir}/inc/Miscellaneous.sh"

# Move to it.
cd "${run_dir}"

# Determine the OS name.
os_name="$(uname -o)"
# Qt repository URL.
qt_repo="https://code.qt.io/qt/qt5.git"
# Ignored submodules which are huge and not used.
mods_ignore=(qtwebchannel qtwebengine qtwebglplugin qtwebview)

# Install base directory for this machine.
dir_file="${run_dir}/.install-dir-$(uname -n)"
# Check if the directory file exists.
if [[ -f "${dir_file}" ]]; then
	# Read the first line of the file and strip the newline.
	lib_base_dir="$(head -n 1 "${dir_file}" | tr -d '\n' | tr -d '\n' | tr -d '\r')"
	WriteLog "- Library install base directory set to: ${lib_base_dir}"
else
	lib_base_dir="$(realpath "${run_dir}/..")"
fi

# Initial Qt version to compile.
qt_ver="0.0.0"

# Default compiler when running Cygwin.
if [[ "${os_name}" == "Cygwin" ]]; then
	compiler="mingw"
else
	compiler=""
fi

# Initialize the cross-compile flag.
flag_cross=false
# Initialize the ignore flag on not being in Docker container.
flag_ignore=false

function show_help {
	echo "Used to build the Qt framework libraries from source."
	echo "Available options:
  -w, --windows   : Crosscompile for Windows flag (all commands)
  --qt-ver        : Qt version to build.
  -c, --compiler  : Compiler (mingw, msvc) for Windows to load the correct load toolchain file (default: ${compiler}).
                    File is named like: '.toolchain-<compiler>-<hostname>
"
	echo "Available commands:
  help      : Shows this help.
  tags      : Show the tags of the remote repository.
  run       : Run the Docker container for this script to execute.
  env       : Prints environment variables.
  start     : Start the Docker container for this script to execute in the background.
  stop      : Stop the Docker container for this script to execute in the background.
  attach    : Attach to the Docker container for this script to execute in the background.
  doc       : Open documentation web-pages.
  deps      : Install dependencies needed to build.
  local     : Creates a symlink to local tmp directory to clone the source into for faster compiling.
  clone     : Clone the Qt repository from '${qt_repo}' at branch 'v${qt_ver}'.
  update    : Update the existing repository.
  init      : Initialize the Git repositories without the large qtwebengine-chromium repository.
  init-norm : Initialize the Git repositories with the default set of modules.
  conf-help : Show configure help.
  feat-help : Show all possible features.
  conf-help : Show available configuration options.
  conf      : Configure cmake.
  summary   : Show the summary of enabled features.
  check     : Check if the features are set (e.g. 'system_xcb_xinput') and if 'fix' command is to be called.
  fix       : Sets the feature(s) by modifying 'CMakeCache.txt' still not being set using the -feature-???? option.
  check     : Shows the required features from CMakeCache.txt and allows checking for 'ON' to build 'libqxcb.so'.
  redo      : Calls the configuration with the '-redo' option where previous are used.
  ccmake    : Run 'ccmake' command in the build directory.
  build     : Calls the cmake build to compile the libraries/framework
  install   : Install the build in the reported library directory.
  zip       : Creates a zip-file from the library directory for upload to Nexus for download in Docker images.
  clean     : Removes the build directory.

Steps to build Qt v${qt_ver} in order are:
  deps, local, clone, init, conf, fix, build, install, zip
"
}

# Parse options.
temp=$(getopt -o 'hc:w' --long 'help,qt-ver:,compiler:,windows:,ignore' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi

eval set -- "${temp}"
unset temp
while true; do
	case "$1" in

		-h | --help)
			show_help
			exit 0
			;;

		-w | --windows)
			shift
			flag_cross=true
			;;

		--ignore)
			shift
			flag_ignore=true
			;;

		--qt-ver)
			qt_ver="${2}"
			shift 2
			continue
			;;

		-c | --compiler)
			compiler="${2}"
			shift 2
			continue
			;;

		'--')
			shift
			break
			;;

		*)
			WriteLog "Internal error on argument (${1}) !" >&2
			exit 1
			;;
	esac
done

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
lnx_pkgs+=(libxcb-xkb-dev)
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
# Added for aarch64 since aarch64 Ubuntu does not have this apparently.
lnx_pkgs+=(libpulse-dev)
lnx_pkgs+=(pipewire)
lnx_pkgs+=(ffmpeg)


# Set some defaults depending on the current OS.
if [[ "${os_name}" == "Cygwin" ]]; then
	os_code="w64"
	repo_dir="qt-win"
	git_cmd='/cygdrive/c/Program Files/Git/cmd/git.exe'
else
	if ${flag_cross}; then
		os_code="win"
	else
		os_code="lnx"
	fi
	repo_dir="qt-lnx"
	git_cmd='git'
fi

# Directory to eventually ZIP.
lib_dir="${lib_base_dir}/${os_code}-$(uname -m)"
# Build directory.
build_dir="${run_dir}/build-${os_code}-$(uname -m)"
# Install directory for cmake.
if [[ "${os_name}" == "Cygwin" ]]; then
	install_dir="${lib_dir}/${qt_ver}/${compiler}_64"
	build_dir="/cygdrive/p/tmp/build-${compiler}-${os_code}-$(uname -m)"
	if [[ -n "${TEMP}" ]]; then
		repo_dir="${TEMP}/${repo_dir}"
	else
		WriteLog "Cygwin is missing 'TEMP' environment variable!"
	fi
else
	if ${flag_cross}; then
		install_dir="${lib_dir}/${qt_ver}/mingw_64"
	else
		install_dir="${lib_dir}/${qt_ver}/gcc_64"
	fi
fi
# Form the zip-filepath using the found or set Qt version.
zip_file_base="${run_dir}/qt-${os_code}-$(uname -m)-${qt_ver}"
zip_file="${zip_file_base}.zip"

# Detect windows using the cygwin 'uname' command.
if [[ "${os_name}" == "Cygwin" ]]; then
	# Tools directory for this machine using the specified compiler.
	GetEnvironmentFromFile "${run_dir}/.toolchain-${compiler}-$(uname -n)"
elif [[ "${os_name}" == "GNU/Linux" ]]; then
	WriteLog "# Linux $(uname -m) detected"
else
	WriteLog "Targeted OS '${os_name}' not supported!"
fi

function report {
	WriteLog "
# Operating System  : ${os_name} (${os_code})
# Qt Repository     : ${qt_repo} (v${qt_ver})
# Compiler          : ${compiler} (Windows only)
# Repo directory    : ${repo_dir}
# Run directory     : ${run_dir}
# Build Directory   : ${build_dir}
# Library Directory : ${lib_dir}
# Install Directory : ${install_dir}
# Zip file          : ${zip_file}
# Git Command       : ${git_cmd}"

	if [[ "${os_name}" == "Cygwin" ]]; then
		WriteLog "# Windows Tools File: ${dir_file}"
		if command -v gcc >/dev/null;then 
			WriteLog "# GCC Version       : $("gcc" --version | head -n 1 | tr -d '\n' | tr -d '\r')"
		fi
		if command -v cl1 >/dev/null; then 
			WriteLog  "# MSVC Version      : $("cl" 2>&1 | head -n 1 | tr -d '\n' | tr -d '\r')"
		fi
	fi
}

# Command available from outside Docker.
case $1 in

	cmd)
		cmd.exe
		;;

	run | start | stop | attach)
		# Run Docker C++ builder image without a Qt version configured.
		"${run_dir}/cpp-builder.sh" --qt-ver '' --project "${run_dir}/../../../applications/library/qt" "$@"
		exit 0
		;;

	tags)
		git ls-remote --tags "${qt_repo}" | grep --invert-match '\^{}$' | pcregrep -o1 '^[^ ]+\s+refs/tags/([^\s]+)$' | sort --version-sort
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
	[[ ! $flag_ignore ]] && exit 1
fi

# Command available from within Docker.
case $1 in

	env)
		report
		printenv
		;;

	deps)
		report
		WriteLog "- Install dependent packages..."
		if [[ "${os_name}" == "Cygwin" ]]; then
			# Iterate through the associative array of subdirectories (key) and remotes (value).
			for name in "${!wg_pkgs[@]}"; do
				if winget list --disable-interactivity --accept-source-agreements --exact --id "${wg_pkgs["${name}"]}" >/dev/null; then
					WriteLog "- WinGet Package '${name}' already installed."
				else
					WriteLog "Installing WinGet package'${name}' ..."
					winget install --disable-interactivity --accept-source-agreements --exact --id "${wg_pkgs["${name}"]}"
				fi
			done
		else
			sudo apt-get update && sudo apt-get --yes install "${lnx_pkgs[@]}"
		fi
		;;

	local)
		if [[ "${os_name}" == "Cygwin" ]]; then
			WriteLog "- Ignored in Cygwin on Windows."
		else
			WriteLog "- Creating symlink to tmp directory for repository directory for speed."
			# Create a symlink for the repository in the temp directory to speed up
			mkdir -p "/tmp/${repo_dir}"
			# Only create the symlink when it does not exist.
			if [[ ! -L "${repo_dir}" ]]; then
				ln -s "/tmp/${repo_dir}/" "${repo_dir}"
			else
				WriteLog "- Symlink '${repo_dir}' exists."
			fi
		fi
		;;

	vers)
		git -C "${repo_dir}" ls-remote --tags 
		;;
		
	clone)
		report
		WriteLog "- Cloning repository from tag 'v${qt_ver}' in '${repo_dir}'".
		# Check if the directory is empty by checking the existence of the README.md file.
		if [[ -f "${repo_dir}/README.md" ]]; then
			WriteLog "Already cloned: v${qt_ver} ${qt_repo} ${repo_dir}"
		else
			if [[ "${os_name}" == "Cygwin" ]]; then
				"${git_cmd}" clone --depth 1 --single-branch --branch "v${qt_ver}" --recurse-submodules --shallow-submodules "${qt_repo}" "$(cygpath -w "${repo_dir}")/"
				#"${git_cmd}" clone --branch "v${qt_ver}" "${qt_repo}" "$(cygpath -w "${repo_dir}/")"
			else
				"${git_cmd}" clone --depth 1 --branch "v${qt_ver}" "${qt_repo}" "${repo_dir}/"
			fi
		fi
		;;
		
	clone2)
		WriteLog "For each submodule..."
		pushd "${repo_dir}" >/dev/null
		# Set the shallow flag (not sure this does anything).
		"${git_cmd}" config --file .gitmodules --name-only --get-regexp path$ |
			sed 's/\.path//' |
			while read -r name; do
				git config -f .gitmodules "$name.shallow" true
			done
#		# Check out all submodules except the ones ignored.
#		"${git_cmd}" config --file .gitmodules --get-regexp path$ | sed -r 's/.* //' | while read -r name; do
#			if InArray "${name}" "${mods_ignore[@]}"; then
#				WriteLog "# Ignoring submodule: ${name}"
#			else
#				WriteLog "~ Initializing submodule (shallow): ${name}"
#				"${git_cmd}" submodule update --init --depth 1 "${name}"
#			fi
#		done
		popd
		;;

	update)
		report
		WriteLog "- Update repository and submodules..."
		# Update recursively.
		if [[ "${os_name}" == "Cygwin" ]]; then
			"${git_cmd}" -C "$(cygpath -w "${repo_dir}")" submodule update --init --recursive
		else
			"${git_cmd}" -C "${repo_dir}" submodule update --init --recursive
		fi
		;;

	init | init-norm)
		report
		WriteLog "- Initialize submodules..."
		# Assemble the options array.
		options=("--module-subset=default" "${mods_ignore[@]}")
		pushd "${repo_dir}" >/dev/null
		if [[ "${os_name}" == "Cygwin" ]]; then
			WriteLog "Initializing repository sub modules..."
			if [[ "${1}" == "init" ]]; then
				WriteLog "# Options: $(JoinBy ",-" "${options[@]}")"
				cmd /c "$(cygpath -w "${PWD}/init-repository.bat")" --force "$(JoinBy "," "${options[@]}")"
			else
				cmd /c "$(cygpath -w "${PWD}/init-repository.bat")" --force --branch --module-subset=default
			fi
			# When in Windows the access control list needs to be fixed so batch files can be
			# called from cmake.exe when cloned using Cygwin git.
			[[ "${os_name}" == "Cygwin" ]] && read -rp "Granting 'Users' group full-access to cloned repository [y/N]?" &&
				if [[ $REPLY = [yY] ]]; then
					WriteLog "Granting 'Users' group full-access to '${repo_dir}'."
					# Reset the access control list changes made while cloning by Git form cygwin.
					icacls . /reset /T /C
				fi
		else
			if [[ "${1}" == "init" ]]; then
				# Omit module qtwebengine when 'https://code.qt.io/qt/qtwebengine-chromium.git' since giving a 503 error.
				# Some additional modules need to be omitted due to failing configuration and this seems to fix that.
				./init-repository --force --branch "$(JoinBy ",-" "${options[@]}")"
			else
				./init-repository --force --branch --module-subset=default
			fi
		fi
		popd >/dev/null
		;;

	clean)
		report
		WriteLog "- Cleaning build and/or repo directory..."
		if [[ -d "${build_dir}" ]]; then
			WriteLog "Removing build directory '${build_dir}'."
			if AskConfirmation "Start removing?"; then
				rm --recursive --preserve-root "${build_dir}"
			fi
		fi
		WriteLog "Removing sources from directory '${repo_dir}'."
		if AskConfirmation "Start removing?"; then
			# shellcheck disable=SC2115
			rm --recursive --preserve-root --force "${repo_dir}/"
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
		"${conf_cmd[@]}" | less
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
		"${conf_cmd[@]}" 2>&1 | less
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
		# Create the toolchain file only when cross compiling.
		if ${flag_cross}; then
			cat <<'EOD' >"${build_dir}/toolchain.cmake"
# File: mingw-toolchain-x86_64.cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Adjust the to match your distro (e.g. x86_64-w64-mingw32)
set(MINGW_PREFIX "/usr/bin/x86_64-w64-mingw32-")
set(MINGW_SUFFIX "-posix")

# Compilers
set(CMAKE_C_COMPILER   ${MINGW_PREFIX}gcc${MINGW_SUFFIX})
set(CMAKE_CXX_COMPILER ${MINGW_PREFIX}g++${MINGW_SUFFIX})
set(CMAKE_RC_COMPILER  ${MINGW_PREFIX}windres)
set(CMAKE_AR           ${MINGW_PREFIX}ar)
set(CMAKE_RANLIB       ${MINGW_PREFIX}ranlib)
set(CMAKE_STRIP        ${MINGW_PREFIX}strip)

# Avoid mixing host paths when searching for libraries/headers
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)   # find host programs on host
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)    # find target libs in target root
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)    # find target headers in target root
EOD
		fi

		if [[ "${os_name}" == "Cygwin" ]]; then
			conf_cmd=(cmd /c "$(cygpath -w "${repo_dir}/configure.bat")")
			#conf_cmd=("../${repo_dir}/configure.bat")
			conf_cmd+=(-prefix "$(cygpath -w "${install_dir}")")
		else
			conf_cmd=("${run_dir}/${repo_dir}/configure")
			conf_cmd+=(-ccache)
			conf_cmd+=(-feature-ccache)
			conf_cmd+=(-prefix "${install_dir}")
			if ! ${flag_cross}; then
				conf_cmd+=(-qpa xcb)
				conf_cmd+=(-platform linux-g++)
				conf_cmd+=(-no-feature-wayland-compositor-quick)
				# Next option need some additional packages installed.
				#conf_cmd+=(-qpa wayland)
			fi
		fi

		# This should change cache variable 'FEATURE_system_xcb_xinput` to be ON.
		conf_cmd+=(-system-xcb -bundled-xcb-xinput no)
		#
		conf_cmd+=(-release)
		#conf_cmd+=(-force-debug-info)
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
		#conf_cmd+=(-skip qtmultimedia)
		conf_cmd+=(-skip qtquick)
		conf_cmd+=(-skip qtquick3d)
		conf_cmd+=(-skip qtquick3dphysics)
		conf_cmd+=(-skip qtquickcontrols)
		conf_cmd+=(-skip qtquickcontrols2)
		conf_cmd+=(-skip qtquickeffectmaker)
		conf_cmd+=(-skip qtquicktimeline)
		#conf_cmd+=(-skip qtshadertools)
		conf_cmd+=(-skip qttranslations)
		conf_cmd+=(-skip qtwebchannel)
		conf_cmd+=(-skip qtwebengine)
		conf_cmd+=(-skip qtwebview)
		conf_cmd+=(-skip qtdeclarative)
		#conf_cmd+=(-skip qtspeech)
		conf_cmd+=(-skip qtlocation)
		conf_cmd+=(-skip qtlottie)
		conf_cmd+=(-skip qtmqtt)
		conf_cmd+=(-skip qtopcua)
		conf_cmd+=(-skip qtvirtualkeyboard)
		if ${flag_cross}; then
			conf_cmd+=(-skip qtactiveqt)
		fi
		conf_cmd+=(-no-feature-spatialaudio_quick3d)
		conf_cmd+=(-no-feature-qdoc)
		conf_cmd+=(-no-feature-clang)
		#conf_cmd+=(-qt3d-assimp)
		# Execute the configuration command.
		if ${flag_cross}; then
			conf_cmd+=("--")
			conf_cmd+=(-DCMAKE_TOOLCHAIN_FILE="${build_dir}/toolchain.cmake")
			conf_cmd+=(-DQT_HOST_PATH="/mnt/project/lnx-x86_64/${qt_ver}/gcc_64")
		fi
		# Execute the configuration command.
		"${conf_cmd[@]}"
		popd >/dev/null
		;;

	summary)
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
		cmake --build . --target help | less
		popd >/dev/null
		;;

	build)
		report
		pushd "${build_dir}" >/dev/null
		cmake --build . --parallel
		popd >/dev/null
		;;

	install)
		if [[ -d "${install_dir}" ]]; then
			WriteLog "- Renaming compiler directory '${install_dir}' first."
			timestamp="$(date +'%FT%T')"
			# Removing ':'  for Windows.
			timestamp="${timestamp//:/_}"
			mv "${install_dir}" "${install_dir}_${timestamp}"
		fi
		pushd "${build_dir}" >/dev/null
		cmake --install .
		popd >/dev/null
		;;

	check)
		grep --perl-regexp "^(QT_|)FEATURE_(system_xcb_xinput|ccache):" "${build_dir}/CMakeCache.txt"
		;;

	zip)
		report
		# Check if the Qt version library directory exists.
		if [[ ! -d "${install_dir}" ]]; then
			WriteLog "- Qt version directory '${install_dir}' does not exist!"
			exit 1
		fi
		# Rename the existing zip file using a time stamp.
		if [[ -f "${zip_file}" ]]; then
			WriteLog "Renaming existing zip-file '${zip_file}' first."
			mv "${zip_file}" "${zip_file_base}_$(date +'%FT%T').zip"
		fi
		# Remove the current zip file.
		[[ -f "${zip_file}" ]] && rm "${zip_file}"
		# Change directory in order for zip to store the correct path.
		pushd "${lib_dir}" >/dev/null
		# Zip only the the compiled version directory.
		zip --display-bytes --recurse-paths --symlinks "${zip_file}" "${qt_ver}/gcc_64/"{bin,lib,include,libexec,mkspecs,plugins} "${qt_ver}"
		ls -lah "${zip_file}"
		popd >/dev/null
		;;

	help)
		show_help
		exit 0
		;;

	*)
		if [[ -n "$1" ]]; then
			WriteLog "Invalid command '$1' !"
		else
			show_help
			exit 1
		fi
		;;
esac
