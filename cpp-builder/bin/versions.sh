#!/usr/bin/env bash
{
	echo -e "Ubuntu:$(lsb_release --release --short)"
	echo -e "GCC:$(gcc --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "C++:$(g++ --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "MinGW GCC:$(x86_64-linux-gnu-gcc --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "MinGW C++:$(x86_64-linux-gnu-g++ --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "CMake:$(cmake --version -q | head -n 1 | grep -o '[^ ]*$')"
	#echo -e "CTest:$(ctest --version -q | head -n 1 | grep -o '[^ ]*$')"
	#echo -e "CPack:$(cpack --version -q | head -n 1 | grep -o '[^ ]*$')"
	echo -e "GNU-Make:$(make --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "Ninja-Build:$(ninja --version)"
	echo -e "CLang-Format:$(clang-format --version | cut -d' ' -f4)"
	echo -e "Gdb:$(gdb --version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "GNU-Linker:$(ld -version | head -n 1 | grep -o '[^ ]*$')"
	echo -e "Qt-Lib-Lnx:$(basename "$(ls -d ~/lib/Qt/*.*.*)")"
	echo -e "Qt-Lib-Win:$(basename "$(ls -d ~/lib/QtWin/*.*.*)")"
	echo -e "DoxyGen:$(doxygen --version)"
	echo -e "Graphviz:$(dot -V 2>&1 | cut -d' ' -f5)"
	echo -e "Exif-Tool:$(exiftool -ver)"
	echo -e "Dpkg:$(dpkg --version | head -n 1 | cut -d' ' -f7)"
	echo -e "RPM:$(rpm --version | grep -o '[^ ]*$')"
	echo -e "OpenJDK:$(java --version | head -n 1 | cut -d' ' -f2)"
	echo -e "BindFS:$(bindfs --version | grep -o '[^ ]*$')"
	echo -e "Fuse-ZIP:$(fuse-zip --version 2>&1 | head -n 1 | cut -d' ' -f3)"
	echo -e "JQ:$(jq --version | cut -d'-' -f2)"
	echo -e "Gcovr:$(gcovr --version | head -n 1 | grep -o '[^ ]*$')"
	if command -v wine64 >/dev/null; then
		echo -e "Wine:$(wine64 --version | sed 's/^wine-\(\S*\).*$/\1/')"
	else
		echo -e "Wine:not-installed"
	fi
} | column --table --separator ':' --table-columns 'Part,Version'
