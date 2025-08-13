# Base image must be given from the build command line.
ARG BASE_IMG="ubuntu"
FROM ${BASE_IMG}

LABEL \
	org.opencontainers.image.authors="Arjan van Olphen <arjan@scanframe.nl>"\
	org.opencontainers.image.description="Borland C++ Builder executable build container for Windows using Wine."\
	org.opencontainers.image.version="0.5"

## Let apt-get know we are running in noninteractive mode
ENV DEBIAN_FRONTEND=noninteractive

# Use '/bin/bash' instead of default '/bin/sh'.
SHELL ["/bin/bash", "-c"]

# Install wine 64-bit only and Wine HQ to get Wine version 9.0 eventually.
# Also add 'xvfb' to create a fake X-server to run and install Wine properly.
RUN apt-get update && apt-get --yes upgrade && \
    apt --yes install wget curl gpg iputils-ping lsb-release software-properties-common binutils iproute2 iputils-ping && \
    add-apt-repository --yes --no-update ppa:git-core/ppa && \
    apt-get --yes install \
    locales sudo git bindfs fuse-zip dialog jq recode pcregrep zip joe mc colordiff dos2unix libopengl0 strace exiftool x11-apps xcb \
    libxkbcommon-x11-0 libxcb-cursor0 libxcb-shape0 libxcb-icccm4 libxcb-xinput0 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 wine64 xvfb && \
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

# Qt requires locale UTF8.
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

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
ARG NEXUS_WIN_APP_URL

# Make Wine configure itself using a different prefix to install and mount later as '~/.wine'.
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

ADD "${NEXUS_WIN_APP_URL}/BCB5.zip" "/opt/wine-apps/"
#ADD "${NEXUS_WIN_APP_URL}/BCB6.zip" "/opt/wine-apps/"

# Make sure the user inside the docker container has the same ID as the user outside
COPY --chown="user:user" --chmod=755 bin/*.sh "${HOME}/bin/"

# Create the entry point.
RUN chmod 755 "${HOME}/bin/entrypoint.sh"
ENTRYPOINT ["/home/user/bin/entrypoint.sh"]
