#!/bin/bash
# Build the DietPi image for the KICKPI K1A with dietpi-build (inside the privileged container).
# Needs: k1/out/debs (kernel), k1/out/u-boot, k1/out/firmware from the earlier stages, and the
# DietPi branch ${DIETPI_OWNER}/${DIETPI_BRANCH} pushed to GitHub (dietpi-build fetches from it).
set -euo pipefail

K1_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${K1_DIR}/.." && pwd)"
# shellcheck source=k1/versions.env
. "${K1_DIR}/versions.env"
OUT="${K1_DIR}/out"
IMG_WORK="${K1_DIR}/work/image"

for d in debs u-boot firmware; do
  [[ -d ${OUT}/${d} ]] || { echo "ERROR: ${OUT}/${d} missing, run the kernel/uboot stages first"; exit 1; }
done
rm -rf "${OUT}/rootfs"
cp -a "${K1_DIR}/rootfs" "${OUT}/rootfs"

mkdir -p "${IMG_WORK}"
cd "${IMG_WORK}"
# Clean leftovers of an interrupted run: mounts, loop devices and the rootfs dir.
if [[ -d rootfs ]]; then
  umount -R rootfs 2>/dev/null || true
  rmdir rootfs
fi
for loop in $(losetup -j "${IMG_WORK}/DietPi_KickPiK1A-ARMv8-Trixie.img" -O NAME -n 2>/dev/null); do
  losetup -d "${loop}" || true
done
rm -f DietPi_KickPiK1A-*.img .#rootfs.lck

export G_GITOWNER="${DIETPI_OWNER}" G_GITBRANCH="${DIETPI_BRANCH}" K1_ARTIFACTS="${OUT}" KEEP_IMAGE=1
bash "${REPO}/.build/images/dietpi-build" -m 120 -d 8 -o "${DIETPI_OWNER}" -b "${DIETPI_BRANCH}" \
  --skip-archive

img="$(ls DietPi_KickPiK1A-*.img)"
mv -f "${img}" "${OUT}/${img}"
sha256sum "${OUT}/${img}" | tee "${OUT}/${img}.sha256"
