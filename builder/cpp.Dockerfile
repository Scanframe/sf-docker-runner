# Base image must be given from the build command line.
ARG BASE_IMG
FROM ${BASE_IMG}

LABEL \
	org.opencontainers.image.authors="Arjan van Olphen <arjan@scanframe.nl>"\
	org.opencontainers.image.description="C++/Qt project build container with support for Windows cross compile."\
	org.opencontainers.image.version="0.4"

## Let apt-get know we are running in noninteractive mode
ENV DEBIAN_FRONTEND=noninteractive

# Use a mirror list as mirror server.
#RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//mirror:\/\/mirrors\.ubuntu\.com\/mirrors\.txt/' /etc/apt/sources.list
#RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//http:\/\/nl.archive.ubuntu.com\/ubuntu\//' /etc/apt/sources.list

## Make sure image is up-to-date
#RUN apt-get update && apt-get --yes upgrade
#
## Install the packages needed for adding other package repositories.
#RUN apt --yes install wget curl gpg lsb-release software-properties-common
#
## Add the LVM tool chain as apt repository for the latest version.
#RUN wget https://apt.llvm.org/llvm-snapshot.gpg.key -O /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
#    echo "deb http://apt.llvm.org/$(lsb_release -sc)/ llvm-toolchain-$(lsb_release -sc) main" > /etc/apt/sources.list.d/llvm-toolchain.list
#
## Add the KitWare package repository for cmake to get the lastest version.
#RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - > /etc/apt/trusted.gpg.d/kitware.gpg && \
#    apt-add-repository --yes "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main"
#
## Install all packages needed for all the tools.
#RUN apt-get --yes install locales sudo git make cmake ninja-build gcc g++ g++-mingw-w64-x86-64 gdb clang-format \
#    bindfs fuse-zip exif doxygen graphviz dialog jq recode default-jre-headless joe mc colordiff dos2unix
#
## Install needed libraries for building/compiling and packaging.
#RUN apt-get --yes install libopengl0 libgl1-mesa-dev libxkbcommon-dev libxkbfile-dev libvulkan-dev libssl-dev \
#    strace exiftool rpm
#
## Install needed libraries for running a Qt GUI application.
#RUN apt-get --yes install x11-apps xcb libxkbcommon-x11-0 libxcb-cursor0 libxcb-shape0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0


