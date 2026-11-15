#!/bin/bash
# Build TF-A BL31 + mainline U-Boot for the KICKPI K1A (inside the build container).
# Output: k1/out/u-boot/u-boot-rockchip.bin (write at sector 64) + idbloader/itb.
set -euo pipefail

K1_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=k1/versions.env
. "${K1_DIR}/versions.env"
SRC="${K1_DIR}/work/src"
OUT="${K1_DIR}/out/u-boot"
JOBS="${JOBS:-$(( $(nproc) * 8 / 10 ))}"
export CROSS_COMPILE="aarch64-linux-gnu-"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1794700800}"

# Single, pinned DDR init blob (LPDDR4 1560 MHz, console 1500000 on UART2).
DDR_BLOB="${SRC}/rkbin/bin/rk35/rk3568_ddr_1560MHz_v1.26.bin"

echo "=== TF-A ${TFA_TAG} (rk3568 BL31)"
make -C "${SRC}/tf-a" -j"${JOBS}" PLAT=rk3568 DEBUG=0 bl31
BL31="${SRC}/tf-a/build/rk3568/release/bl31/bl31.elf"

echo "=== U-Boot ${UBOOT_TAG}"
UB_OUT="${K1_DIR}/work/build-u-boot"
mkdir -p "${UB_OUT}"
make -C "${SRC}/u-boot" O="${UB_OUT}" generic-rk3568_defconfig
"${SRC}/u-boot/scripts/kconfig/merge_config.sh" -m -O "${UB_OUT}" "${UB_OUT}/.config" \
  "${K1_DIR}/config/uboot-k1.config"
make -C "${SRC}/u-boot" O="${UB_OUT}" olddefconfig
make -C "${SRC}/u-boot" O="${UB_OUT}" -j"${JOBS}" BL31="${BL31}" ROCKCHIP_TPL="${DDR_BLOB}"

mkdir -p "${OUT}"
cp "${UB_OUT}/u-boot-rockchip.bin" "${UB_OUT}/idbloader.img" "${UB_OUT}/u-boot.itb" \
  "${UB_OUT}/.config" "${OUT}/"
# Rockusb loader for Maskrom recovery (rkdeveloptool db), from rkbin.
cp "${SRC}/rkbin/bin/rk35/rk356x_spl_loader"*.bin "${OUT}/" 2>/dev/null || true
ls -l "${OUT}"
