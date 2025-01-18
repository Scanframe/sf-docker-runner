#!/usr/bin/env bash

function WriteLog {
	if [[ -n "${DEBUG}" ]]; then
		echo "${@}" 1>&2
	fi
}

# Report the current command to stderr
WriteLog "Entrypoint($(id -u)):" "${@}"

# Fixing the warning message 'unable to resolve host ???'.
echo "127.0.1.1  $(cat /etc/hostname)" | sudo tee --append /etc/hosts >/dev/null

# Check if root is executing the entrypoint.
if [[ "$(id -u)" -eq 0 ]]; then
	# When the LOCAL user id and group are not given.
	if [[ -n "${LOCAL_USER}" ]]; then
		WriteLog "User uid:gid (${LOCAL_USER}) from passed environment variable 'LOCAL_USER'."
	else
		# Try taking them from the mounted project directory if it exists.
		if mountpoint -q /mnt/project; then
			LOCAL_USER="$(stat /mnt/project --format='%u:%g')"
			WriteLog "User uid:gid (${LOCAL_USER}) from project mount."
		# Taking them from the home directory.
		else
			LOCAL_USER="$(stat "${HOME}" --format='%u:%g')"
			WriteLog "User uid:gid (${LOCAL_USER}) from current home directory."
		fi
	fi
	usermod --uid "$(echo "${LOCAL_USER}" | cut --delimiter=: -f1)" user || exit 1
	groupmod --gid "$(echo "${LOCAL_USER}" | cut --delimiter=: -f2)" user || exit 1
	usermod --append --groups "${WINE_USER}" user || exit 1
	# Change the owner of 'user' home directory and all in the 'bin' directory.
	chown user:user ~user
	# Change the ownership of a possible the existing temporary wine directory created during the image building.
	chown user:user --recursive /tmp/wine-* 2>/dev/null
	#chown user:user -R ~user/.wine
	chown user:user --recursive ~user/bin
	# Add symlink to project mount when it exists.
	[[ -d /mnt/project ]] && ln --symbolic /mnt/project ~/project
	# Check if the wine-prefix directory available.
	if [[ -d "${WINEPREFIX}" ]]; then
		sudo --user=user mkdir "${HOME}/.wine"
		if ! bindfs --map="${USER_ID}/user:@${GROUP_ID}/@user" "${WINEPREFIX}" "${HOME}/.wine"; then
			WriteLog "Binding wine-prefix '${WINEPREFIX}' onto '${HOME}/.wine' failed!"
			exit 1
		fi
		WriteLog "Wine prefix '${WINEPREFIX}' bound to '${HOME}/.wine'."
		# Check if an import registry is available.
		if [[ -f "${HOME}/import.reg" ]]; then
			WriteLog "Importing registry file '${HOME}/import.reg'."
			sudo --user=user wine regedit "${HOME}/import.reg" 2>/dev/null
		fi
	fi
	# Check if the Qt zipped libraries are available.
	if [[ -d "/usr/local/lib/qt" ]]; then
		WriteLog "Qt zipped library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/qt" "${HOME}/lib/qt"
	else
		# Keep track the qt version dirs of each mounted zip-file.
		declare -A arch_qt_ver_dir
		# Iterate through all the qt-*.zip files and mount them at the correct places.
		for zip_file in ls "${HOME}/qt-"*.zip; do
			if [[ "$(basename "${zip_file}")" =~ ^qt-((lnx|win)-([a-z_0-9]*))\.zip$ ]]; then
				mount_dir="${HOME}/lib/qt/${BASH_REMATCH[1]}"
				if mkdir --parent "${mount_dir}"; then
					if ! fuse-zip -o rw,nonempty,allow_other "${zip_file}" "${mount_dir}"; then
						WriteLog "Mounting Qt library zip-file '${zip_file}' onto '${mount_dir}' failed!"
					else
						# shellcheck disable=SC212
						arch_qt_ver_dir["${BASH_REMATCH[1]}"]="$(find "${mount_dir}" -maxdepth 1 -type d -regex ".*/[0-9]+\.[0-9]+\.[0-9]+$")"
						WriteLog "Qt zipped '${BASH_REMATCH[2]}' library is mounted on '${mount_dir}'."
					fi
				fi
			fi
		done
		# Fix the Qt build tools in subdir libexec for lnx-x86_64 cross-compiling architecture lnx-aarch64.
		if [[ -d "${arch_qt_ver_dir['lnx-x86_64']}" && -d "${arch_qt_ver_dir['lnx-aarch64']}" ]]; then
			mv "${arch_qt_ver_dir['lnx-aarch64']}/gcc_64/libexec" "${arch_qt_ver_dir['lnx-aarch64']}/gcc_64/libexec-original" &&
				ln -rs "${arch_qt_ver_dir['lnx-x86_64']}/gcc_64/libexec" "${arch_qt_ver_dir['lnx-aarch64']}/gcc_64/libexec"
		fi
	fi
	WriteLog "Working directory: $(pwd)"
	# Check if the host has the X11 display passed.
	if [[ -n "${DISPLAY}" && -f "${HOME}/.Xauthority" ]]; then
		# Create file for profile to import to be used when running sshd.
		echo "export DISPLAY=${DISPLAY}" >"${HOME}/.display.sh"
	fi
	# Execute CMD passed by the user when starting the image.
	if [[ $# -ne 0 ]]; then
		WriteLog "Calling command:" "${@}"
		sudo --user=user --chdir="$(pwd)" -- "${@}"
	else
		WriteLog "No command and logging in as user."
		sudo --user=user --chdir="$(pwd)" --login
	fi
# When the current user is 'user' execute the script using sudo.
elif [[ "$(id -nu)" == "user" ]]; then
	# Execute this script but now as root passing the environment variables.
	sudo -E "${0}" "${@}" || exit 1
else
	WriteLog "User(${HOME}): $(id -u) $(stat "${HOME}" --format='%u:%g') > '${*}'"
	WriteLog "Entrypoint not running as root which is required!
When using CLion replace the Docker arguments in the configuration with:
    --rm --privileged --env LOCAL_USER=\"$(id -u):$(id -u)\"
  or:
    --rm --privileged --user user:user
	"
	exit 1
fi
