# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022


# Set some colors for the prompt.\n\
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
umask 022
# You may uncomment the following lines if you want 'ls' to be colorized.
export LS_OPTIONS='--color=auto'
alias la='ls $LS_OPTIONS -A'
alias ll='ls $LS_OPTIONS -alF'
alias l='ls $LS_OPTIONS -CF'

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# Source the profile script when available.
if [ -f "$HOME/bin/profile.sh" ] ; then
    source "$HOME/bin/profile.sh"
fi