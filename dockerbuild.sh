#!/bin/sh
# Build the Docker image that holds the KICKPI K1A build environment.
# Usage: ./dockerbuild.sh
set -eu

cd "$(dirname "$0")"
. ./k1/versions.env

IMAGE="kickpi-k1-dietpi-build:latest"
mkdir -p k1/logs
LOG="k1/logs/dockerbuild-$(date +%Y%m%d-%H%M%S).log"

echo "Building ${IMAGE} (log: ${LOG})"
docker build \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  -t "${IMAGE}" . 2>&1 | tee "${LOG}"
