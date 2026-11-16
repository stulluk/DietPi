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

## Flash (fully automatic)
```sh
./flash.sh            # provision + flash + post-install, no buttons
```
1. `k1/scripts/provision-image.sh` (in Docker) makes `k1/out/kickpi-k1.img`, a copy with
   first-boot settings: hostname, host SSH key, OpenSSH, automated setup, Wi-Fi off.
2. `rk-burn-tool.py --mode raw` writes it from LBA 0. The entry path depends on the board:
   - Linux reachable on eth0 (`192.168.1.113`): SSH erases the loader and reboots, and the BootROM
     enters Maskrom. Then `db rk356x_loader_*.bin` and `wl 0` run at about 21 MiB/s (`--entry ssh`).
   - Otherwise: relay power cycle, Ctrl-C at U-Boot (`bootdelay=1`), `mmc erase` of the loader,
     `reset`, and Maskrom as above (`--entry uboot`). The mainline U-Boot `rockusb` also works,
     but at about 1 MiB/s.
   - Stage 3 checks U-Boot, kernel, systemd and the login prompt on `/dev/serial-ws2`.
3. `k1/scripts/k1-postinstall.sh` waits for the DietPi first run. It then enables Bluetooth and
   writes Wi-Fi for `ST-EV-5.0` (priority) and `ST-EV-2.4`. The passphrase comes from `ST_EV_PWD`
   over SSH stdin, and only hashed PSKs are stored on the board.

## Tests
- `k1/scripts/k1-soak-test.sh N` alternates soft reboots and cold relay power cycles. Each
  iteration records SSH time (Wi-Fi/eth), SSID/dBm, Bluetooth, USB, failed units, boot time and
  kernel errors into a CSV.
- `k1/scripts/wifi-test.sh SSID` runs on the board: it associates with one SSID and reports link,
  signal and DHCP.

## Boot layout
- Sector 64: `u-boot-rockchip.bin` (TPL/SPL + U-Boot FIT with BL31).
- GPT: ext4 root from 16 MiB, then a small FAT partition with `dietpi.txt`.
- `/boot/boot.scr` (DietPi `boot.cmd`): it loads `/boot/Image` and
  `/boot/dtb/rockchip/rk3568-kickpi-k1a.dtb` and boots without an initramfs. The kernel hook
  `/etc/kernel/postinst.d/zz-dietpi-k1a` refreshes both on every kernel install.
