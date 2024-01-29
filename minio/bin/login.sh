#!/usr/bin/env bash

mc config host add minio "http://localhost:9000" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"