# Make sure image is up-to-date
# Install wine 64-bit only and Wine HQ to get Wine version 9.0 eventually.
# Also add 'xvfb' to create a fake X-server to run and install Wine properly.
RUN apt-get update && apt-get --yes upgrade && \
    apt --yes install wget curl gpg lsb-release software-properties-common iproute2 iputils-ping binutils && \
    add-apt-repository --yes --no-update ppa:git-core/ppa && \
    wget --quiet "https://apt.llvm.org/llvm-snapshot.gpg.key" -O /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    apt-add-repository --yes --no-update "deb http://apt.llvm.org/$(lsb_release -sc)/ llvm-toolchain-$(lsb_release -sc) main" && \
    wget --quiet -O - "https://apt.kitware.com/keys/kitware-archive-latest.asc" | gpg --dearmor - > /etc/apt/trusted.gpg.d/kitware.gpg && \
    apt-add-repository --yes "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" && \
    apt-get --yes install \
    locales sudo git make cmake ninja-build gcc-12 g++-12 g++-mingw-w64-x86-64 gdb valgrind clang-format chrpath dpkg-dev \
    bindfs fuse-zip exif doxygen graphviz dialog jq recode pcregrep default-jre-headless joe mc colordiff dos2unix \
    libopengl0 libgl1-mesa-dev libxkbcommon-dev libxkbfile-dev libvulkan-dev libssl-dev strace exiftool rpm nsis \
    x11-apps xcb libxkbcommon-x11-0 libxcb-cursor0 libxcb-shape0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 wine64 xvfb && \
    wget -q https://dl.winehq.org/wine-builds/winehq.key -O - | gpg --dearmor --output /etc/apt/trusted.gpg.d/winehq.gpg && \
    apt-add-repository --uri "https://dl.winehq.org/wine-builds/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/" --component main && \
    dpkg --add-architecture i386 && \
    apt-get --yes update && apt-get --yes install winehq-stable python3 python3-venv && \
    apt-get --yes autoremove --purge && apt-get --yes clean && rm -rf /var/lib/apt/lists/*

# Copy some needed scripts to the root bin directory.
COPY bin/.profile /root/bin/.profile
COPY build-scripts/gcovr-install.sh /root/bin/gcovr-install.sh
# Install latest gcovr command using pip in an virtual environement.
RUN /root/bin/gcovr-install.sh

# Qt requires locale UTF8.
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Use '/bin/bash' instead of default '/bin/sh'.
SHELL ["/bin/bash", "-c"]

# Set the working directory inside the container.
# Also used to put the build context into.
WORKDIR "/home/user"

# Initial user ids used for installing as regular and not as root.
ENV USER_ID=99999
ENV GROUP_ID=99999

RUN addgroup --gid ${GROUP_ID} user
RUN useradd --shell /bin/bash -u ${USER_ID} -g ${GROUP_ID} -o -c "" -m user
ENV HOME="/home/user"
RUN chown -R user:user "${HOME}"
# Set user password to 'user'.
RUN echo 'user:user' | chpasswd
# Creating file '/etc/sudoers.d/wine-user' to allow sudo without password.
RUN bash -c 'echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/plain-user'

RUN printf "\
# Modify the defaults for the members of User_Alias USERLIST\n\
Defaults:USERLIST runcwd=*\n\
# User alias specification\n\
User_Alias USERLIST = user\n\
" > /etc/sudoers.d/chdir-allowed

# Initialize wine for user 'user'.
#RUN su user -c '/usr/bin/wineboot --init' && rm -rf /tmp/wine-*

# Create '.profile' file in the home directory.
RUN sudo --user=user -- printf "\
if [ "\$BASH" ]; then\n\
  if [ -f ~/.bashrc ]; then\n\
    . ~/.bashrc\n\
  fi\n\
fi\n\
# set PATH so it includes user's private bin if it exists\n\
if [ -d \"\$HOME/bin\" ] ; then\n\
    PATH=\"\$HOME/bin:\$PATH\"\n\
fi\n\
mesg n || true\n\
" | tee "${HOME}/.profile" > "${HOME}/.bash_profile"

# Create '.bashrc' file in the home directory.
RUN sudo --user=user -- printf "\
# Set some colors for the prompt.\n\
export PS1='\\[\\033[01;32m\\]\\\u@\\h\\[\\033[00m\\]:\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '\n\
umask 022\n\
# You may uncomment the following lines if you want 'ls' to be colorized:\n\
export LS_OPTIONS='--color=auto' WINEDLLOVERRIDES='mscoree=d'\n\
alias la='ls \$LS_OPTIONS -A'\n\
alias ll='ls \$LS_OPTIONS -alF'\n\
alias l='ls $\LS_OPTIONS -CF'\n" > "${HOME}/.bashrc"

# Allow fuse by others.
RUN sed -i -e 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

# Use the arguments to pass the library URL.
ARG NEXUS_SERVER_URL
ARG NEXUS_RAW_LIB_URL
# Get the compressed Qt library.
#RUN wget "${NEXUS_RAW_LIB_URL}/qt-lnx.zip" -O "qt-lnx.zip"
ADD "${NEXUS_RAW_LIB_URL}/qt-lnx.zip" "qt-lnx.zip"
# Get the compressed QtWin library.
#RUN wget "${NEXUS_RAW_LIB_URL}/qt-win.zip" -O "qt-win.zip"
ADD "${NEXUS_RAW_LIB_URL}/qt-win.zip" "qt-win.zip"

# Make Wine configure itself using a different prefix to install and mount later as '~/.wine'.
ENV WINEPREFIX="/opt/wine-prefix"
RUN (Xvfb :10 -screen 0 1024x768x24 &) && \
    sudo mkdir "${WINEPREFIX}" && sudo chown user:user "${WINEPREFIX}" && \
    sudo --user=user WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="mscoree=d" DISPLAY=:10 wineboot

# Copy the Windows registry files as a fix since no registry files are created during the build.
RUN wget "${NEXUS_RAW_LIB_URL}/wine-reg.tgz" -O- | tar -C "${WINEPREFIX}" -xzf -

# Allow the initial user to run the sudo command.
RUN usermod -aG sudo user

# Create an 'import.reg' registry file for the 'entrypoint.sh' script to import since
# somehow the Wine registry during a build does not work.
RUN sudo --user=user -- printf "\
Windows Registry Editor Version 5.00\n\
\n\
[HKEY_CURRENT_USER\Environment]\n\
\"PATH\"=\"C:\\\\\\python;C:\\\\\\python\\\\\\Scripts\"\n\
\n" > "${HOME}/import.reg" # && sudo --user=user WINEPREFIX="${WINEPREFIX}" wine regedit "${HOME}/import.reg"

# Make sure the user inside the docker container has the same ID as the user outside
COPY --chown="user:user" --chmod=755 bin/*.sh "${HOME}/bin/"

# Create the entry point.
RUN chmod 755 "${HOME}/bin/entrypoint.sh"
ENTRYPOINT ["/home/user/bin/entrypoint.sh"]
