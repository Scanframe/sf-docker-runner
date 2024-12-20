#!/usr/bin/env bash

function WriteLog {
	if [[ -n "${DEBUG}" ]]; then
		echo "${@}" 1>&2
	fi
}

# Report the current command to stderr
WriteLog "Entrypoint($(id -u)):" "${@}"

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
	# Check if the Qt library is available.
	if [[ -d "/usr/local/lib/Qt" ]]; then
		WriteLog "Qt zipped library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/Qt" "${HOME}/lib/Qt"
	else
		qt_lnx_zip="${HOME}/qt-lnx.zip"
		if [[ -f "${qt_lnx_zip}" ]]; then
			mkdir --parents "${HOME}/lib/Qt"
			if ! fuse-zip -o ro,nonempty,allow_other "${qt_lnx_zip}" "${HOME}/lib/Qt"; then
				WriteLog "Mounting Qt library zip-file '${qt_lnx_zip}' onto '${HOME}/lib/Qt' failed!"
				exit 1
			else
				WriteLog "Qt zipped library is mounted on '${HOME}/lib/Qt'."
			fi
		fi
	fi
	# Check if the QtWin library is available.
	if [[ -d "/usr/local/lib/QtWin" ]]; then
		WriteLog "QtWin library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/QtWin" "${HOME}/lib/QtWin"
	else
		qt_lnx_zip="${HOME}/qt-win.zip"
		if [[ -f "${qt_lnx_zip}" ]]; then
			mkdir --parents "${HOME}/lib/QtWin"
			if ! fuse-zip -o ro,nonempty,allow_other "${qt_lnx_zip}" "${HOME}/lib/QtWin"; then
				WriteLog "Mounting QtWin library zip-file '${qt_lnx_zip}' onto '${HOME}/lib/QtWin' failed!"
				exit 1
			else
				WriteLog "QtWin zipped library is mounted on '${HOME}/lib/QtWin'."
			fi
		fi
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
elif [[ "$(id -nu)" == "user" ]] ; then
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
