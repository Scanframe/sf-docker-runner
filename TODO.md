# TODO's on Docker Images

## Project 'cpp-builder'

### 0) Wine Registry Files on Nexus

Move the Nexus Windows registry files to the Nexus server and modify 
the `Dockerfile` usinf `ADD` instead of `COPY` or use `winget` of a single 
zip-file and decompressing it using a pipe.

### 1) Use BindFS for Home Directory

To sync the ownership of the caller which runs the container the `uid:gid` some entries 
of the home directory are changed.   
It is much faster do a mount using `bindfs` mapping the wanted `uid:gid` of the whole home directory. 

### 2) Split up C++/Qt Linux/Windows Image

Create a hierarchy of images instead of a single one doing it all.  
Images having:

* C++/CMake and tools (doxygen, gcovr)
* C++ Windows cross compiler
* Linux/Windows Qt libraries
* Wine HQ (v9.0)
* Python

