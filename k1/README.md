# KICKPI K1A support (fork branch `kickpi-k1`)

This directory builds a reproducible DietPi (Debian 13 trixie) image for the KICKPI K1A
(Rockchip RK3568B2). DietPi uses hardware ID `120`. Everything is built in Docker.

## Inputs (pinned in `versions.env`)
- Linux 6.18 LTS tarball (sha256) with `dts/rk3568-kickpi-k1a.dts`. The DTS is based on
  [j3ffs/Kickpi-K1](https://github.com/j3ffs/Kickpi-K1) and fixed for the K1A: WLAN enable on
  gpio3 PD5, GMAC delays from the vendor BSP, and stable MACs from U-Boot.
- Kernel config: arm64 `defconfig` + `config/kernel-k1.config`. It is Rockchip-only and has no
  initramfs. RTL8822CS Wi-Fi/BT, every USB-serial driver, and HDMI/GPU are enabled.
- Mainline U-Boot (`generic-rk3568_defconfig` + `config/uboot-k1.config`): `bootdelay=0`,
  Rockusb, MAC from CPU id. BL31 comes from mainline TF-A. Only the DDR init blob comes from rkbin.
- RTL8822CS firmware from linux-firmware (sha256 per file).
- DietPi installer from this fork branch (`.build/images/dietpi-{build,installer}`, model 120).

## Build
```sh
./dockerbuild.sh            # build environment image
./indockerbuild.sh kernel   # -> k1/out/debs/linux-image-*-k1_*.deb
./indockerbuild.sh uboot    # -> k1/out/u-boot/u-boot-rockchip.bin
./indockerbuild.sh image    # -> k1/out/DietPi_KickPiK1A-ARMv8-Trixie.img (privileged)
./indockerbuild.sh all      # all of the above
./entercontainer.sh         # interactive shell in the build environment
```
Optional second argument: number of make jobs (default 80% of the host cores).

The image stage needs a temporary qemu-aarch64 binfmt registration, which it does inside the
privileged container. `dietpi-build` fetches the installer from `stulluk/DietPi@kickpi-k1`,
so push local changes there before you run the image stage.

## Flash
The image goes to eMMC over the USB-C OTG port with `rk-burn-tool.py`. The tool power-cycles
the relay, stops U-Boot, runs `rockusb 0 mmc 0`, writes the raw image and checks the boot
on the UART. See the project README one level up.

## Boot layout
- Sector 64: `u-boot-rockchip.bin` (TPL/SPL + U-Boot FIT with BL31).
- GPT: ext4 root from 16 MiB, then a small FAT partition with `dietpi.txt`.
- `/boot/boot.scr` (DietPi `boot.cmd`): it loads `/boot/Image` and
  `/boot/dtb/rockchip/rk3568-kickpi-k1a.dtb` and boots without an initramfs. The kernel hook
  `/etc/kernel/postinst.d/zz-dietpi-k1a` refreshes both on every kernel install.
