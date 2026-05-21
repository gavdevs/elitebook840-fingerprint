#!/bin/bash -e
# Reproduce the synaTudor HP-110 build from a clean checkout:
#   1. clone synaTudor at the pinned base commit
#   2. apply our HP-110 port patch
#   3. fetch + stage the HP "110" driver DLLs
#   4. build (libtudor + tudor_cli) with import debugging on
#
# Build deps (Debian/Ubuntu):
#   sudo apt install -y build-essential meson ninja-build pkg-config \
#       libglib2.0-dev libgusb-dev libudev-dev libssl-dev libusb-1.0-0-dev \
#       libjson-glib-dev libcap-dev libseccomp-dev libdbus-1-dev \
#       libfprint-2-tod-dev innoextract

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$REPO_DIR/work"
SYNA="$WORK/synaTudor"
SYNA_BASE_COMMIT="31dfdb0"   # github.com/Popax21/synaTudor base this port was built on

mkdir -p "$WORK"
if [ ! -d "$SYNA/.git" ]; then
    git clone https://github.com/Popax21/synaTudor.git "$SYNA"
fi
cd "$SYNA"
git checkout "$SYNA_BASE_COMMIT"
git apply --reject "$REPO_DIR/patches/synaTudor-hp110.patch" || \
    echo "NOTE: patch may already be applied (check for *.rej)"

bash "$REPO_DIR/scripts/fetch-hp-driver.sh" "$SYNA/libtudor/hpdrv"

rm -rf build
meson setup build -DDBGIMPORT=true
ninja -C build
echo
echo "Built: $SYNA/build/cli/tudor_cli"
echo "Run:   sudo bash $REPO_DIR/scripts/syna-cli.sh"
