#!/bin/bash -e
# Reproduce the working 06cb:00df Synaptics Tudor stack:
#   1. clone synaTudor at the pinned base commit
#   2. apply patches/synaTudor-hp110-storage-ipc.patch (HP "110" support, Win-API shims,
#      vendor sensor storage, IPC error reporting, TOD record listing)
#   3. fetch + stage the HP "110" driver DLLs
#   4. build libtudor, tudor_host, tudor_host_launcher, tudor_cli, libtudor_tod.so
#
# This does not touch the system. Install with scripts/install-tudor-stack.sh.
#
# Build deps (Arch): base-devel meson ninja pkgconf glib2 libgusb systemd-libs
#   openssl libusb json-glib libcap libseccomp dbus innoextract

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$REPO_DIR/work"
SYNA="$WORK/synaTudor"
SYNA_BASE_COMMIT="31dfdb0"   # github.com/Popax21/synaTudor base this port was built on

mkdir -p "$WORK"
if [ ! -d "$SYNA/.git" ]; then
    git clone https://github.com/Popax21/synaTudor.git "$SYNA"
fi
cd "$SYNA"
# Start from the pristine pinned base so a re-run never stacks patches twice.
git checkout -f "$SYNA_BASE_COMMIT"
git clean -fdq -e build -e hpdrv
git apply "$REPO_DIR/patches/synaTudor-hp110-storage-ipc.patch"

bash "$REPO_DIR/scripts/fetch-hp-driver.sh" "$SYNA/libtudor/hpdrv"

rm -rf build
meson setup build -DDBGIMPORT=true
ninja -C build
meson test -C build --print-errorlogs
echo
echo "Built:   $SYNA/build/cli/tudor_cli"
echo "Install: sudo bash $REPO_DIR/scripts/install-tudor-stack.sh"
