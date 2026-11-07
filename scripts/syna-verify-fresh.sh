#!/bin/bash
# Read-only fresh-session verification for the HP 06cb:00df sensor.
# Opens vendor secure storage, verifies one existing record, then exits.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/../work/synaTudor/build/cli/tudor_cli"
STATE="$SCRIPT_DIR/../state"
STORE="$STATE/tudor-store"
LOG="$STATE/verify-fresh-00df.log"
TEST_TIMEOUT="${TUDOR_VERIFY_TIMEOUT:-120s}"

if [ "${TUDOR_FIRMWARE_WRITE_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: possible sensor pairing/firmware writes are not approved."
    exit 2
fi
if [ "${TUDOR_VERIFY_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: fresh-session verification has not been approved."
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
echo "# Fresh-session verification, sensor 06cb:00df"
echo "# Existing record: identity 1, finger 2 (right index)."
echo "# Fixed commands: query, verify identity 1/finger 2, shutdown."
echo "# No enrollment, no deletion, no authentication changes."
echo "# Log: $LOG"
echo "############################################################"
printf 'y\nq\n1\nv\n1\n2\ns\n' | \
    timeout --signal=TERM --kill-after=5s "$TEST_TIMEOUT" \
    "$CLI" "$STORE" -vv -t -P00df 2>&1 | tee "$LOG"
ec=${PIPESTATUS[1]}
echo "### tudor_cli exit code: $ec ###" | tee -a "$LOG"
exit "$ec"
