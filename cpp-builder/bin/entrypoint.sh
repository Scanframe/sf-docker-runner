#!/usr/bin/env bash

# Check if the entrypoint was called by root.
if [[ "$(id -u)" -ne 0 ]]; then
	echo "User(${HOME}): $(id -u) $(stat "${HOME}" --format='%u:%g') > '${*}'"
	echo "Entrypoint not running as root which is required!
When using CLion replace the Docker arguments in the configuration with:
	 --rm --privileged --env LOCAL_USER=\"$(ig -u):$(ig -u)\"
"
	exit 1
fi

# If option '--user' has not been passed switch
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
	# Add symlink to project mount.
	ln -s /mnt/project ~/project
	# Check if the Qt library is available.
	if [[ -d "/usr/local/lib/Qt" ]]; then
		echo "Qt library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/Qt" "${HOME}/lib/Qt"
	else
		QT_LNX_ZIP="${HOME}/qt-lnx.zip"
		if [[ -f "${QT_LNX_ZIP}" ]]; then
			mkdir --parents "${HOME}/lib/Qt"
			if ! fuse-zip -o ro,nonempty,allow_other "${QT_LNX_ZIP}" "${HOME}/lib/Qt"; then
				echo "Mounting Qt library zip-file '${QT_LNX_ZIP}' onto '${HOME}/lib/Qt' failed!"
				exit 1
			else
				echo "Qt library is mounted..."
			fi
		fi
	fi
	# Check if the QtWin library is available.
	if [[ -d "/usr/local/lib/QtWin" ]]; then
		echo "QtWin library is available."
		mkdir --parents "${HOME}/lib"
		ln -s "/usr/local/lib/QtWin" "${HOME}/lib/QtWin"
	else
		QT_LNX_ZIP="${HOME}/qt-win.zip"
		if [[ -f "${QT_LNX_ZIP}" ]]; then
			mkdir --parents "${HOME}/lib/QtWin"
			if ! fuse-zip -o ro,nonempty,allow_other "${QT_LNX_ZIP}" "${HOME}/lib/QtWin"; then
				echo "Mounting QtWin library zip-file '${QT_LNX_ZIP}' onto '${HOME}/lib/QtWin' failed!"
				exit 1
			else
				echo "Qt library is mounted..."
			fi
		fi
	fi
	# Execute CMD passed by the user when starting the image.
	if [[ $# -ne 0 ]]; then
		sudo --user=user -- "${@}"
	else
		sudo --user=user --login
	fi
# Check if arguments are passed.
elif [[ $# -ne 0 ]]; then
	/bin/bash --login -c "$*"
# When no arguments are passed.
else
	/bin/bash --login
fi
