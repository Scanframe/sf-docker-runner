# Base image must be given from the build command line.
ARG BASE_IMG="ubuntu"
FROM ${BASE_IMG}

LABEL \
	org.opencontainers.image.authors="Arjan van Olphen <arjan@scanframe.nl>"\
	org.opencontainers.image.description="C++/Qt project build container with support for Windows cross compile."\
	org.opencontainers.image.version="0.4"

## Let apt-get know we are running in noninteractive mode
ENV DEBIAN_FRONTEND=noninteractive

# Use '/bin/bash' instead of default '/bin/sh'.
SHELL ["/bin/bash", "-c"]

# Make sure image is up-to-date
# Install wine 64-bit only and Wine HQ to get Wine version 9.0 eventually.
# Also add 'xvfb' to create a fake X-server to run and install Wine properly.
# Packge winehq-stable is not yet available for Ubuntu version 24.04 so there is a workaround when it does.
RUN apt-get update && apt-get --yes upgrade && \
    apt-get --yes install wget curl gpg lsb-release software-properties-common iproute2 iputils-ping binutils openssh-server && \
    mkdir /run/sshd && \
    add-apt-repository --yes --no-update ppa:git-core/ppa && \
    wget --quiet "https://apt.llvm.org/llvm-snapshot.gpg.key" -O /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    apt-add-repository --yes --no-update "deb http://apt.llvm.org/$(lsb_release -sc)/ llvm-toolchain-$(lsb_release -sc) main" && \
    wget --quiet -O - "https://apt.kitware.com/keys/kitware-archive-latest.asc" | gpg --dearmor - > /etc/apt/trusted.gpg.d/kitware.gpg && \
    apt-add-repository --yes "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" && \
    apt-get --yes install \
    locales sudo git make cmake ninja-build gcc g++ g++-mingw-w64-x86-64 gdb-mingw-w64-target gdb valgrind clang-format chrpath dpkg-dev \
    bindfs fuse-zip exif doxygen graphviz dialog jq recode pcregrep default-jre-headless joe mc colordiff dos2unix shfmt \
    python3 python3-venv libopengl0 libgl1-mesa-dev libxkbcommon-dev libxkbfile-dev libvulkan-dev libssl-dev strace exiftool rpm nsis \
    x11-apps xcb libxkbcommon-x11-0 libxcb-cursor0 libxcb-shape0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 xvfb && \
    apt-get --yes autoremove --purge && apt-get --yes clean && rm -rf /var/lib/apt/lists/*

# Install Wine HQ when the machine is of 'x86_64'.
RUN if [[ "$(uname -m)" == 'x86_64' ]]; then \
      apt-get update && \
      wget -q https://dl.winehq.org/wine-builds/winehq.key -O - | gpg --dearmor --output /etc/apt/trusted.gpg.d/winehq.gpg && \
      apt-add-repository --uri "https://dl.winehq.org/wine-builds/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/" --component main && \
      dpkg --add-architecture i386 && apt-get --yes update && \
      ( \
         apt-get --yes install --simulate winehq-stable && \
         apt-get --yes install wine32:i386 wine64 winehq-stable || apt-get --yes install wine32:i386 wine64 wine \
      ) && \
      apt-get --yes autoremove --purge && apt-get --yes clean && rm -rf /var/lib/apt/lists/* ; \
    fi

# Copy some needed scripts to the root bin directory.
COPY bin/.profile /root/bin/.profile
COPY build-scripts/gcovr-install.sh /root/bin/gcovr-install.sh
# Install latest gcovr command using pip in an virtual environement.
RUN /root/bin/gcovr-install.sh

# Qt requires locale UTF8.
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

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
RUN bash -c 'echo "user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/plain-user'
# Ubuntu 24.04 does not allow the 'sudo' command '-D' or '--chdir' option even for the 'root' user.
RUN bash -c 'echo "root ALL=(ALL:ALL) CWD=* NOPASSWD: ALL" > /etc/sudoers.d/root-user'

RUN printf "\
# Modify the defaults for the members of User_Alias USERLIST\n\
Defaults:USERLIST runcwd=*\n\
# User alias specification\n\
User_Alias USERLIST = user\n\
" > /etc/sudoers.d/chdir-allowed

# Initialize wine for user 'user'.
#RUN su user -c '/usr/bin/wineboot --init' && rm -rf /tmp/wine-*

# Create '.profile' file in the home directory.
# Changes the working directory when logging in using so when deamonized the
# commands run using attach are also stzarting from the same working directory.
RUN sudo --user=user -- printf "\
if [ "\$BASH" ]; then\n\
  if [ -f ~/.bashrc ]; then\n\
    . ~/.bashrc\n\
    work_dir=\"\$(ls -d /mnt/project/* | head -n 1)\";[[ -n \"\${work_dir}\" ]] && cd \"\${work_dir}\"\n\
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
alias l='ls $\LS_OPTIONS -CF'\n\
" > "${HOME}/.bashrc"

# Allow fuse by others.
RUN sed -i -e 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

# Platform building for.
ARG PLATFORM="amd64"
# Version of the Qt library and when empty do not install a Qt library at all.
ARG QT_VERSION=""
# Use the arguments to pass the library URL.
ARG NEXUS_SERVER_URL
ARG NEXUS_RAW_LIB_URL
# Get the compressed Qt library.
RUN if [[ -n "${QT_VERSION}" ]]; then wget "${NEXUS_RAW_LIB_URL}/${PLATFORM}/qt-lnx-${QT_VERSION}.zip" -O "qt-lnx.zip"; fi
# Get the compressed QtWin library only for the 'x86_64' machine.
RUN if [[ -n "${QT_VERSION}" && "$(uname -m)" == 'x86_64' ]]; then wget "${NEXUS_RAW_LIB_URL}/${PLATFORM}/qt-win-${QT_VERSION}.zip" -O "qt-win.zip"; fi

# Make Wine configure itself using a different prefix to install and mount later as '~/.wine'.
# Remove wine temporary directories '/tmp/wine-*' at the end to allow running as a different.
# TODO: Maybe use command "winecfg /v win10" sets the Windows version for this wine instance but does not use a GUI at all.
ENV WINEPREFIX="/opt/wine-prefix"
# Install Wine only on 'x86_64' machines.
RUN if [[ "$(uname -m)" == 'x86_64' ]]; then \
    (Xvfb :10 -screen 0 1024x768x24 &) && \
    sudo mkdir "${WINEPREFIX}" && sudo chown user:user "${WINEPREFIX}" && \
    sudo --user=user WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="mscoree=d" DISPLAY=:10 wineboot && \
    rm -rf /tmp/wine-* ; \
    fi

# Copy the Windows registry files as a fix since no registry files are created during the build.
RUN if [[ "$(uname -m)" == 'x86_64' ]]; then wget "${NEXUS_RAW_LIB_URL}/wine-reg.tgz" -O- | tar -C "${WINEPREFIX}" -xzf - ; fi

# Ubuntu 24.04 has a default 'ubuntu' user.
RUN userdel --remove ubuntu || exit 0

# Allow the initial user to run the sudo command.
RUN usermod -aG sudo user

# Create an 'import.reg' registry file for the 'entrypoint.sh' script to import since
# somehow the Wine registry during a build does not work.
RUN if [[ "$(uname -m)" == "x86_64" ]]; then \
    sudo --user=user -- printf "\
Windows Registry Editor Version 5.00\n\
\n\
[HKEY_CURRENT_USER\Environment]\n\
\"PATH\"=\"C:\\\\\\python;C:\\\\\\python\\\\\\Scripts\"\n\
\n" > "${HOME}/import.reg" ;\
    fi
# && sudo --user=user WINEPREFIX="${WINEPREFIX}" wine regedit "${HOME}/import.reg" \

# Make sure the user inside the docker container has the same ID as the user outside
COPY --chown="user:user" --chmod=755 bin/*.sh "${HOME}/bin/"

# Create the entry point.
RUN chmod 755 "${HOME}/bin/entrypoint.sh"
ENTRYPOINT ["/home/user/bin/entrypoint.sh"]
