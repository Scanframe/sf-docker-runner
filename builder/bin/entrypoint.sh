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
	# Change the ownership of the existing temporary wine directory created during the image building.
	chown user:user --recursive /tmp/wine-*
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
		# Iterate through all the qt-*.zip files and mount them at the correct places.
		for zip_file in ls "${HOME}/qt-"*.zip; do
			if [[ "$(basename "${zip_file}")" =~ ^qt-((lnx|win)-([a-z_0-9]*))\.zip$ ]]; then
				mount_dir="${HOME}/lib/qt/${BASH_REMATCH[1]}"
				if mkdir --parent "${mount_dir}"; then
					# Hack for fixing symlinks used referring to Qt.
					if [[ "${BASH_REMATCH[1]}" == 'lnx-x86_64' ]]; then
						ln -rs "${mount_dir}" "${mount_dir}/../Qt"
					fi
					if ! fuse-zip -o ro,nonempty,allow_other "${zip_file}" "${mount_dir}"; then
						WriteLog "Mounting Qt library zip-file '${zip_file}' onto '${mount_dir}' failed!"
					else
						WriteLog "Qt zipped '${BASH_REMATCH[2]}' library is mounted on '${mount_dir}'."
					fi
				fi
			fi
		done
	fi

	WriteLog "Working directory: $(pwd)"
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
	echo "Entrypoint not running as root which is required!
When using CLion replace the Docker arguments in the configuration with:
    --rm --privileged --env LOCAL_USER=\"$(id -u):$(id -u)\"
  or:
    --rm --privileged --user user:user
	"
	exit 1
fi
