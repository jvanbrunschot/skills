#!/bin/sh
# Reconnect over network adb and wait until Android reports boot completed.
# Usage: wait_boot.sh <ip:port> [timeout_seconds=300]
SER="${1:?ip:port}"; TIMEOUT="${2:-300}"
START=$(date +%s)
sleep 15
while :; do
  adb connect "$SER" >/dev/null 2>&1
  if [ "$(adb -s "$SER" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    echo "booted after $(( $(date +%s) - START ))s"; exit 0
  fi
  [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ] && { echo "timed out after ${TIMEOUT}s" >&2; exit 1; }
  sleep 10
done
