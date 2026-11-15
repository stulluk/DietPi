#!/bin/sh
# Provision the built image for one board and flash it to the KICKPI K1A eMMC, fully automatic.
# Usage: ./flash.sh [image] [hostname]
#   image   : default k1/out/DietPi_KickPiK1A-ARMv8-Trixie.img
#   hostname: default kickpi-k1
# Env: K1_SERIAL (/dev/serial-ws2), K1_RELAY (192.168.1.161), K1_PUBKEY (~/.ssh/id_rsa.pub),
#      RK_BURN_TOOL (rk-burn-tool.py on PATH)
set -eu

cd "$(dirname "$0")"
IMG="${1:-k1/out/DietPi_KickPiK1A-ARMv8-Trixie.img}"
NAME="${2:-kickpi-k1}"
SERIAL="${K1_SERIAL:-/dev/serial-ws2}"
RELAY="${K1_RELAY:-192.168.1.161}"
PUBKEY="${K1_PUBKEY:-${HOME}/.ssh/id_rsa.pub}"
BURN="${RK_BURN_TOOL:-rk-burn-tool.py}"
OUT="k1/out/${NAME}.img"

[ -f "${IMG}" ] || { echo "ERROR: ${IMG} not found, run ./indockerbuild.sh all first"; exit 1; }
[ -f "${PUBKEY}" ] || { echo "ERROR: ${PUBKEY} not found"; exit 1; }
mkdir -p k1/logs
cp "${PUBKEY}" k1/out/provision.pub

echo "=== Provisioning ${IMG} -> ${OUT} (hostname ${NAME})"
docker run --rm --privileged -v /dev:/dev -v "$(pwd):/work" -w /work \
  kickpi-k1-dietpi-build:latest \
  sh -c "k1/scripts/provision-image.sh '${IMG}' '${OUT}' '${NAME}' k1/out/provision.pub \
         && chown $(id -u):$(id -g) '${OUT}'"
rm -f k1/out/provision.pub

echo "=== Flashing ${OUT} via U-Boot rockusb (relay ${RELAY}, console ${SERIAL})"
"${BURN}" --mode raw --entry uboot --image "${OUT}" --serial "${SERIAL}" --relay "${RELAY}" \
  --session-dir k1/logs/burn --ntfy ""
