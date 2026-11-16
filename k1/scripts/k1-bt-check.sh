#!/bin/bash
# Host side: reboot the K1A until Bluetooth does not come up, then stop and keep the board as it is.
# Prints one line per boot. Usage: k1-bt-check.sh [max_iterations]
set -u
MAX="${1:-20}"
ETH_IP="${K1_ETH_IP:-192.168.1.113}"
RELAY="${K1_RELAY:-tasmota-11.lan}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no
     -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

for i in $(seq 1 "${MAX}"); do
  if (( i % 2 )); then
    curl -s -m 5 "http://${RELAY}/cm?cmnd=Power%20OFF" >/dev/null; sleep 5
    curl -s -m 5 "http://${RELAY}/cm?cmnd=Power%20ON" >/dev/null; mode=cold
  else
    timeout 10 "${SSH[@]}" "root@${ETH_IP}" 'systemctl reboot' 2>/dev/null; sleep 8; mode=soft
  fi
  t0=$(date +%s)
  until timeout 6 "${SSH[@]}" "root@${ETH_IP}" true 2>/dev/null; do
    (( $(date +%s) - t0 > 180 )) && { log "iter ${i} ${mode}: no SSH after 180 s"; exit 1; }
    sleep 2
  done
  sleep 8
  out="$(timeout 30 "${SSH[@]}" "root@${ETH_IP}" 'hciconfig hci0 2>&1 | sed -n 3p | tr -s " \t" " ";
    echo "|"; journalctl -b -u k1-bt-rebind --no-pager -o cat | grep -E "hci0|rebind" | tr "\n" " ";
    echo "|"; dmesg | grep -iE "hci0|btrtl|hci_uart|serdev|Bluetooth: HCI UART" | tail -6 | tr "\n" ";"')"
  if [[ ${out} == *"UP RUNNING"* ]]; then
    log "iter ${i} ${mode}: BT OK ${out#*|}" | cut -c1-160
  else
    log "iter ${i} ${mode}: BT FAIL -> ${out}"
    log "stopping, board left in the failing state for inspection"
    exit 2
  fi
done
log "no BT failure in ${MAX} boots"
