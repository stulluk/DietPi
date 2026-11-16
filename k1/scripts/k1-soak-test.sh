#!/bin/bash
# Host side soak test for the KICKPI K1A: repeated soft reboots and cold relay power cycles.
# Every iteration prints one result line (and a CSV row); waits print a heartbeat every 15 s and
# have their own timeout, so the run never sits silent.
# Usage: k1-soak-test.sh [iterations] [csv]
set -u

ITER="${1:-10}"
CSV="${2:-$(dirname "$0")/../logs/soak-$(date +%Y%m%d-%H%M%S).csv}"
WLAN_IP="${K1_WLAN_IP:-192.168.1.112}"
ETH_IP="${K1_ETH_IP:-192.168.1.113}"
RELAY="${K1_RELAY:-tasmota-11.lan}"
BOOT_TIMEOUT=240
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no
     -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

# Wait until "ssh root@$1 true" works; prints a heartbeat every 15 s. Echoes seconds or "timeout".
wait_ssh() {
  local ip="$1" t0 now last=0
  t0=$(date +%s)
  while true; do
    if timeout 6 "${SSH[@]}" "root@${ip}" true 2>/dev/null; then
      echo $(( $(date +%s) - t0 )); return 0
    fi
    now=$(( $(date +%s) - t0 ))
    if (( now - last >= 15 )); then log "  ... waiting for ${ip} (${now}s)" >&2; last=${now}; fi
    if (( now >= BOOT_TIMEOUT )); then echo timeout; return 1; fi
    sleep 2
  done
}

# Collect the health of the running board as key=value pairs on one line.
probe() {
  # shellcheck disable=SC2016 # expanded on the board
  timeout 40 "${SSH[@]}" "root@${WLAN_IP}" '
    ssid=$(iw dev wlan0 link | sed -n "s/^[[:space:]]*SSID: //p")
    sig=$(iw dev wlan0 link | sed -n "s/^[[:space:]]*signal: \([-0-9]*\).*/\1/p")
    bt=$(hciconfig hci0 2>/dev/null | sed -n 3p | tr -s " \t" " " | sed "s/^ //;s/ $//;s/ /_/g")
    usb=$(lsusb | grep -vc "root hub")
    tty=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | wc -l)
    failed=$(systemctl --failed --no-legend | wc -l)
    boot=$(systemd-analyze 2>/dev/null | sed -n "s/.*= \([0-9.]*\)s.*/\1/p")
    kerr=$(dmesg | grep -ciE "Oops|BUG:|Call trace|panic|soft lockup|rcu_sched self-detected")
    wd=$(systemctl show -p WatchdogDevice --value 2>/dev/null; :)
    echo "ssid=${ssid:-none} signal=${sig:-na} bt=${bt:-none} usb=${usb} tty=${tty} failed=${failed} boot=${boot:-na} kerr=${kerr}"
  ' 2>/dev/null || echo "probe=failed"
}

relay() { curl -s -m 5 "http://${RELAY}/cm?cmnd=Power%20$1" >/dev/null; }

echo "iter,mode,t_wlan,t_eth,result" > "${CSV}"
log "soak test: ${ITER} iterations, CSV ${CSV}"
fails=0
for i in $(seq 1 "${ITER}"); do
  if (( i % 2 )); then
    mode=soft
    timeout 10 "${SSH[@]}" "root@${ETH_IP}" 'systemctl reboot' 2>/dev/null || true
    sleep 5
  else
    mode=cold
    relay OFF; sleep 5; relay ON
  fi
  log "iter ${i}/${ITER} ${mode}: rebooting"
  tw=$(wait_ssh "${WLAN_IP}")
  te=$(wait_ssh "${ETH_IP}")
  sleep 5
  res="$(probe)"
  case "${tw}${te}${res}" in
    *timeout*|*probe=failed*|*ssid=none*|*bt=none*) fails=$((fails + 1)); status=FAIL ;;
    *) status=OK ;;
  esac
  log "iter ${i} ${mode} ${status}: t_wlan=${tw}s t_eth=${te}s ${res}"
  echo "${i},${mode},${tw},${te},\"${status} ${res}\"" >> "${CSV}"
done
log "soak test done: $((ITER - fails))/${ITER} OK"
