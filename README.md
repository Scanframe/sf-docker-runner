# Docker & GitLab-Runner

## Purpose

The purpose is multiple:
1. Using Docker to run a GitLab runner which use Docker images to execute jobs.
2. Create a Docker image for building C++ projects which are uploaded to a self-hosted Sonatype Nexus server.
3. Enable GitLab runner cache using the S3-API from a self-hosted MinIO server using a Docker image.

### 1) GitLab-Runner via Docker

Running GitLab provided Docker image (`gitlab/gitlab-runner:latest`) for running a runner.  
A script [`gitlab-runner.sh`](gitlab-runner.sh "Link to the script.") is provided to execute it.

### 2) Create Docker C++ Build Image & Hosted on a Nexus Server

To build C++ projects using a Docker image the next Docker configuration is used
[`Dockerfile`](cpp-builder%2FDockerfile "Link to the docker file.").
Applications within the Docker image to C++ projects are:
* CMake
* CTest
* Doxygen
* Qt library (Linux & Windows using a cross-compiler)

To create the image and upload it to the Sonatype Nexus server the script [cpp-builder.sh](cpp-builder.sh) 
is created to handle it. 

### 3) Enable GitLab Runner Cache using a MinIO Server 

Set up MinIO server using a docker image named (`minio/minio:latest`) and for the controlling 
the server from the command line the image (`minio/mc:latest`).  
For easy usage and set up the script [minio.sh](minio.sh "Link to the script.") is used.