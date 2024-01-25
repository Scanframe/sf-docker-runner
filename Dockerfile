FROM ubuntu:22.04

MAINTAINER Arjan van Olphen
LABEL Description="A docker test container for building docker images." Version="0.1"

# Use '/bin/bash' instead of default '/bin/sh'.
SHELL ["/bin/bash", "-c"]

## Let apt-get know we are running in noninteractive mode
ENV DEBIAN_FRONTEND noninteractive

# Use a mirror list as mirror server.
#RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//mirror:\/\/mirrors\.ubuntu\.com\/mirrors\.txt/' /etc/apt/sources.list
RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//http:\/\/nl.archive.ubuntu.com\/ubuntu\//' /etc/apt/sources.list

RUN apt-get update && apt-get -y install sudo wget joe mc

ENV USER_ID 1001
ENV GROUP_ID 1001
ENV HOME /home/user

RUN addgroup --gid $GROUP_ID user
RUN useradd --shell /bin/bash -u $USER_ID -g $GROUP_ID -o -c "" -m user
RUN chown -R user:user $HOME
# Set user password to 'user'.
RUN echo 'user:user' | chpasswd

# Creating file '/etc/sudoers.d/wine-user' to allow sudo without password.
RUN bash -c 'echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/common-user'

# Create '.profile' file in the home directory.
RUN sudo -u user -- printf "\
if [ "$BASH" ]; then\n\
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
RUN sudo -u user -- printf "\
# Set some colors for the prompt.\n\
export PS1='\\[\\033[01;32m\\]\\\u@\\h\\[\\033[00m\\]:\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '\n\
umask 022\n\
# You may uncomment the following lines if you want 'ls' to be colorized:\n\
export LS_OPTIONS='--color=auto'\n\
alias la='ls $LS_OPTIONS -A'\n\
alias ll='ls $LS_OPTIONS -alF'\n\
alias l='ls $LS_OPTIONS -CF'\n\
# Other normal wine location.\n\
" > "${HOME}/.bashrc"

# Make sure the user inside the docker has the same ID as the user outside
COPY --chown=user:user --chmod=755 bin/*.sh "${HOME}/bin/"

RUN chmod 755 "${HOME}/bin/entrypoint.sh"
ENTRYPOINT ["/home/user/bin/entrypoint.sh"]
