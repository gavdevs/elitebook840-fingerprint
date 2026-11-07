#!/bin/bash -e
# Reproduce the working 06cb:00df Synaptics Tudor stack from source:
#   1. clone the synaTudor fork and check out the feature branch
#      (HP "110" support, vendor sensor storage, IPC error reporting)
#   2. fetch + stage the HP "110" driver DLLs
#   3. build libtudor, tudor_host, tudor_host_launcher, tudor_cli, libtudor_tod.so
#
# This does not touch the system. Install with scripts/install-tudor-stack.sh.
#
# Build deps (Arch): base-devel meson ninja pkgconf glib2 libgusb systemd-libs
#   openssl libusb json-glib libcap libseccomp dbus innoextract

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$REPO_DIR/work"
SYNA="$WORK/synaTudor"
# Our work now lives as commits on a branch of the synaTudor fork, which is the
# canonical copy. FORK overrides it (e.g. to track upstream once merged).
SYNA_FORK="${SYNA_FORK:-https://github.com/gavdevs/synaTudor.git}"
SYNA_BRANCH="${SYNA_BRANCH:-hp110-storage-ipc}"

mkdir -p "$WORK"
if [ ! -d "$SYNA/.git" ]; then
    git clone "$SYNA_FORK" "$SYNA"
else
    git -C "$SYNA" remote set-url origin "$SYNA_FORK"
fi
cd "$SYNA"
# Track the fork's branch directly: no patch stack to reapply, and re-running
# this only fast-forwards.
git fetch -q origin "$SYNA_BRANCH"
git checkout -f -B "$SYNA_BRANCH" "origin/$SYNA_BRANCH"
git clean -fdq -e build -e hpdrv

bash "$REPO_DIR/scripts/fetch-hp-driver.sh" "$SYNA/libtudor/hpdrv"

rm -rf build
meson setup build -DDBGIMPORT=true
ninja -C build
meson test -C build --print-errorlogs
echo
echo "Built:   $SYNA/build/cli/tudor_cli"
echo "Install: sudo bash $REPO_DIR/scripts/install-tudor-stack.sh"
