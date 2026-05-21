#!/bin/bash
# Run as root:  sudo bash ~/fp-test.sh [UID_MAX]
#   UID_MAX (optional): cap the enroll user_id length to this many bytes.
# Tests the freshly-built, patched libfprint Synaptics driver directly.
BIN=/home/nhukette/Projects/libfprint/builddir/examples
export G_MESSAGES_DEBUG=all
[ -n "$1" ] && export SYNA_UID_MAX="$1"

echo "### 1. disabling USB autosuspend on the sensor ###"
for d in /sys/bus/usb/devices/*; do
  if [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor")" = "06cb" ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = "00f0" ]; then
    echo on > "$d/power/control"
    echo "    $d/power/control = $(cat "$d/power/control")"
  fi
done

echo "### 2. stopping system fprintd so it does not hold the device ###"
systemctl stop fprintd

echo "### 3. enroll via PATCHED driver  (SYNA_UID_MAX=${SYNA_UID_MAX:-<none>}) ###"
echo "    touch the sensor repeatedly ONLY if it gets past 'Place Finger' without an instant 104"
echo
"$BIN/enroll"
echo
echo "### enroll exit code: $? ###"
