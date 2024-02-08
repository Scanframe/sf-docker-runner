#!/usr/bin/env bash

function WriteLog
{
	echo "${@}" 1>&2
}

# Report the current command to stderr
WriteLog "Entrypoint:" "${@}"

# Check if root is executing the entrypoint.
if [[ "$(id -u)" -eq 0 ]]; then
	# When the LOCAL user id and group are not given.
	if [[ -z "${LOCAL_USER}" ]]; then
		# Try taking them from the mounted project directory if it exists.
		if [[ -d /mnt/project ]]; then
			LOCAL_USER="$(stat /mnt/project --format='%u:%g')"
		# Taking them from the home directory.
		else
			LOCAL_USER="$(stat "${HOME}" --format='%u:%g')"
		fi
	fi
	usermod -u "$(echo "${LOCAL_USER}" | cut -d: -f1)" user || exit 1
	groupmod -g "$(echo "${LOCAL_USER}" | cut -d: -f2)" user || exit 1
	usermod -aG sudo user || exit 1
	usermod -aG "${WINE_USER}" user || exit 1
	# Change the owner of 'user' home directory and all in the 'bin' directory.
	chown user:user ~user
	chown user:user -R ~user/bin
	# Add symlink to project mount when it exists.
	[[ -d /mnt/project ]] && ln -s /mnt/project ~/project
	# Check if the Qt library is available.
	if [[ -d "/usr/local/lib/Qt" ]]; then
		WriteLog "Qt zipped library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/Qt" "${HOME}/lib/Qt"
	else
		QT_LNX_ZIP="${HOME}/qt-lnx.zip"
		if [[ -f "${QT_LNX_ZIP}" ]]; then
			mkdir --parents "${HOME}/lib/Qt"
			if ! fuse-zip -o ro,nonempty,allow_other "${QT_LNX_ZIP}" "${HOME}/lib/Qt"; then
				WriteLog "Mounting Qt library zip-file '${QT_LNX_ZIP}' onto '${HOME}/lib/Qt' failed!"
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
		QT_LNX_ZIP="${HOME}/qt-win.zip"
		if [[ -f "${QT_LNX_ZIP}" ]]; then
			mkdir --parents "${HOME}/lib/QtWin"
			if ! fuse-zip -o ro,nonempty,allow_other "${QT_LNX_ZIP}" "${HOME}/lib/QtWin"; then
				WriteLog "Mounting QtWin library zip-file '${QT_LNX_ZIP}' onto '${HOME}/lib/QtWin' failed!"
				exit 1
			else
				WriteLog "QtWin zipped library is mounted on '${HOME}/lib/QtWin'."
			fi
		fi
	fi
	WriteLog "Working directory: $(pwd)"
	# Execute CMD passed by the user when starting the image.
	if [[ $# -ne 0 ]]; then
		# Hack to set LD_LIBRARY_PATH when needed.
		EXEC_SCRIPT="$(realpath "$(dirname "${1}")/../lnx-exec.sh")"
		if [[ -f "${EXEC_SCRIPT}" ]]; then
			WriteLog "Using execution script '${EXEC_SCRIPT}'."
			sudo --user=user --chdir="$(pwd)" -- "${EXEC_SCRIPT}" "${@}"
		else
			sudo --user=user --chdir="$(pwd)" -- "${@}"
		fi
	else
		sudo --user=user --chdir="$(pwd)" --login
	fi
else
	WriteLog "User(${HOME}): $(id -u) $(stat "${HOME}" --format='%u:%g') > '${*}'"
	echo "Entrypoint not running as root which is required!
	When using CLion replace the Docker arguments in the configuration with:
		 --rm --privileged --env LOCAL_USER=\"$(ig -u):$(ig -u)\"
	"
	exit 1
fi
