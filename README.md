# Docker & GitLab-Runner & CLion

## Purpose

The purpose of this repository is multiple:

1. Using Docker to run a GitLab runner which uses Docker images to execute jobs.
2. Create a Docker image for building C++ projects which are uploaded to a self-hosted Sonatype Nexus server.
3. Building Executables from Python Code.
4. Enable GitLab runner cache using the S3-API from a self-hosted MinIO server using a Docker image.
5. Use the Docker image in JetBrain's CLion for checking the image only.
6. Building the Qt library/framework from source for Linux x86_64, aarch64 and Windows x86_64.

## 1) GitLab-Runner via Docker

Running GitLab provided Docker image (`gitlab/gitlab-runner:latest`) for running a runner.  
A script [`gitlab-runner.sh`](gitlab-runner.sh "Link to the script.") is provided to execute it.

## 2) Create Docker C++ Build Image & Hosted on a Nexus Docker Registry

### Primary Goal

Create a comprehensive Docker-based C++ build environment that supports:

1. **Multi-platform C++ compilation**
	- Native Linux (x86_64 and aarch64)
	- Windows cross-compilation (x86_64) using the Linux MinGW cross-compiler
	- Windows compilation (using MinGW and MSVC via Wine)

2. **Qt framework support**
	- Building Qt from source for multiple platforms
	- Packaging and hosting Qt libraries (versions like 6.8.1, 6.9.1, 6.10.1) for different architectures
	- Cross-platform Qt development (Linux → Windows)

3. **Developer tooling**
	- JetBrains CLion integration for containerized development
	- Support for debugging and running GUI applications via X11
	- The Python tool is available in native Linux and also in Wine to support cross-platform build-scripts.

### Key Technical Features

- **Base image**: Ubuntu 24.04 LTS with comprehensive C++ toolchain
- **Cross-compilation**: aarch64 and Windows (x86_64) support from x86_64 hosts
- **Wine integration**: For Windows tooling, MSVC and MinGW compilation on Linux
- **Library management**: Automated packaging/uploading of Qt libraries to Nexus
- **Entrypoint**: Sophisticated user/permission handling to match host UID/GID
- **FUSE mounting**: Zip-mounted libraries and toolchains for space efficiency


The system enables consistent, reproducible C++ builds across platforms while maintaining developer workflow
flexibility.

### Python Build Script

