<!-- TOC -->

* [Docker & GitLab-Runner & CLion](#docker--gitlab-runner--clion)
	* [Purpose](#purpose)
		* [1) GitLab-Runner via Docker](#1-gitlab-runner-via-docker)
		* [2) Create Docker C++ Build Image & Hosted on a Nexus Server](#2-create-docker-c-build-image--hosted-on-a-nexus-server)
			* [Building Executables from Python Code](#building-executables-from-python-code)
		* [3) Enable GitLab Runner Cache using a MinIO Server](#3-enable-gitlab-runner-cache-using-a-minio-server-)
		* [4) CLion Using Docker the Image](#4-clion-using-docker-the-image-)
		* [5) Building the Qt Library/Framework from Source](#5-building-the-qt-libraryframework-from-source)

<!-- TOC --># Docker & GitLab-Runner & CLion

## Purpose

The purpose is multiple:

1. Using Docker to run a GitLab runner which use Docker images to execute jobs.
2. Create a Docker image for building C++ projects which are uploaded to a self-hosted Sonatype Nexus server.
3. Enable GitLab runner cache using the S3-API from a self-hosted MinIO server using a Docker image.
4. Use the Docker image in JetBrain's CLion for checking the image only.
5. Building the Qt library/framework from source for Linux x86_64, aarch64 and Windows x86_64.

### 1) GitLab-Runner via Docker

Running GitLab provided Docker image (`gitlab/gitlab-runner:latest`) for running a runner.  
A script [`gitlab-runner.sh`](gitlab-runner.sh "Link to the script.") is provided to execute it.

### 2) Create Docker C++ Build Image & Hosted on a Nexus Server

To build C++ projects using a Docker image the next Docker configuration is used
[`Dockerfile`](builder/cpp.Dockerfile "Link to the docker file.").
Applications within the Docker image to C++ projects are:
* Ubuntu LTS
* Git
* GCC
* C++
* Arch64 GCC
* Arch64 C++
* MinGW GCC
* MinGW C++
* CMake
* CTest
* CPack
* GNU-Make
* Ninja-Build
* CLang-Format
* Gdb
* GNU-Linker
* DoxyGen
* Graphviz
* Exif-Tool
* Dpkg
* RPM
* OpenJDK
* BindFS
* Fuse-ZIP
* JQ
* Gcovr
* Python3
* SSH
* Wine
* Qt Framework (optional using `--qt-ver '6.8.1'` or leave empty for none.)

To create the image and upload it to the Sonatype Nexus server the script [cpp-builder.sh](cpp-builder.sh)
is created to handle it.

#### Building Executables from Python Code

Command line examples for building executables of a Python project containing executable `*.py` files.

```shell
./py-builder.sh --project ../../pysrc/dev-tools run -- wine venv-setup.cmd mk-exec.cmd nexus-docker.py
./py-builder.sh --project ../../pysrc/dev-tools run -- ./venv-setup.sh ./mk-exec.sh nexus-docker.py
```

### 3) Enable GitLab Runner Cache using a MinIO Server

Set up MinIO server using a docker image named (`minio/minio:latest`) and for the controlling
the server from the command line the image (`minio/mc:latest`).  
For easy usage and set up the script [minio.sh](minio.sh "Link to the script.") is used.

### 4) CLion Using Docker the Image

To have CLion compile CMake projects using Qt arguments passed to the Docker `run` command need to be
changed in order to have the original [entrypoint](builder/bin/entrypoint.sh) to execute the command.
CLion Docker command-line arguments: `--rm --privileged --user 0:0 --env USER_LOCAL="<uid>:<gid>"`
where **uid** and **gid** is the current users user and group id.
Debugging is not possible since the intermediate `entrypoint.sh` script prevents this.
Running a console application is possible from CLion.  
Running GUI applications the X11 socket needs to be configured with additional run options  
`--env DISPLAY --volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro"`.
CLion does not do variable expansion for Docker command line arguments so expand them manually.

### 5) Building the Qt Library/Framework from Source

Shell script `build-qt-lib.sh` is for building the framework libraries for Linux and for Windows
using multiple command steps:

1. Pulling a Git tagged version of the Qt source.
2. Initializing the Git-submodules.
3. Installing the dependent libraries for Linux or dependent applications for Windows.
4. Configuring the cmake files for parts that is only needed to build.
5. Fix cmake cache file when needed and configure again.
6. Installing the libraries into the correct named Qt version directory for projects.
7. Zipping the version for mounting in a Qt versioned Docker Qt build container.

For Linux Qt it is best to build it using a Docker container having the correct distro.  
The build for Windows is done using the same shell script
using [Cygwin](https://github.com/Scanframe/sf-cygwin-bin "Cygwin repository at GitHub.").
Use the [cpp-builder.sh](cpp-builder.sh) script with option `--qt-ver ''` which builds docker
image without Qt libraries from which the Qt library itself can be built. 

