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

LOADER="$(find k1/out/u-boot -name "rk356x_loader_*.bin" | head -n1)"
ETH_IP="${K1_ETH_IP:-192.168.1.113}"
RUN=""
[ -x "$(command -v "${BURN}" || echo "${BURN}")" ] || RUN="python3"
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
     -o UserKnownHostsFile=/dev/null "root@${ETH_IP}" true 2>/dev/null; then
  echo "=== Flashing ${OUT}: Linux is up, Maskrom via SSH loader erase (${ETH_IP})"
  ENTRY="--entry ssh --ssh-target root@${ETH_IP} --miniloader ${LOADER}"
else
  echo "=== Flashing ${OUT}: U-Boot rockusb (relay ${RELAY}, console ${SERIAL})"
  ENTRY="--entry uboot --relay ${RELAY} --miniloader ${LOADER}"
fi
# shellcheck disable=SC2086 # ENTRY is a list of options
${RUN} "${BURN}" --mode raw ${ENTRY} --image "${OUT}" --serial "${SERIAL}" \
  --session-dir k1/logs/burn --ntfy ""

echo "=== Post-install over SSH (Bluetooth, Wi-Fi)"
k1/scripts/k1-postinstall.sh "${ETH_IP}"
