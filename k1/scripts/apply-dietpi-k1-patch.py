#!/usr/bin/env python3
"""One-shot helper that adds KICKPI K1A (hardware ID 120) support to the DietPi scripts.

Every replacement must match exactly once, so the helper fails loudly when upstream changes.
It is kept in the repo to document the change set; the result is committed to the fork.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def patch(rel: str, old: str, new: str) -> None:
  """Replace exactly one occurrence of old with new in ROOT/rel."""
  path = ROOT / rel
  text = path.read_text()
  if new in text:
    print(f"skip (already applied): {rel}: {new.splitlines()[0][:60]}")
    return
  count = text.count(old)
  if count != 1:
    sys.exit(f"ERROR: {rel}: expected 1 match, got {count}: {old[:80]!r}")
  path.write_text(text.replace(old, new))
  print(f"patched: {rel}: {old.splitlines()[0][:60]}")


BUILD = ".build/images/dietpi-build"
INSTALLER = ".build/images/dietpi-installer"

# --- dietpi-build ---------------------------------------------------------------------------
patch(
  BUILD,
  "\t110) iname='OrangePi6' HW_ARCH=3 PTTYPE='gpt' efi_size=64 root_size='cixp1';;\n",
  "\t110) iname='OrangePi6' HW_ARCH=3 PTTYPE='gpt' efi_size=64 root_size='cixp1';;\n"
  "\t120) iname='KickPiK1A' HW_ARCH=3 PTTYPE='gpt' partition_start=16 root_size='rockchip64';;\n",
)
# Register QEMU binfmt without a running systemd (e.g. inside a privileged Docker container).
patch(
  BUILD,
  "(( $emulation )) && G_EXEC systemctl restart systemd-binfmt\n",
  "if (( $emulation ))\n"
  "then\n"
  "\tif [[ -d '/run/systemd/system' ]]\n"
  "\tthen\n"
  "\t\tG_EXEC systemctl restart systemd-binfmt\n"
  "\telse\n"
  "\t\tfindmnt /proc/sys/fs/binfmt_misc > /dev/null || G_EXEC mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc\n"
  "\t\tG_EXEC /usr/lib/systemd/systemd-binfmt\n"
  "\tfi\n"
  "fi\n",
)
# KICKPI K1A: bind the locally built kernel/U-Boot/firmware into the build container.
patch(
  BUILD,
  "\tfor i in \"${FP_LOOP}p\"*; do abind+=(\"--bind=$i\"); done\n",
  "\tfor i in \"${FP_LOOP}p\"*; do abind+=(\"--bind=$i\"); done\n"
  "\t# KICKPI K1A: kernel, U-Boot and firmware built by k1/build.sh\n"
  "\t[[ $HW_MODEL == 120 ]] && { [[ -d $K1_ARTIFACTS ]] || Error_Exit 'K1_ARTIFACTS directory missing'; abind+=(\"--bind-ro=$K1_ARTIFACTS:/mnt/k1\"); }\n",
)

# systemd-nspawn without a host systemd/D-Bus (Docker): do not register with systemd-machined.
patch(
  BUILD,
  "systemd-nspawn -bD rootfs \"${abind[@]}\" ||",
  "[[ -d '/run/systemd/system' ]] || abind+=('--register=no' '--keep-unit')\n"
  "systemd-nspawn -bD rootfs \"${abind[@]}\" ||",
)

# Keep the raw image when the caller asks for it (--skip-archive output, used by k1/build-image.sh).
patch(
  BUILD,
  "\t[[ -f $OUTPUT_IMG_NAME.img ]] && G_EXEC rm \"$OUTPUT_IMG_NAME.img\"\n",
  "\t[[ -f $OUTPUT_IMG_NAME.img && ${KEEP_IMAGE:-0} != 1 ]] && G_EXEC rm \"$OUTPUT_IMG_NAME.img\"\n",
)

# --- dietpi-installer -----------------------------------------------------------------------
patch(
  INSTALLER,
  "\t\t\t\t\t\t'109' ': LubanCat 4'\n",
  "\t\t\t\t\t\t'109' ': LubanCat 4'\n\t\t\t\t\t\t'120' ': KICKPI K1A'\n",
)
patch(
  INSTALLER,
  "\t\tlocal armbian_packages=0\n",
  "\t\tlocal armbian_packages=0 k1_packages=0\n",
)
patch(
  INSTALLER,
  "|105|106|107|108|109)$ ]]\n\t\tthen\n\t\t\t# Amlogic 64-bit\n\t\t\tarmbian_packages=1\n",
  "|105|106|107|108|109|120)$ ]]\n\t\tthen\n\t\t\t# Amlogic 64-bit\n\t\t\tarmbian_packages=1\n"
  "\t\t\t# KICKPI K1A: locally built kernel/U-Boot instead of Armbian packages\n"
  "\t\t\t(( $G_HW_MODEL == 120 )) && armbian_packages=0 k1_packages=1\n",
)
patch(
  INSTALLER,
  "|100|101|102|103|104|105|106|109)$ ]]\n\t\t\tthen\n\t\t\t\t# Load addresses\n",
  "|100|101|102|103|104|105|106|109|120)$ ]]\n\t\t\tthen\n\t\t\t\t# Load addresses\n",
)
patch(
  INSTALLER,
  "\t\t\t\t\t77) G_CONFIG_INJECT 'fdtfile=' 'fdtfile=rockchip/rk3568-rock-3a.dtb' /boot/dietpiEnv.txt;;\n",
  "\t\t\t\t\t77) G_CONFIG_INJECT 'fdtfile=' 'fdtfile=rockchip/rk3568-rock-3a.dtb' /boot/dietpiEnv.txt;;\n"
  "\t\t\t\t\t120) G_CONFIG_INJECT 'fdtfile=' 'fdtfile=rockchip/rk3568-kickpi-k1a.dtb' /boot/dietpiEnv.txt;;\n",
)
patch(
  INSTALLER,
  "\t\t\t\t\t77) G_CONFIG_INJECT 'overlay_prefix=' 'overlay_prefix=rockchip-rk3568-rock-3a rockchip-rk3568-hk rockchip-rk3566' /boot/dietpiEnv.txt;;\n",
  "\t\t\t\t\t77) G_CONFIG_INJECT 'overlay_prefix=' 'overlay_prefix=rockchip-rk3568-rock-3a rockchip-rk3568-hk rockchip-rk3566' /boot/dietpiEnv.txt;;\n"
  "\t\t\t\t\t120) G_CONFIG_INJECT 'overlay_prefix=' 'overlay_prefix=rockchip-rk3568 rockchip-rk3566' /boot/dietpiEnv.txt;;\n",
)
# K1A boots without initramfs (all boot-critical drivers are built in): make initrd optional.
patch(
  INSTALLER,
  "\t\t\t\t\t*) G_EXEC sed --follow-symlinks -i 's/ttyAML0,115200/ttyS2,1500000/' /boot/dietpiEnv.txt;; # mainline\n"
  "\t\t\t\tesac\n",
  "\t\t\t\t\t*) G_EXEC sed --follow-symlinks -i 's/ttyAML0,115200/ttyS2,1500000/' /boot/dietpiEnv.txt;; # mainline\n"
  "\t\t\t\tesac\n"
  "\t\t\t\t# KICKPI K1A: no initramfs, so boot without one unless it exists\n"
  "\t\t\t\tif (( $G_HW_MODEL == 120 ))\n"
  "\t\t\t\tthen\n"
  "\t\t\t\t\tG_EXEC sed --follow-symlinks -i '/initrd.img\"$/d' /boot/boot.cmd\n"
  "\t\t\t\t\t# shellcheck disable=SC2016\n"
  "\t\t\t\t\tG_EXEC sed --follow-symlinks -i '/^booti /c\\\n"
  "if load \"${devtype}\" \"${devnum}\" \"${ramdisk_addr_r}\" \"${prefix}initrd.img\"; then\\\n"
  "\\tbooti \"${kernel_addr_r}\" \"${ramdisk_addr_r}:${filesize}\" \"${fdt_addr_r}\"\\\n"
  "else\\\n"
  "\\tbooti \"${kernel_addr_r}\" - \"${fdt_addr_r}\"\\\n"
  "fi' /boot/boot.cmd\n"
  "\t\t\t\tfi\n",
)
patch(
  INSTALLER,
  "\t\t# DietPi-Build with Armbian kernel/bootloader/firmware\n\t\telif (( $armbian_packages ))\n",
  "\t\t# KICKPI K1A: kernel, U-Boot and Wi-Fi/BT firmware from k1/build.sh, bind-mounted at /mnt/k1\n"
  "\t\telif (( $k1_packages ))\n"
  "\t\tthen\n"
  "\t\t\t[[ -d '/mnt/k1/debs' ]] || { G_DIETPI-NOTIFY 1 'KICKPI K1A artifacts missing in /mnt/k1, aborting ...'; exit 1; }\n"
  "\t\t\tG_AGI u-boot-tools\n"
  "\t\t\tG_EXEC mkdir -p /etc/kernel/post{inst,rm}.d /usr/lib/u-boot-kickpi-k1a\n"
  "\t\t\tG_EXEC cp /mnt/k1/rootfs/etc/kernel/postinst.d/zz-dietpi-k1a /etc/kernel/postinst.d/zz-dietpi-k1a\n"
  "\t\t\tG_EXEC chmod +x /etc/kernel/postinst.d/zz-dietpi-k1a\n"
  "\t\t\tG_EXEC_OUTPUT=1 G_EXEC dpkg -i /mnt/k1/debs/linux-image-*.deb\n"
  "\t\t\tG_EXEC cp -a /mnt/k1/firmware/. /usr/lib/firmware/\n"
  "\t\t\tG_EXEC cp -a /mnt/k1/rootfs/. /\n"
  "\t\t\tG_EXEC cp /mnt/k1/u-boot/u-boot-rockchip.bin /usr/lib/u-boot-kickpi-k1a/\n"
  "\t\t\t# STB live-debug tooling and Bluetooth stack\n"
  "\t\t\tG_AGI adb picocom minicom tmux ser2net bluez\n"
  "\t\t\tG_EXEC mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr\n"
  "\t\t\tG_EXEC dd if=/usr/lib/u-boot-kickpi-k1a/u-boot-rockchip.bin of=\"$BOOT_DEVICE\" bs=512 seek=64 conv=notrunc,fsync\n"
  "\t\t\tG_EXEC rm -f /boot/uImage /boot/uInitrd* /boot/armbianEnv.txt /boot/uEnv.txt\n"
  "\n"
  "\t\t# DietPi-Build with Armbian kernel/bootloader/firmware\n"
  "\t\telif (( $armbian_packages ))\n",
)

# --- hardware model name, serial console ------------------------------------------------------
patch(
  "dietpi/func/dietpi-obtain_hw_model",
  "\t\t\t\t110) G_HW_MODEL_NAME='Orange Pi 6';;\n",
  "\t\t\t\t120) G_HW_MODEL_NAME='KICKPI K1A' G_HW_CPUID=10;;\n"
  "\t\t\t\t110) G_HW_MODEL_NAME='Orange Pi 6';;\n",
)
patch(
  "dietpi/func/dietpi-set_hardware",
  "|91|92|93|94|95|100|101|105|106|109)$ && $INPUT_ADDITIONAL =~ ^('ttyS2'|'ttyFIQ0')$ ]]",
  "|91|92|93|94|95|100|101|105|106|109|120)$ && $INPUT_ADDITIONAL =~ ^('ttyS2'|'ttyFIQ0')$ ]]",
)
print("done")
