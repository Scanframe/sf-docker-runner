# Base image must be given from the build command line.
ARG BASE_IMG=ubuntu:22.04
FROM ${BASE_IMG}
RUN apt-get update && \
    apt-get install --yes openssh-server sshfs && \
    apt-get --yes autoremove --purge && \
    apt-get --yes clean && \
    rm -rf /var/lib/apt/lists/*
# Configure SSH
RUN mkdir /run/sshd
RUN echo 'root:redhat' | chpasswd
#password for user login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
# Start SSH server allow '--network host' option specifying the port other then port 22.
CMD ["/usr/sbin/sshd", "-D", "-p 3022"]