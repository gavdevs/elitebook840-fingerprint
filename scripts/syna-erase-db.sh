#!/bin/bash
# Erase EVERY enrollment in the 06cb:00df sensor database, including records
# the vendor query API cannot enumerate (an orphaned template otherwise makes
# every new enrollment of that finger fail as a duplicate).
#
# Must run as root: the CLI opens the USB device before dropping privileges.
#   sudo bash syna-erase-db.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/work/synaTudor/build/cli/tudor_cli"
STORE="$ROOT/state/tudor-store"
LOG="$ROOT/state/erase-db-00df.log"
TARGET_USER="${SUDO_USER:-gav}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run with sudo (the CLI must open the USB device as root)."
    exit 2
fi
if [ ! -x "$CLI" ]; then
    echo "ERROR: missing $CLI"
    exit 1
fi

echo "############################################################"
echo "# DESTRUCTIVE: erases the whole sensor fingerprint database"
echo "# Log: $LOG"
echo "############################################################"

echo "[1/4] Stopping fingerprint services so the sensor is free..."
systemctl stop fprintd.service 2>/dev/null
systemctl stop tudor-host-launcher.service 2>/dev/null
pkill -x tudor_host 2>/dev/null
sleep 1

echo "[2/4] Erasing sensor database via vendor adapter..."
# Input order matters: main() reads one char for the warning, the command loop
# skips whitespace to get 'd', then 'd' calls fgets() for the ERASE word. A
# newline after 'd' would be consumed by fgets() and abort the erase.
# The trailing 's' shuts the driver down; without it the CLI loops on EOF.
printf 'y\ndERASE\ns\n' | \
    TUDOR_FIRMWARE_WRITE_APPROVED=1 TUDOR_DB_ERASE_APPROVED=1 \
    timeout --signal=TERM --kill-after=5s 120s "$CLI" "$STORE" -P00df 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

if ! grep -q 'Sensor database erased' "$LOG"; then
    echo
    echo "ERROR: erase was not confirmed (CLI exit $rc). Last log lines:"
    tail -5 "$LOG"
    echo
    echo "Restarting services unchanged."
    systemctl start tudor-host-launcher.service
    systemctl start fprintd.service
    exit 1
fi

echo "[3/4] Clearing fprintd local metadata..."
rm -rf /var/lib/fprint/*

echo "[4/4] Restarting services..."
systemctl reset-failed fprintd.service tudor-host-launcher.service 2>/dev/null
systemctl start tudor-host-launcher.service
systemctl start fprintd.service
sleep 4

echo
echo "=== fprintd-list ==="
fprintd-list "$TARGET_USER" 2>&1
echo
echo "Sensor database erased. Re-run: omarchy setup security fingerprint"
echo "If fprintd still reports 'No devices available', run:"
echo "  sudo systemctl restart tudor-host-launcher fprintd"
