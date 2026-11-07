#!/bin/bash -e
# Fetch the HP EliteBook 840/845 G8 Synaptics fingerprint driver and extract the
# two "110" DLLs that libtudor relinks. These are proprietary HP/Synaptics blobs
# and are NOT committed to this repo — they are downloaded on demand here.
#
# Usage: scripts/fetch-hp-driver.sh [DEST_HPDRV_DIR]
#   DEST defaults to work/synaTudor/libtudor/hpdrv (where the patched
#   download_driver.sh expects them).
#
# Requires: wget, cabextract

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$REPO_DIR/work/synaTudor/libtudor/hpdrv}"

# HP SoftPaq: "Synaptics Fingerprint Sensor Driver" for EliteBook 840/845 G8.
# INF (synaWudfBioUsbUwp.inf) lists USB\VID_06CB&PID_00C0/C4/D8/DF/E9/F0.
URL="https://ftp.hp.com/pub/softpaq/sp111001-111500/sp111238.exe"

command -v cabextract >/dev/null || { echo "ERROR: install cabextract"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading HP driver ($URL)..."
wget -q "$URL" -O "$TMP/sp.exe"

echo "Extracting the HP Softpaq CAB payload..."
mkdir -p "$TMP/x"
cabextract -q -d "$TMP/x" "$TMP/sp.exe"

mkdir -p "$DEST"
cp "$TMP/x/src/driver/INF/x64/synaFpAdapter110.dll" "$DEST/synaFpAdapter110.dll"
cp "$TMP/x/src/driver/INF/x64/synaWudfBioUsb110.dll" "$DEST/synaWudfBioUsb110.dll"

echo "Staged into $DEST:"
ls -la "$DEST"
