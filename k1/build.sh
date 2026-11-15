#!/bin/bash
# In-container build driver for the KICKPI K1A DietPi image.
# Usage (inside the container, via ../indockerbuild.sh): k1/build.sh <fetch|kernel|uboot|image|all>
set -euo pipefail

K1_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=k1/versions.env
. "${K1_DIR}/versions.env"

WORK="${K1_DIR}/work"
DL="${WORK}/dl"
SRC="${WORK}/src"
OUT="${K1_DIR}/out"
JOBS="${JOBS:-$(( $(nproc) * 8 / 10 ))}"
CROSS="aarch64-linux-gnu-"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1794700800}" # 2026-11-15 00:00 UTC
export KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH}"
export KBUILD_BUILD_USER="k1" KBUILD_BUILD_HOST="dietpi-build"

git config --global --add safe.directory "*"

log() { printf '\n=== [%s] %s\n' "$(date +%T)" "$*"; }

# Clone a git tag shallowly and verify that it resolves to the pinned commit.
git_fetch() {
  local name="$1" url="$2" tag="$3" commit="$4" dir="${SRC}/$1"
  if [[ ! -d ${dir}/.git ]]; then
    log "Cloning ${name} ${tag}"
    git clone -q --depth 1 --branch "${tag}" "${url}" "${dir}" 2>/dev/null \
      || { rm -rf "${dir}"; git init -q "${dir}"; git -C "${dir}" fetch -q --depth 1 "${url}" "${commit}";
           git -C "${dir}" checkout -q FETCH_HEAD; }
  fi
  local head
  head="$(git -C "${dir}" rev-parse HEAD)"
  [[ ${head} == "${commit}" ]] || { echo "ERROR: ${name} is ${head}, expected ${commit}"; exit 1; }
}

stage_fetch() {
  mkdir -p "${DL}" "${SRC}"
  local tarball="${DL}/linux-${LINUX_VERSION}.tar.xz"
  if [[ ! -f ${tarball} ]]; then
    log "Downloading Linux ${LINUX_VERSION}"
    curl -fL --retry 3 -o "${tarball}.part" "${LINUX_URL}"
    mv "${tarball}.part" "${tarball}"
  fi
  if [[ -n ${LINUX_SHA256:-} ]]; then
    echo "${LINUX_SHA256}  ${tarball}" | sha256sum -c -
  else
    echo "WARNING: LINUX_SHA256 not pinned yet: $(sha256sum "${tarball}" | cut -d' ' -f1)"
  fi
  if [[ ! -d ${SRC}/linux-${LINUX_VERSION} ]]; then
    log "Extracting Linux"
    tar -C "${SRC}" -xf "${tarball}"
  fi
  git_fetch u-boot "${UBOOT_URL}" "${UBOOT_TAG}" "${UBOOT_COMMIT}"
  git_fetch tf-a "${TFA_URL}" "${TFA_TAG}" "${TFA_COMMIT}"
  if [[ ! -d ${SRC}/rkbin/.git ]]; then
    log "Fetching rkbin ${RKBIN_COMMIT}"
    git init -q "${SRC}/rkbin"
    git -C "${SRC}/rkbin" fetch -q --depth 1 "${RKBIN_URL}" "${RKBIN_COMMIT}"
    git -C "${SRC}/rkbin" checkout -q FETCH_HEAD
  fi
  log "Firmware ${FIRMWARE_TAG}"
  local entry path sum
  for entry in ${FIRMWARE_FILES}; do
    path="${entry%%=*}" sum="${entry#*=}"
    mkdir -p "${OUT}/firmware/$(dirname "${path}")"
    [[ -f ${OUT}/firmware/${path} ]] \
      || curl -fsSL --retry 3 -o "${OUT}/firmware/${path}" "${FIRMWARE_URL}/${path}?h=${FIRMWARE_TAG}"
    echo "${sum}  ${OUT}/firmware/${path}" | sha256sum -c -
  done
}

