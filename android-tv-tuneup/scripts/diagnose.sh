#!/bin/sh
# Read-only performance diagnosis of an Android TV over adb.
# Usage: diagnose.sh <serial e.g. 192.168.1.163:5555> [outdir]
# Prints a report to stdout; if outdir is given, also saves raw dumpsys output there.
set -u
SER="${1:?usage: diagnose.sh <serial> [outdir]}"
OUT="${2:-}"
S() { adb -s "$SER" shell "$@"; }

section() { printf '\n== %s\n' "$1"; }

# Fail fast if the device isn't usable (TV in standby / stale network adb session).
case "$SER" in *:*) adb connect "$SER" >/dev/null 2>&1;; esac
STATE=$(adb -s "$SER" get-state 2>&1 | tr -d '\r')
if [ "$STATE" != "device" ]; then
  adb disconnect "$SER" >/dev/null 2>&1; adb connect "$SER" >/dev/null 2>&1
  STATE=$(adb -s "$SER" get-state 2>&1 | tr -d '\r')
fi
if [ "$STATE" != "device" ]; then
  echo "adb state for $SER: $STATE — is the TV on (not standby) and debugging allowed?" >&2
  exit 1
fi

section "device"
for p in ro.product.manufacturer ro.product.model ro.build.version.release ro.build.fingerprint \
         ro.board.platform ro.hardware ro.product.cpu.abi ro.config.low_ram; do
  printf '%s=%s\n' "$p" "$(S getprop "$p" | tr -d '\r')"
done

section "uptime / load"
S uptime
echo "(load avg on MediaTek/MStar TVs is inflated by driver threads idling in state D — check CPU idle in top instead)"
printf 'D-state tasks: %s\n' "$(S 'ps -A -o STAT' | grep -c D)"

section "memory (/proc/meminfo)"
S cat /proc/meminfo | grep -E "^(MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree):"

section "memory summary (dumpsys meminfo)"
TMP=$(mktemp)
S dumpsys meminfo > "$TMP"
sed -n '/Total RAM/,/Tuning/p' "$TMP"

section "top 25 processes by PSS"
sed -n '/Total PSS by process/,/Total PSS by OOM/p' "$TMP" | sed -n '2,26p'

section "cpu (top snapshot)"
S top -b -n 1 -m 12 | sed -n '3,20p'

section "cpu frequency / governor"
S 'for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do echo "$(basename $(dirname $c)) cur=$(cat $c/scaling_cur_freq 2>/dev/null) max=$(cat $c/cpuinfo_max_freq 2>/dev/null) gov=$(cat $c/scaling_governor 2>/dev/null)"; done'

section "thermal"
S 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); [ -n "$t$v" ] && echo "$t $v"; done' || true
echo "(empty = not exposed on this device)"

section "storage"
S dumpsys diskstats | grep -E "^(Data-Free|System-Free)"
S df -h /data 2>/dev/null

section "animation scales (global)"
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
  printf '%s=%s\n' "$k" "$(S settings get global "$k" | tr -d '\r')"
done

section "crash / ANR history (dropbox tag counts)"
S dumpsys dropbox 2>/dev/null | grep -E "^[0-9]{4}-" | awk '{print $3}' | sort | uniq -c | sort -rn | head -10

section "most recent ANR (who froze + CPU at the time)"
S dumpsys dropbox --print system_app_anr 2>/dev/null \
  | grep -E "^(Process|Subject):|^CPU usage from|kswapd|mmcqd|[0-9.]+% [0-9]+/" | head -17
echo "(check the date on 'CPU usage from' — an old ANR is history, not current state)"
echo "(kswapd/mmcqd high + many 'major' faults = memory thrashing)"

section "tombstones (native crashes)"
S dumpsys dropbox --print SYSTEM_TOMBSTONE 2>/dev/null | grep -E ">>> .* <<<" | sort | uniq -c | head

section "low-memory kills in current log"
S logcat -d -b events 2>/dev/null | grep am_kill | awk -F'[][]' '{print $2}' | awk -F, '{print $3}' | sort | uniq -c | sort -rn | head -10

section "third-party apps"
S pm list packages -3 | sed 's/^package://' | sort

section "running system apps that are often bloat (review manually)"
S 'ps -A -o NAME' | grep -iE "acr|anoki|samba|alphonso|demo|shopmode|retail|freeview|teatro|hbbtv|twitch|videos|tvrecommendations" | sort -u

section "screensaver"
S settings list secure | grep -E "^screensaver_(enabled|components)"

if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
  cp "$TMP" "$OUT/meminfo.txt"
  S dumpsys usagestats > "$OUT/usagestats.txt" 2>/dev/null
  echo; echo "raw dumps saved in $OUT"
fi
rm -f "$TMP"
