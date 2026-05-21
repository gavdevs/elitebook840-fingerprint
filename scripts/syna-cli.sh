#!/bin/bash
# Run as root:  sudo bash scripts/syna-cli.sh
# Launches synaTudor's CLI with the HP "110" driver against the 06cb:00f0 sensor.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/../work/synaTudor/build/cli/tudor_cli"
STORE=/home/nhukette/.tudor-store
LOG=/tmp/syna-cli.log
# Clamp infinite USB waits (ms) so the open-time orphan-record read can't hang forever.
# Pass an override as $1 (e.g. sudo bash ~/syna-cli.sh 4000).
export SYNA_USB_TIMEOUT="${1:-8000}"

# wake + free the sensor
for d in /sys/bus/usb/devices/*; do
  if [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor")" = "06cb" ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = "00f0" ]; then
    echo on > "$d/power/control"
  fi
done
systemctl stop fprintd 2>/dev/null

echo "############################################################"
echo "# tudor_cli + HP 110 driver, sensor 06cb:00f0"
echo "# At the menu:  e=enroll  i=identify  q=query  w=wipe   (Ctrl+D to quit)"
echo "# Secure sensors may need a few restarts to re-pair (driver re-flashes"
echo "#   on ownership change); if it errors, just run this script again 2-3x."
echo "# Full output is also saved to $LOG"
echo "############################################################"
echo
"$CLI" "$STORE" -v -t -P00f0 2>&1 | tee "$LOG"
ec=${PIPESTATUS[0]}
sig=$((ec - 128))
echo "### tudor_cli exit code: $ec  (if >128: killed by signal $sig; 11=SEGV, 6=ABRT) ###" | tee -a "$LOG"