stage_kernel() {
  local ksrc="${SRC}/linux-${LINUX_VERSION}" kout="${WORK}/build-linux"
  log "Kernel ${LINUX_VERSION}${LINUX_LOCALVERSION}: DTS + config"
  cp "${K1_DIR}/dts/rk3568-kickpi-k1a.dts" "${ksrc}/arch/arm64/boot/dts/rockchip/"
  local mk="${ksrc}/arch/arm64/boot/dts/rockchip/Makefile"
  grep -q 'rk3568-kickpi-k1a.dtb' "${mk}" \
    || echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += rk3568-kickpi-k1a.dtb" >> "${mk}"
  # Make sure the dtb target really landed.
  grep -q 'rk3568-kickpi-k1a.dtb' "${ksrc}/arch/arm64/boot/dts/rockchip/Makefile"
  mkdir -p "${kout}"
  make -C "${ksrc}" O="${kout}" ARCH=arm64 CROSS_COMPILE="${CROSS}" defconfig
  "${ksrc}/scripts/kconfig/merge_config.sh" -m -O "${kout}" "${kout}/.config" \
    "${K1_DIR}/config/kernel-k1.config"
  make -C "${ksrc}" O="${kout}" ARCH=arm64 CROSS_COMPILE="${CROSS}" olddefconfig
  # Report fragment options that did not survive olddefconfig (missing deps / renamed).
  log "Fragment options not applied"
  while IFS= read -r line; do
    case "${line}" in CONFIG_*=*) ;; *) continue ;; esac
    local key="${line%%=*}" val="${line#*=}"
    if [[ ${val} == n ]]; then
      grep -q "^${key}=" "${kout}/.config" && echo "  ${key} wanted n, got $(grep "^${key}=" "${kout}/.config")"
    else
      grep -qx "${line}" "${kout}/.config" || echo "  ${line} -> $(grep "^${key}=" "${kout}/.config" || echo unset)"
    fi
  done < "${K1_DIR}/config/kernel-k1.config"
  log "Kernel build (-j${JOBS})"
  make -C "${ksrc}" O="${kout}" ARCH=arm64 CROSS_COMPILE="${CROSS}" \
    LOCALVERSION="${LINUX_LOCALVERSION}" KDEB_PKGVERSION="${LINUX_VERSION}-1" \
    KDEB_CHANGELOG_DIST="${DEBIAN_SUITE}" DPKG_FLAGS=-d \
    DEB_BUILD_PROFILES="pkg.linux-upstream.nokernelheaders pkg.linux-upstream.nokerneldbg" \
    -j"${JOBS}" bindeb-pkg
  mkdir -p "${OUT}/debs"
  mv -f "${WORK}"/linux-*"${LINUX_VERSION}${LINUX_LOCALVERSION}"*.deb "${OUT}/debs/" 2>/dev/null || true
  mv -f "${WORK}"/linux-upstream_* "${WORK}"/linux-*.buildinfo "${WORK}"/linux-*.changes "${OUT}/debs/" 2>/dev/null || true
  cp "${kout}/arch/arm64/boot/dts/rockchip/rk3568-kickpi-k1a.dtb" "${OUT}/"
  cp "${kout}/.config" "${OUT}/kernel.config"
  ls -l "${OUT}/debs"
}

stage_uboot() {
  "${K1_DIR}/scripts/build-uboot.sh"
}

stage_image() {
  "${K1_DIR}/scripts/build-image.sh"
}

fix_owner() {
  [[ -n ${HOST_UID:-} ]] && chown -R "${HOST_UID}:${HOST_GID:-${HOST_UID}}" "${WORK}" "${OUT}" 2>/dev/null || true
}
trap fix_owner EXIT

case "${1:-all}" in
  fetch) stage_fetch ;;
  kernel) stage_fetch; stage_kernel ;;
  uboot) stage_fetch; stage_uboot ;;
  image) stage_image ;;
  all) stage_fetch; stage_kernel; stage_uboot; stage_image ;;
  *) echo "Usage: $0 <fetch|kernel|uboot|image|all>"; exit 1 ;;
esac
log "Stage ${1:-all} done"
