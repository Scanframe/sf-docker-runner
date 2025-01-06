#!/bin/bash

# Bailout on first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"

# Run Docker image without a Qt version configured.
"${script_dir}/cpp-builder.sh" --qt-ver '' --project "${script_dir}/../../../applications/linux/QtBuild" run