#!/usr/bin/env bash

mc config host add minio "${MINIO_URL}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