The `bin/build.py` script from the [**CMake Library**](https://git.scanframe.com/library/cmake-lib/-/branches) 
is responsible for automating the build process of C++ projects using CMake.  
The script provides a bootstrap option for creating a new C++ boilerplate project.
It provides a convenient interface for developers to execute build commands.  
The same script can be used for both Linux and Windows, including CI/CD-pipelines.  
See the Python script in action see the [YouTube](https://www.youtube.com/@Scanframe) channel.

> Good chance the `main` branch is not up to date and use a `dev` or `fix` branch.

### Image Content

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
* Python3 (Linux + Windows)
* SSH
* Wine
* Qt Framework (optional using `--qt-ver '6.10.1'` or leave empty for none.)

To create the image and upload it to the Sonatype Nexus server's Docker V2 registry, the
script [cpp-builder.sh](cpp-builder.sh)
is used to handle it.

For Linux the order of the steps is:

1. Pull the base image from GitHub  
	 `./cpp-builder.sh base-pull`.
2. Push the base image to the Nexus Docker registry  
	 `./cpp-builder.sh base-push`.
3. Build the image to build a Linux Qt version with  
	 `./cpp-builder.sh --qt-ver '' build`.
4. Build the image to build projects using the specified Qt version (`<qt-ver>`)  
	 `./cpp-builder.sh --qt-ver '<qt-ver>' build`.  
	 This step requires the Qt-version zipped library to be uploaded or present on the Nexus shared storage.
5. Push the image to the Nexus Docker registry  
	 `./cpp-builder.sh --qt-ver '<qt-ver>' push`.
6. Push the image to Docker Hub registry  
	 `./cpp-builder.sh --qt-ver '<qt-ver>' docker-push`.
6. Make the image get the latest tag on Docker Hub  
	 `./cpp-builder.sh --qt-ver '<qt-ver>' docker-latest`.

> For the **aarch64** version the same steps are performed on a Raspberry Pi 5 or an **aarch64** image running on an *
*x86_64** machine using **qemu**.  
> The **aarch64** image can only build QT targets for **aarch64** as where the **x86_64** one does all 3.

The zip-files are locally stored in the Nexus repository having the following directory structure:

```text
<file-server>/library/qt/
├── lnx-aarch64
│   ├── 6.8.1
│   │   └── gcc_64
│   └── 6.10.1
│       └── gcc_64
├── lnx-x86_64
│   ├── 6.8.1
│   │   └── gcc_64
│   └── 6.10.1
│       └── gcc_64
├── w64-x86_64
│   ├── 6.8.1
│   │   └── mingw_64
│   └── 6.10.1
│       └── mingw_64
└── win-x86_64
    ├── 6.8.1
    │   └── mingw_64
    └── 6.10.1
        └── mingw_64
```

To create the Qt-version zip-files for the Nexus shared storage, the following script commands ar used:
> The `--platform` flag is optional and defaults to `amd64` on an `x86_64` machine.

* `./cpp-builder.sh --platform qt-lnx`
* `./cpp-builder.sh --platform arm64 qt-lnx`
* `./cpp-builder.sh qt-win`
* `./cpp-builder.sh qt-w64`

Upload the created zip-files to the Nexus shared storage.

* `./cpp-builder.sh --platform qt-lnx-up`
* `./cpp-builder.sh --platform arm64 qt-lnx-up`
* `./cpp-builder.sh qt-win-up`
* `./cpp-builder.sh qt-w64-up`

## 3) Building Executables from Python Code

Command line examples for building executables of a Python project containing executable `*.py` files.

```shell
./py-builder.sh --project ../../pysrc/dev-tools run -- wine venv-setup.cmd mk-exec.cmd nexus-docker.py
./py-builder.sh --project ../../pysrc/dev-tools run -- ./venv-setup.sh ./mk-exec.sh nexus-docker.py
```

## 4) Enable GitLab Runner Cache using a MinIO Server

Set up MinIO server using a docker image named (`minio/minio:latest`) and for the controlling
the server from the command line the image (`minio/mc:latest`).  
For easy usage and set up the script [minio.sh](minio.sh "Link to the script.") is used.

## 5) CLion Using Docker the Image

To have CLion compile CMake projects using Qt arguments passed to the Docker `run` command need to be
changed to have the original [entrypoint](builder/bin/entrypoint.sh) to execute the command.
CLion Docker command-line arguments: `--rm --privileged --user 0:0 --env USER_LOCAL="<uid>:<gid>"`
where **uid** and **gid** is the current users user and group id.
Debugging is not possible since the intermediate `entrypoint.sh` script prevents this.
Running a console application is possible from CLion.  
Running GUI applications, the X11 socket needs to be configured with additional run options  
`--env DISPLAY --volume "${HOME}/.Xauthority:/home/user/.Xauthority:ro"`.
CLion does not do variable expansion for Docker command line arguments, so expand them manually.

## 6) Building the Qt Library/Framework from Source

Shell script `build-qt-lib.sh` is for building the framework libraries for Linux and for Windows
using multiple command steps:

1. Pulling a Git-tagged version of the Qt source.
2. Initializing the Git-submodules.
3. Installing the dependent libraries for Linux or dependent applications for Windows.
4. Configuring the cmake files for parts that are only needed to build.
5. Fix the cmake cache file when needed and configure again.
6. Installing the libraries into the correct named Qt version directory for projects.
7. Zipping the version for mounting in a Qt-versioned Docker Qt build container.

See also the [Qt from source](doc/qt-from-source.md) document.

::include{file=doc/cpp-builder-process.puml}
