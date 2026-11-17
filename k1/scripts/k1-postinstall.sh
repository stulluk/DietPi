#!/bin/sh
# Host side: finish a freshly flashed KICKPI K1A over SSH (eth0), without any manual step.
#  - waits for the DietPi first-run setup to finish (install_stage 2)
#  - enables Bluetooth (DietPi disables it by default)
#  - writes Wi-Fi for both home SSIDs with hashed PSKs (5 GHz preferred) and brings wlan0 up
# Wi-Fi names and passphrase come from /etc/secrets (ST_EV_WIFI_SSID_50, ST_EV_WIFI_SSID_24,
# ST_EV_WIFI_PWD; rule sertac_lab_environment). They travel only over SSH stdin, are never written
# to the image, a repo, a log or a command line, and only hashed PSKs land on the board.
# During a Wi-Fi password change, K1_WIFI_INCLUDE_NEXT=1 also adds both SSIDs with
# ST_EV_WIFI_PWD_NEXT at a lower priority, so the board falls back by itself.
# Usage: k1-postinstall.sh [host]   (default: 192.168.1.113, the eth0 static lease)
set -eu

HOST="${1:-192.168.1.113}"
# First-run setup swaps Dropbear for OpenSSH, so the host key changes mid-way: do not pin it.
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Read KEY from the environment, else from /etc/secrets (a session may predate a secrets update).
secret() {
  eval "v=\${$1:-}"
  # shellcheck disable=SC2154 # v is set by eval
  [ -n "${v}" ] || v="$(sed -n "s/^$1=//p" /etc/secrets 2>/dev/null | head -n1)"
  # /etc/secrets may quote values (KEY="value"), like a shell would: strip one pair of quotes.
  case "${v}" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "${v}"
}
SSID50="$(secret ST_EV_WIFI_SSID_50)"
SSID24="$(secret ST_EV_WIFI_SSID_24)"
WPWD="$(secret ST_EV_WIFI_PWD)"
for k in SSID50 SSID24 WPWD; do
  eval "[ -n \"\${${k}}\" ]" || {
    echo "ERROR: ST_EV_WIFI_SSID_50/ST_EV_WIFI_SSID_24/ST_EV_WIFI_PWD missing in /etc/secrets"; exit 1; }
done
WNEXT=""
if [ "${K1_WIFI_INCLUDE_NEXT:-0}" = "1" ]; then
  WNEXT="$(secret ST_EV_WIFI_PWD_NEXT)"
  [ -n "${WNEXT}" ] || { echo "ERROR: K1_WIFI_INCLUDE_NEXT=1 but ST_EV_WIFI_PWD_NEXT is missing"; exit 1; }
fi

# One network per line on stdin: priority<TAB>ssid<TAB>passphrase (never printed).
wifi_lines() {
  printf '10\t%s\t%s\n' "${SSID50}" "${WPWD}"
  printf '5\t%s\t%s\n' "${SSID24}" "${WPWD}"
  if [ -n "${WNEXT}" ] && [ "${WNEXT}" != "${WPWD}" ]; then
    printf '3\t%s\t%s\n' "${SSID50}" "${WNEXT}"
    printf '2\t%s\t%s\n' "${SSID24}" "${WNEXT}"
  fi
}

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
  modprobe hci_uart 2>/dev/null; systemctl restart bluetooth 2>/dev/null;
  for i in 1 2 3 4 5 6 7 8 9 10; do
    bluetoothctl power on >/dev/null 2>&1 || true
    hciconfig hci0 | grep -q "UP RUNNING" && break; sleep 1
  done; hciconfig hci0 | sed -n 3p'

echo "=== Wi-Fi (5 GHz preferred, 2.4 GHz fallback$( [ -n "${WNEXT}" ] && echo ", plus next password"))"
# shellcheck disable=SC2016 # expanded on the board
wifi_lines | ${SSH} "root@${HOST}" '
  umask 077
  tab="$(printf "\t")"
  {
    printf "%s\n" "country=TR" "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev" "update_config=1" ""
    while IFS="${tab}" read -r prio ssid pass; do
      [ -n "${ssid}" ] || continue
      wpa_passphrase "${ssid}" "${pass}" | sed -e "/#psk=/d" \
        -e "s/^}\$/\tscan_ssid=1\n\tpriority=${prio}\n}/"
    done
  } > /etc/wpa_supplicant/wpa_supplicant.conf
  echo "networks written: $(grep -c "^network=" /etc/wpa_supplicant/wpa_supplicant.conf)"
  grep -q "^[[:space:]]*psk=\"" /etc/wpa_supplicant/wpa_supplicant.conf && echo "WARNING: plaintext psk"
  /boot/dietpi/func/dietpi-set_hardware wifimodules enable >/dev/null 2>&1 || true
  modprobe rtw88_8822cs 2>/dev/null || true
  printf "%s\n" "allow-hotplug wlan0" "iface wlan0 inet dhcp" \
    "wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf" > /etc/network/interfaces.d/wlan0.conf
  sed -i "s/^AUTO_SETUP_NET_WIFI_ENABLED=.*/AUTO_SETUP_NET_WIFI_ENABLED=1/" /boot/dietpi.txt
  sync
  nohup sh -c "ifdown wlan0; ifup wlan0" >/root/ifup-wlan0.log 2>&1 </dev/null &
'
sleep 20
${SSH} "root@${HOST}" 'iw dev wlan0 link | grep -E "SSID|freq|signal"; ip -4 -br addr show wlan0'
${SSH} "root@${HOST}" sync # new files must survive a sudden power cut (ext4 delayed allocation)
echo "=== done"
