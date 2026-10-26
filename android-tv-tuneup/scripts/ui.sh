#!/bin/sh
# Drive and read an Android TV UI over adb.
# Usage:
#   ui.sh <serial> dump                 # print visible texts, which item has focus, toggle states
#   ui.sh <serial> key KEY [KEY ...]    # send key events (DPAD_DOWN, DPAD_CENTER, BACK, HOME, MENU ...)
#   ui.sh <serial> shot <out.png>       # screenshot (strips vendor log noise before the PNG header)
# Always `dump` after moving focus and before pressing DPAD_CENTER, so you never toggle the wrong row.
set -u
SER="${1:?serial}"; CMD="${2:?dump|key|shot}"; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

case "$CMD" in
  dump)
    adb -s "$SER" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb -s "$SER" pull /sdcard/ui.xml "$TMPD/ui.xml" >/dev/null 2>&1
    adb -s "$SER" shell rm -f /sdcard/ui.xml
    python3 -I "$HERE/ui_parse.py" "$TMPD/ui.xml"
    ;;
  key)
    for k in "$@"; do
      case "$k" in KEYCODE_*) ;; *) k="KEYCODE_$k";; esac
      adb -s "$SER" shell input keyevent "$k"
      sleep 1
    done
    ;;
  shot)
    OUTF="${1:?output png path}"
    adb -s "$SER" exec-out screencap -p > "$TMPD/raw.bin"
    python3 -I -c 'import sys;d=open(sys.argv[1],"rb").read();i=d.find(b"\x89PNG");sys.exit("no PNG data (DRM/secure screen?)") if i<0 else open(sys.argv[2],"wb").write(d[i:])' "$TMPD/raw.bin" "$OUTF"
    command -v sips >/dev/null && sips -Z 1280 "$OUTF" >/dev/null 2>&1
    echo "$OUTF"
    ;;
  *) echo "unknown command $CMD" >&2; exit 2;;
esac
