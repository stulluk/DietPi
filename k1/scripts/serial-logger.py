#!/usr/bin/env python3
"""Log a UART console to a file with a timestamp per line, until killed.

Usage: serial-logger.py <device> <baud> <logfile>
Writes a heartbeat line every 60 s of silence, so a dead console is visible in the log.
"""

from __future__ import annotations

import sys
import time

import serial


def main() -> int:
  """Read the serial port forever and append timestamped lines to the log file."""
  dev, baud, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
  ser = serial.Serial(dev, baud, timeout=1)
  buf = b""
  last = time.time()
  with open(path, "a", buffering=1) as log:
    log.write(f"=== serial-logger start {time.strftime('%F %T')} {dev}@{baud}\n")
    while True:
      data = ser.read(4096)
      now = time.time()
      if data:
        buf += data.replace(b"\x00", b"")
        *lines, buf = buf.split(b"\n")
        for line in lines:
          text = line.decode("utf-8", "replace").rstrip("\r")
          log.write(f"[{time.strftime('%T')}] {text}\n")
        last = now
      elif now - last >= 60:
        log.write(f"[{time.strftime('%T')}] --- heartbeat: console silent 60 s\n")
        last = now


if __name__ == "__main__":
  sys.exit(main())
