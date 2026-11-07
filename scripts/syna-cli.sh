#!/bin/bash
# One bounded open/pairing probe for the HP 06cb:00df sensor, with no post-open menu.
# SAFETY: the proprietary HP driver reportedly re-flashes firmware on an ownership
# change. TUDOR_OPEN_ONLY does NOT disable that behavior. Do not approve the run until
# firmware writes are explicitly approved too, or the vendor path is made flash-safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/../work/synaTudor/build/cli/tudor_cli"
STATE="$SCRIPT_DIR/../state"
STORE="$STATE/tudor-store"
LOG="$STATE/open-00df.log"
OPEN_TIMEOUT="${TUDOR_OPEN_TIMEOUT:-60s}"

# Clamp infinite USB waits (ms) so an open-time DB2 read cannot hang forever.
# Pass an override as $1 (for example, 4000).
export SYNA_USB_TIMEOUT="${1:-8000}"
export TUDOR_OPEN_ONLY=1

if [ "${TUDOR_FIRMWARE_WRITE_APPROVED:-}" != "1" ]; then
    echo "REFUSING to run: this is not provably a pairing-only operation."
    echo "The HP driver may reflash firmware during ownership/pairing changes."
    echo "A separate firmware-write approval is required; there is no known disable switch."
    exit 2
fi
if [ ! -x "$CLI" ]; then
    echo "ERROR: missing executable $CLI (complete the local build first)"
    exit 1
fi
mkdir -p "$STATE"

echo "############################################################"
echo "# Bounded tudor_cli open-only probe, sensor 06cb:00df"
echo "# No post-open commands will be accepted. Possible firmware reflash approved."
echo "# Host store: $STORE"
echo "# USB timeout: ${SYNA_USB_TIMEOUT}ms; process timeout: $OPEN_TIMEOUT (SIGKILL 5s later)"
echo "# Full output: $LOG"
echo "############################################################"
printf 'y\n' | timeout --signal=TERM --kill-after=5s "$OPEN_TIMEOUT" \
    "$CLI" "$STORE" -v -t -P00df 2>&1 | tee "$LOG"
ec=${PIPESTATUS[1]}
echo "### tudor_cli exit code: $ec (124=timeout, 137=timeout SIGKILL, 139=SEGV, 134=ABRT) ###" | tee -a "$LOG"
exit "$ec"
