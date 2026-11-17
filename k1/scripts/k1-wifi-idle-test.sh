#!/bin/bash
# Host side: long idle Wi-Fi test for the KICKPI K1A. Reboots the board, then once a minute pings
# its Wi-Fi address and reads rtw88 "tx report" failures over eth0. One line per minute.
# Usage: k1-wifi-idle-test.sh [minutes] [--no-reboot]
set -u
MIN="${1:-45}"
WLAN_IP="${K1_WLAN_IP:-192.168.1.112}"
ETH_IP="${K1_ETH_IP:-192.168.1.113}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no
     -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

if [[ ${2:-} != --no-reboot ]]; then
  timeout 10 "${SSH[@]}" "root@${ETH_IP}" 'systemctl reboot' 2>/dev/null; sleep 10
fi
t0=$(date +%s)
until timeout 6 "${SSH[@]}" "root@${WLAN_IP}" true 2>/dev/null; do
  (( $(date +%s) - t0 > 180 )) && { log "no SSH over Wi-Fi after 180 s"; exit 1; }
  sleep 3
done
# shellcheck disable=SC2016 # expanded on the board
log "up: $(timeout 15 "${SSH[@]}" "root@${ETH_IP}" 'echo lps_deep_disabled=$(cat /sys/module/rtw88_core/parameters/disable_lps_deep) $(iw dev wlan0 get power_save)')"
down=0
for m in $(seq 1 "${MIN}"); do
  sleep 60
  if ping -c3 -W2 -q "${WLAN_IP}" >/dev/null 2>&1; then wl=OK; down=0; else wl=FAIL; down=$((down + 1)); fi
  # shellcheck disable=SC2016 # expanded on the board
  st="$(timeout 15 "${SSH[@]}" "root@${ETH_IP}" 'echo "txfail=$(dmesg | grep -c "failed to get tx report")" \
    "signal=$(iw dev wlan0 link | sed -n "s/.*signal: \([-0-9]*\).*/\1/p")" \
    "ip=$(ip -4 -br addr show wlan0 | awk "{print \$3}")" "up=$(cut -d. -f1 /proc/uptime)s"')"
  log "min ${m}/${MIN}: wlan=${wl} ${st:-eth0 probe failed}"
  (( down >= 3 )) && { log "Wi-Fi down for 3 minutes in a row, stopping"; exit 2; }
done
log "idle test done: Wi-Fi stayed up for ${MIN} min"
