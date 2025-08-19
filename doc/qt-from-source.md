# Building the Qt Library from Source

## Introduction

The shell script [`build-qt-lib.sh`](build-qt-lib.sh) is for building the framework libraries
for Linux and for Windows in multiple command steps and is described here.

For Linux Qt it is best to build it using a Docker container having the correct distro.  
The build for Windows is done using the same shell script
using [Cygwin](https://github.com/Scanframe/sf-cygwin-bin "Cygwin repository at GitHub.").
Use the [cpp-builder.sh](cpp-builder.sh) script with option `--qt-ver ''` which builds docker
image without Qt libraries from which the Qt library itself can be built.

## Build the C++ Docker Image without Qt Libs

The script [cpp-builder.sh](cpp-builder.sh) is used to build the C++ Docker image.
It builds one without Qt libraries and one with Qt libraries.

The first common steps are:

**1) Pull the possible updated base image.**

```shell
./cpp-builder.sh base-pull
# Under the hood, when running from a Linux x86_64 machine:
./cpp-builder.sh --base-image amd64/ubuntu --platform amd64 base-pull
# Under the hood, when running from a Linux aarch64 machine:
./cpp-builder.sh --base-image arm64v8/ubuntu --platform arm64 base-pull
```

**2) Push the base image to the Nexus registry.**

```shell
./cpp-builder.sh base-push
# Or full command:
./cpp-builder.sh --base-image amd64/ubuntu --platform amd64 base-push
```

**3) Build the `gnu-cpp` image without the Qt-library.**

By specifying option `--qt-ver` as empty string the script will build the image without Qt libraries.

```shell
./cpp-builder.sh --qt-ver '' build
# Or full command:
./cpp-builder.sh --base-image amd64/ubuntu --platform amd64 --qt-ver '' build
```

**4) Push the image without the Qt-library to the Nexus registry.**

```shell
./cpp-builder.sh --qt-ver '' push
# Or full command:
./cpp-builder.sh --base-image amd64/ubuntu --platform amd64 --qt-ver '' push
```

## Build the Qt Library

### Common Linux & Windows

Determine which version of the Qt-library to build.

```shell
./build-qt-lib.sh tags
```

Modify the `build-qt-lib.sh` script to build the correct version.
> Should be an option in the future.

### Linux Build

Run the Docker build image to get the command line.

```shell
./build-qt-lib.sh run
```

The preferred way is to use the Docker build image to build the Qt-library is starting the container
in the background and the attaching to it.

```shell
./build-qt-lib.sh start
./build-qt-lib.sh attach
```

When started the project must be `/mnt/project/build-src` and must be changed otherwise.
From the build-src directory the script `build-qt-lib.sh` is mounted as `build.sh`.

Run the `./build.sh` to check if it checks out the correct version.

**1) Update or install dependencies needed by the Qt-library for building.**

```shell
./build.sh deps
```

**2) Clone the Qt repository and update the submodules.**

```shell
./build.sh clone
./build.sh update
```

**3) Initialize the Qt-library build.**

The command executes the `./init-repository` script in the Qt-repository.

```shell
./build.sh init
```

**4) Configure CMake.**

```shell
./build.sh conf
```

**5) Fix features not automatically set when configuring.**

The feature `system_xcb_xinput` with flag `FEATURE_system_xcb_xinput:BOOL=OFF` should be `ON` which it is not.

To check this and fix it, run the following commands:

```shell
./build.sh check
./build.sh fix
# Check if the feature is set to ON.
./build.sh check
```

**6) Build the actual Qt-Libraries.**

```shell
./build.sh build
```

**7) Install the build into the Qt-versioned directory.**

```shell
./build.sh install
```

### Windows Build

Run the `build-qt-lib.sh` from Cygwin command line in the project

**1) Update or install dependencies needed by the Qt-library for building.**

This uses the `win-get` command.

```shell
./build-qt-lib.sh deps
```

**2) Clone the Qt repository and update the submodules.**

```shell
./build-qt-lib.sh clone
./build-qt-lib.sh update
```

**3) Initialize the Qt-library build.**

The command executes the `./init-repository.bat` script in the Qt-repository.

```shell
./build-qt-lib.sh init
```

**4) Configure CMake.**

```shell
./build.sh conf
```

