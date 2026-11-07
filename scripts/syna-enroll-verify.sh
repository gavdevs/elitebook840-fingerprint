#!/bin/bash
# One bounded enrollment and verification sequence for the HP 06cb:00df sensor.
# Fixed input permits no wipe, query, or additional driver-open operation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/../work/synaTudor/build/cli/tudor_cli"
STATE="$SCRIPT_DIR/../state"
STORE="$STATE/tudor-store"
LOG="$STATE/enroll-fixed2-00df.log"
TEST_TIMEOUT="${TUDOR_TEST_TIMEOUT:-180s}"
# Optional extra CLI flags (e.g. TUDOR_CLI_EXTRA_FLAGS=-v to log storage-adapter calls)
CLI_EXTRA_FLAGS="${TUDOR_CLI_EXTRA_FLAGS:-}"

if [ "${TUDOR_FIRMWARE_WRITE_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: possible sensor pairing/firmware writes are not approved."
    exit 2
fi
if [ "${TUDOR_ENROLL_VERIFY_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: one enrollment and verification has not been approved."
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
unset TUDOR_OPEN_ONLY

echo "############################################################"
echo "# One enrollment + one verification, sensor 06cb:00df"
# Test identity: 2; enroll finger: 3 (right middle); verify finger: 3
echo "# Use the right middle finger. Touch and lift as requested during enrollment."
echo "# After the success/menu prompt, touch once for verification."
echo "# No wipe commands will be sent. USB timeout: ${SYNA_USB_TIMEOUT}ms"
echo "# Extra CLI flags: '${CLI_EXTRA_FLAGS}' (TUDOR_CLI_EXTRA_FLAGS=-v enables storage logs)"
echo "# Process backstop: $TEST_TIMEOUT; log: $LOG"
printf 'y\ne\n2\n3\nv\n2\n3\ns\n' | \
    timeout --signal=TERM --kill-after=5s "$TEST_TIMEOUT" \
    "$CLI" "$STORE" -v -t $CLI_EXTRA_FLAGS -P00df 2>&1 | tee "$LOG"
ec=${PIPESTATUS[1]}
echo "### tudor_cli exit code: $ec ###" | tee -a "$LOG"
exit "$ec"
