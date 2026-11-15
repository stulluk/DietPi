#!/bin/bash
# Make a per-board copy of the built image with first-boot settings in dietpi.txt.
# Runs inside the privileged build container (loop mounts).
# Usage: provision-image.sh <in.img> <out.img> <hostname> <ssh-pubkey-file>
# No Wi-Fi credentials are ever written here: Wi-Fi is configured on the board after boot.
set -euo pipefail

IN="$1" OUTIMG="$2" HOSTNAME_K1="$3" PUBKEY_FILE="$4"
[[ -f ${IN} && -f ${PUBKEY_FILE} ]] || { echo "Usage: $0 <in.img> <out.img> <hostname> <pubkey>"; exit 1; }

cp --reflink=auto "${IN}" "${OUTIMG}"
LOOP="$(losetup -fP --show "${OUTIMG}")"
MNT="$(mktemp -d)"
cleanup() {
  umount -R "${MNT}" 2>/dev/null || true
  losetup -d "${LOOP}" 2>/dev/null || true
  rmdir "${MNT}" 2>/dev/null || true
}
trap cleanup EXIT

# Set KEY=value in a dietpi.txt (replace an active or commented line, else append).
set_key() {
  local file="$1" key="$2" val="$3"
  if grep -qE "^#?${key}=" "${file}"; then
    sed -i -E "0,/^#?${key}=.*/s|^#?${key}=.*|${key}=${val//|/\\|}|" "${file}"
  else
    echo "${key}=${val}" >> "${file}"
  fi
}

PUBKEY="$(head -n1 "${PUBKEY_FILE}")"
edited=0
for part in "${LOOP}"p*; do
  mount "${part}" "${MNT}"
  for f in "${MNT}/dietpi.txt" "${MNT}/boot/dietpi.txt"; do
    [[ -f ${f} ]] || continue
    set_key "${f}" AUTO_SETUP_AUTOMATED 1
    set_key "${f}" AUTO_SETUP_NET_HOSTNAME "${HOSTNAME_K1}"
    set_key "${f}" AUTO_SETUP_NET_ETHERNET_ENABLED 1
    set_key "${f}" AUTO_SETUP_NET_WIFI_ENABLED 1
    set_key "${f}" AUTO_SETUP_TIMEZONE Europe/Istanbul
    set_key "${f}" AUTO_SETUP_SSH_PUBKEY "${PUBKEY}"
    set_key "${f}" SURVEY_OPTED_IN 0
    set_key "${f}" CONFIG_SERIAL_CONSOLE_ENABLE 1
    set_key "${f}" AUTO_SETUP_SSH_SERVER_INDEX -2
    echo "provisioned ${f#"${MNT}"} on ${part}"
    edited=$((edited + 1))
  done
  umount "${MNT}"
done
(( edited > 0 )) || { echo "ERROR: no dietpi.txt found in ${OUTIMG}"; exit 1; }
sync
