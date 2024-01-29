# Docker & GitLab-Runner

## Purpose

The purpose is multiple.

### 1) GitLab-Runner via Docker

Running GitLab provided Docker image (`gitlab/gitlab-runner:latest`) for running a runner.  
A script [`gitlab-runner.sh`](gitlab-runner.sh) is provided to execute it.

### 2) Build C++ Projects using Docker

Building C++ projects using a Docker image ([`Dockerfile`](Dockerfile)).  
The C++ projects are using CMake, CTest, Doxygen and the Qt library.  
Targets are build for Linux and Windows which is using a cross-compiler.

### 3) Docker Image CI-Pipeline

Set up a CI-pipeline to compile the Docker C++ build image and push it to the Sonatype Nexus server.   