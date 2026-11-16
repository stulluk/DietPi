#!/bin/sh
# Host side: finish a freshly flashed KICKPI K1A over SSH (eth0), without any manual step.
#  - waits for the DietPi first-run setup to finish (install_stage 2)
#  - enables Bluetooth (DietPi disables it by default)
#  - writes Wi-Fi for both home SSIDs with hashed PSKs (5 GHz preferred) and brings wlan0 up
# The Wi-Fi passphrase comes from $ST_EV_PWD (/etc/secrets) over SSH stdin; it is never written
# to the image, a repo or a log, and only its hash lands on the board.
# Usage: k1-postinstall.sh [host]   (default: 192.168.1.113, the eth0 static lease)
set -eu

HOST="${1:-192.168.1.113}"
# First-run setup swaps Dropbear for OpenSSH, so the host key changes mid-way: do not pin it.
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SSIDS="${K1_SSIDS:-ST-EV-5.0:10 ST-EV-2.4:5}"

[ -n "${ST_EV_PWD:-}" ] || { echo "ERROR: ST_EV_PWD is not set (add it to /etc/secrets)"; exit 1; }

echo "=== waiting for SSH on ${HOST}"
i=0
until ${SSH} "root@${HOST}" true 2>/dev/null; do
  i=$((i + 1)); [ "${i}" -lt 120 ] || { echo "ERROR: no SSH on ${HOST}"; exit 1; }; sleep 5
done
echo "=== waiting for the DietPi first-run setup"
i=0
until [ "$(${SSH} "root@${HOST}" cat /boot/dietpi/.install_stage 2>/dev/null)" = "2" ]; do
  i=$((i + 1)); [ "${i}" -lt 180 ] || { echo "ERROR: first-run setup did not finish"; exit 1; }; sleep 5
done

echo "=== Bluetooth"
${SSH} "root@${HOST}" '/boot/dietpi/func/dietpi-set_hardware bluetooth 1 >/dev/null 2>&1;
  bluetoothctl power on >/dev/null 2>&1 || true; hciconfig hci0 | sed -n 3p'

echo "=== Wi-Fi (${SSIDS})"
# shellcheck disable=SC2016 # expanded on the board
printf '%s\n' "${ST_EV_PWD}" | ${SSH} "root@${HOST}" "SSIDS='${SSIDS}' sh -c '"'
  IFS= read -r P; umask 077
  {
    printf "%s\n" "country=TR" "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev" "update_config=1" ""
    for e in $SSIDS; do
      wpa_passphrase "${e%:*}" "$P" | sed -e "/#psk=/d" -e "s/^}\$/\tscan_ssid=1\n\tpriority=${e#*:}\n}/"
    done
  } > /etc/wpa_supplicant/wpa_supplicant.conf
  unset P
  /boot/dietpi/func/dietpi-set_hardware wifimodules enable >/dev/null 2>&1 || true
  modprobe rtw88_8822cs 2>/dev/null || true
  printf "%s\n" "allow-hotplug wlan0" "iface wlan0 inet dhcp" \
    "wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf" > /etc/network/interfaces.d/wlan0.conf
  sed -i "s/^AUTO_SETUP_NET_WIFI_ENABLED=.*/AUTO_SETUP_NET_WIFI_ENABLED=1/" /boot/dietpi.txt
  nohup sh -c "ifdown wlan0; ifup wlan0" >/root/ifup-wlan0.log 2>&1 &
'"'"
sleep 20
${SSH} "root@${HOST}" 'iw dev wlan0 link | grep -E "SSID|freq|signal"; ip -4 -br addr show wlan0'
echo "=== done"
