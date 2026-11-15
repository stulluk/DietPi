#!/bin/sh
# Open an interactive shell in the K1 build container with the repo mounted at /work.
# Usage: ./entercontainer.sh [--privileged]
set -eu

cd "$(dirname "$0")"
IMAGE="kickpi-k1-dietpi-build:latest"
PRIV=""
if [ "${1:-}" = "--privileged" ]; then
  PRIV="--privileged -v /dev:/dev"
fi

# shellcheck disable=SC2086
docker run --rm -it ${PRIV} \
  -u "$(id -u):$(id -g)" \
  -v "$(pwd):/work" \
  -w /work \
  "${IMAGE}" \
  bash
