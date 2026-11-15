#!/bin/sh
# Run a K1 build stage inside the build container.
# Usage: ./indockerbuild.sh <stage> [jobs]
#   stage: fetch | kernel | uboot | image | all
#   jobs : parallel make jobs (default: 80% of host cores)
set -eu

cd "$(dirname "$0")"
STAGE="${1:-all}"
JOBS="${2:-$(( $(nproc) * 8 / 10 ))}"
IMAGE="kickpi-k1-dietpi-build:latest"
mkdir -p k1/logs
LOG="k1/logs/${STAGE}-$(date +%Y%m%d-%H%M%S).log"

# The image stage needs loop devices, mounts and systemd-nspawn: privileged container.
PRIV=""
if [ "${STAGE}" = "image" ] || [ "${STAGE}" = "all" ]; then
  PRIV="--privileged -v /dev:/dev"
fi

echo "Stage ${STAGE}, ${JOBS} jobs, log: ${LOG}"
# shellcheck disable=SC2086
docker run --rm ${PRIV} \
  --cpus="${JOBS}" \
  -e JOBS="${JOBS}" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd):/work" \
  -w /work \
  "${IMAGE}" \
  ./k1/build.sh "${STAGE}" 2>&1 | tee "${LOG}"
