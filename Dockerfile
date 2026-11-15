# Build environment for the KICKPI K1A DietPi image (kernel, U-Boot, TF-A, rootfs).
ARG BASE_IMAGE=debian:trixie-slim
FROM ${BASE_IMAGE}

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      bc bison build-essential ca-certificates cpio curl debhelper-compat device-tree-compiler \
      dosfstools dpkg-dev dwarves e2fsprogs fakeroot flex gcc-aarch64-linux-gnu git gnupg \
      kmod libelf-dev libgnutls28-dev libssl-dev mmdebstrap parted python3 python3-dev \
      python3-pyelftools python3-setuptools qemu-user-binfmt rsync swig systemd-container \
      udev uuid-dev xz-utils zstd debian-archive-keyring locales sudo whiptail procps \
      iproute2 file \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g "${GID}" builder 2>/dev/null || true \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash builder \
    && echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder

WORKDIR /work
