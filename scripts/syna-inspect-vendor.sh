#!/bin/bash
# Read-only vendor secure-storage inspection for the HP 06cb:00df sensor.
# Lists records and makes one bounded verification attempt. No enrollment or deletion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/../work/synaTudor/build/cli/tudor_cli"
STATE="$SCRIPT_DIR/../state"
STORE="$STATE/tudor-store"
LOG="$STATE/inspect-vendor-00df-rerun.log"
TEST_TIMEOUT="${TUDOR_INSPECT_TIMEOUT:-150s}"

if [ "${TUDOR_FIRMWARE_WRITE_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: possible sensor pairing/firmware writes are not approved."
    exit 2
fi
if [ "${TUDOR_INSPECT_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: vendor-storage inspection has not been approved."
    exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "Run in a visible terminal with sudo and both approval variables set."
    exit 2
fi
if [ ! -x "$CLI" ]; then
    echo "ERROR: missing executable $CLI (complete the local build first)"
    exit 1
fi

mkdir -p "$STATE"
export SYNA_USB_TIMEOUT="${1:-8000}"
unset TUDOR_OPEN_ONLY TUDOR_HOST_STORAGE

echo "############################################################"
echo "# Vendor secure-storage inspection, sensor 06cb:00df"
# Fixed commands: query all records, shut down. No enroll, delete, or verify.
echo "# No enroll, no wipe/delete, no authentication changes."
echo "# Log: $LOG"
echo "############################################################"
printf 'y\nq\n0\ns\n' | \
    timeout --signal=TERM --kill-after=5s "$TEST_TIMEOUT" \
    "$CLI" "$STORE" -vv -t -P00df 2>&1 | tee "$LOG"
ec=${PIPESTATUS[1]}
echo "### tudor_cli exit code: $ec ###" | tee -a "$LOG"
exit "$ec"
