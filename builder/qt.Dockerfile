# Qt library image derived from the Qt-less base image which already contains the toolchains.
# Base image must be given from the build command line.
ARG BASE_IMG="dummy"
FROM ${BASE_IMG}

# Use '/bin/bash' instead of default '/bin/sh'.
SHELL ["/bin/bash", "-c"]

# Version of the Qt library which is required.
ARG QT_VERSION
# Timestamp to force the Docker steps.
ARG NEXUS_TIMESTAMP=""
ARG COMPRESSION_SUFFIX=".zip"
# Use the argument to pass the library URL.
ARG NEXUS_RAW_LIB_URL

# Get the compressed Qt libraries and the cross platform libraries only for the 'x86_64' machines.
RUN set -e; \
    [[ -n "${QT_VERSION}" ]] || { echo "Build argument QT_VERSION is required!"; exit 1; }; \
    names=("lnx-$(uname -m)"); \
    if [[ "$(uname -m)" == 'x86_64' ]]; then names+=(win-x86_64 lnx-aarch64 w64-x86_64); fi; \
    for name in "${names[@]}"; do \
      wget -q "${NEXUS_RAW_LIB_URL}/qt/qt-${name}-${QT_VERSION}${COMPRESSION_SUFFIX}?${NEXUS_TIMESTAMP}" \
        -O "${HOME}/qt-${name}${COMPRESSION_SUFFIX}"; \
    done

# Create sqlite index files for faster mounting of only the Qt files and fail when one is missing.
RUN shopt -s nullglob; ratarmount --recreate-index qt-*${COMPRESSION_SUFFIX} || true; ls -la

# Make the Qt version inspectable using 'docker inspect'.
LABEL com.scanframe.qt-version="${QT_VERSION}"