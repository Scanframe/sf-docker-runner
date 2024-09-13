#!/usr/bin/env bash
{
	command -v lsb_release >/dev/null && echo -e "$(lsb_release --id --short):$(lsb_release --release --short)"
	command -v git >/dev/null && echo -e "Git:$(git --version | head -n 1 | grep -o '[^ ]*$')"
	command -v gcc >/dev/null && echo -e "GCC:$(gcc --version | head -n 1 | grep -o '[^ ]*$')"
	command -v g++ >/dev/null && echo -e "C++:$(g++ --version | head -n 1 | grep -o '[^ ]*$')"
	command -v gcc-12 >/dev/null && echo -e "GCC:$(gcc-12 --version | head -n 1 | grep -o '[^ ]*$')"
	command -v g++-12 >/dev/null && echo -e "C++:$(g++-12 --version | head -n 1 | grep -o '[^ ]*$')"
	command -v x86_64-w64-mingw32-gcc-posix >/dev/null && echo -e "MinGW GCC:$(x86_64-w64-mingw32-gcc-posix --version | head -n 1 | cut -d' ' -f3)"
	command -v x86_64-w64-mingw32-c++-posix >/dev/null && echo -e "MinGW C++:$(x86_64-w64-mingw32-c++-posix --version | head -n 1 | cut -d' ' -f3)"
	command -v cmake >/dev/null && echo -e "CMake:$(cmake --version -q | head -n 1 | grep -o '[^ ]*$')"
	command -v make >/dev/null && echo -e "GNU-Make:$(make --version | head -n 1 | grep -o '[^ ]*$')"
	command -v ninja >/dev/null && echo -e "Ninja-Build:$(ninja --version)"
	command -v clang-format >/dev/null && echo -e "CLang-Format:$(clang-format --version | cut -d' ' -f4)"
	command -v gdb >/dev/null && echo -e "Gdb:$(gdb --version | head -n 1 | grep -o '[^ ]*$')"
	command -v ld >/dev/null && echo -e "GNU-Linker:$(ld -version | head -n 1 | grep -o '[^ ]*$')"
	[[ -d ~/lib/Qt ]] && echo -e "Qt-Lib-Lnx:$(basename "$(ls -d ~/lib/Qt/*.*.*)")"
	[[ -d ~/lib/QtWin ]] && echo -e "Qt-Lib-Win:$(basename "$(ls -d ~/lib/QtWin/*.*.*)")"
	command -v doxygen >/dev/null && echo -e "DoxyGen:$(doxygen --version)"
	command -v dot >/dev/null && echo -e "Graphviz:$(dot -V 2>&1 | cut -d' ' -f5)"
	command -v exiftool >/dev/null && echo -e "Exif-Tool:$(exiftool -ver)"
	command -v dpkg >/dev/null && echo -e "Dpkg:$(dpkg --version | head -n 1 | cut -d' ' -f7)"
	command -v rpm >/dev/null && echo -e "RPM:$(rpm --version | grep -o '[^ ]*$')"
	command -v java >/dev/null && echo -e "OpenJDK:$(java --version | head -n 1 | cut -d' ' -f2)"
	command -v bindfs >/dev/null && echo -e "BindFS:$(bindfs --version | grep -o '[^ ]*$')"
	command -v fuse-zip >/dev/null && echo -e "Fuse-ZIP:$(fuse-zip --version 2>&1 | head -n 1 | cut -d' ' -f3)"
	command -v jq >/dev/null && echo -e "JQ:$(jq --version | cut -d'-' -f2)"
	command -v gcovr >/dev/null && echo -e "Gcovr:$(gcovr --version | head -n 1 | grep -o '[^ ]*$')"
	command -v python3 >/dev/null && echo -e "Python3:$(python3 --version | cut -d' ' -f2)"
	if command -v wine64 >/dev/null; then
		echo -e "Wine:$(wine64 --version | sed 's/^wine-\(\S*\).*$/\1/')"
		winver="$(DISPLAY='' wine cmd /c ver 2>/dev/null)"
		echo "Wine > Windows:$(echo "${winver:4}" | cut -d' ' -f3)"
		if [[ -f "${HOME}/.wine/drive_c/python/python.exe" ]]; then
			echo "Wine > Python:$(wine cmd /c 'python' --version 2>/dev/null)"
		fi
	fi
} | column --table --separator ':' --table-columns 'Application,Version'
