#!/usr/bin/env bash

# mc alias set gitlab "${MINIO_URL}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
mc -C "${MC_CFG_DIR}" config host add vps "${MINIO_URL}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
# List the aliases to see if it exists,
mc -C "${MC_CFG_DIR}" alias ls
# Get information on the minio server.
mc -C "${MC_CFG_DIR}" admin info vps
# List the entries in all the buckets.
mc -C "${MC_CFG_DIR}" ls -r vps
