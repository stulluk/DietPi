#!/bin/sh
# Runs ON the K1: connect wlan0 to one SSID, report link/signal/DHCP/ping, then disconnect.
# Usage: wifi-test.sh <ssid> [seconds]   (passphrase is read from stdin, never printed)
# The temporary config lives in /run (tmpfs) and is removed on exit.
set -eu

SSID="$1"
WAIT="${2:-40}"
CONF="/run/k1-wifi-test.conf"
IFACE="wlan0"

cleanup() {
  wpa_cli -i "${IFACE}" terminate >/dev/null 2>&1 || true
  dhclient -r "${IFACE}" >/dev/null 2>&1 || true
  rm -f "${CONF}"
}
trap cleanup EXIT

IFS= read -r PASS
umask 077
{
  echo "ctrl_interface=/run/wpa_supplicant"
  echo "country=TR"
  wpa_passphrase "${SSID}" "${PASS}" | sed -e '/#psk=/d' -e 's/^}$/\tscan_ssid=1\n}/'
} > "${CONF}"
unset PASS

pkill -f "wpa_supplicant.*${IFACE}" 2>/dev/null || true
ip link set "${IFACE}" up
wpa_supplicant -B -i "${IFACE}" -c "${CONF}" >/dev/null

i=0
state=""
while [ "${i}" -lt "${WAIT}" ]; do
  state="$(wpa_cli -i "${IFACE}" status 2>/dev/null | sed -n 's/^wpa_state=//p')"
  [ "${state}" = "COMPLETED" ] && break
  sleep 1
  i=$((i + 1))
done
echo "SSID=${SSID} wpa_state=${state} after ${i}s"
[ "${state}" = "COMPLETED" ] || exit 1

iw dev "${IFACE}" link | grep -E "Connected|freq|signal|tx bitrate|rx bitrate"
dhclient -1 -4 "${IFACE}" >/dev/null 2>&1 || true
ip -4 -br addr show "${IFACE}"
GW="$(ip -4 route show dev "${IFACE}" default | awk '{print $3; exit}')"
[ -n "${GW}" ] && ping -c 5 -q -I "${IFACE}" "${GW}" | tail -2
i=0
while [ "${i}" -lt 5 ]; do
  iw dev "${IFACE}" station dump | sed -n 's/^[[:space:]]*signal avg:[[:space:]]*/signal_avg=/p'
  sleep 1
  i=$((i + 1))
done
