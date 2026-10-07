# Agent Instructions: Docker Projects

## Overview

This project is for build Docker images and containers for various applications.

## Boundaries

### Mandatory Git Tracking Policy

- **Strict Scope**: The "Project" consists **ONLY** of files currently tracked by Git.
- **Prohibition**: You **MUST NOT** read, reference, modify, or execute any file that is not tracked by Git.
- **Treat as Non-Existent**: Even if a file is visible in directory listings or returned by search tools, you **MUST** treat it as non-existent if it is untracked.
- **Verification Requirement**: Before interacting with any file, you **MUST** verify its status (e.g., using `git ls-files --error-unmatch <path>`). If the command fails, the file is out of bounds.

### Semantic Versioning

Although this repository does not use semantic versioning, it is recommended to follow the guidelines
provided in the document for versioning purposes.  
The document on how to version is described in [semantic-versioning.md](doc/semantic-versioning.md).

## Qt Library

The Dockerfile should include the necessary dependencies and configurations to ensure that the application runs 
smoothly within the container.

In total, five versions of the Qt library are compiled and incorporated into the 
image and have the following directory structure:

```
lib/qt
├── lnx-aarch64
│   └── 6.10.1
│       └── gcc_64
├── lnx-x86_64
│   └── 6.10.1
│       └── gcc_64
├── w64-x86_64
│   └── 6.10.1
│       ├── mingw_64
│       └── msvc_64
└── win-x86_64
    └── 6.10.1
        └── mingw_64
```

The structure is used in C++ projects that require the Qt library for building and running applications.