**5) Build the actual Qt-Libraries.**

```shell
./build.sh build
```

**6) Install the build into the Qt-versioned directory.**

```shell
./build.sh install
```

## Windows Cross Compile Fix

For cross compiling Windows on Linux the directory `qt/win-x86_64/<qt-ver>` is created using `overlayfs` from
`qt/w64-x86_64/<qt-ver>`.  
The [`qt-cross-windows-fix.sh`](https://github.com/Scanframe/sf-cmake/blob/main/bin/qt-cross-windows-fix.sh) modifies
the `qt/win-x86_64/<qt-ver>` files and more to replace the calls to tools as
Qt MOC with the Linux versions using symbolic links to `qt/lnx-x86_64/<qt-ver>` and some other measures.

The script is called from the `lib/qt/` directory where all Qt version directories reside.

> The `qt-cross-windows-fix.sh` script also works for downloaded versions of the Qt library for Windows and Linux.

```shell
./qt-cross-windows-fix.sh -r
# Add a specific version.
./qt-cross-windows-fix.sh --run --qt-ver '<qt-ver>'
```

The script will ask for confirmation after showing the proposed directories.

```text
# Found Linux (x86_64) Qt highest version: '6.9.1'.
# Running dry...                                                                                                                                                                                                                                                                   
Proposed directories:                                                                                                                                                                                                                                                              
Linux  : lnx-x86_64/6.9.1/gcc_64
Windows: win-x86_64/6.9.1/mingw_64

Modifying Windows Qt version 6.9.1 for Cross-compiling on Linux:                                                                                                                                                                                                                  
  Source     : lnx-x86_64/6.9.1/gcc_64/lib/cmake
  Destination: win-x86_64/6.9.1/mingw_64/lib/cmake
Continue [y/N]? 
```

## Uploading Zipped Qt Libraries to Nexus

The image

To zip the three versions of the Qt libraries for Linux and Windows, run the following commands:

```shell
# Create file: /tmp/qt-lnx-x86_64-<qt-ver>.zip
./cpp-builder.sh --platform x86_64 --qt-ver '<qt-ver>' qt-lnx
# Create file: /tmp/qt-lnx-aarch64-<qt-ver>.zip
./cpp-builder.sh --platform aarch64 --qt-ver '<qt-ver>' qt-lnx
# Create file: /tmp/qt-win-x86_64-<qt-ver>.zip
./cpp-builder.sh --platform x86_64 --qt-ver '<qt-ver>' qt-win
```

The script will ask for confirmation after displaying some information like this:

```text
Qt version           : 6.9.1
Targeted Platform    : amd64
Architecture         : x86_64
Base image tag       : 24.04
Base image name      : amd64/ubuntu
Image tag            : 24.04-6.9.1
Image name           : gnu-cpp
Container name       : gnu-cpp
Temporary directory  : /tmp
Qt library directory : /mnt/server/userdata/applications/library/qt
Nexus relative path  : repository/shared/library

Continue with command 'qt-lnx' [y/N]?
```

Command to upload the zip-files to the Nexus server:

```shell
./cpp-builder.sh --platform amd64 --qt-ver '<qt-ver>' qt-lnx-up
./cpp-builder.sh --platform arm64 --qt-ver '<qt-ver>' qt-lnx-up
./cpp-builder.sh --platform amd64 --qt-ver '<qt-ver>' qt-win-up
```

The script will ask for confirmation after displaying some information.

When the zip-files are available on the Nexus server, the Docker Image for the Qt-library
can be built and successively be pushed to the Nexus Docker registry using
the [cpp-builder.sh](../cpp-builder.sh) script.

Build the Docker image for `amd64` platform with three versions of the Qt-library:

```shell
./cpp-builder.sh --qt-ver '<qt-ver>' build
```

Push the Docker image to the Nexus Docker registry:

```shell
./cpp-builder.sh --qt-ver '<qt-ver>' push
```

Push it also to the Docker Hub registry:

```shell
./cpp-builder.sh --qt-ver '<qt-ver>' docker-login
./cpp-builder.sh --qt-ver '<qt-ver>' docker-push
# Optional: Make this the 'latest' one on Docker Hub.
./cpp-builder.sh --qt-ver '<qt-ver>' docker-latest
```
