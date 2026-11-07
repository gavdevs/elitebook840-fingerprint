#!/bin/bash
# Install the working 06cb:00df Synaptics Tudor stack on Arch/Omarchy.
#
# Installs: libtudor.so, tudor_host, tudor_host_launcher, tudor_cli,
# libtudor_tod.so, the launcher systemd unit, the D-Bus policy/activation files,
# and the udev rule (into rules.d, where udev actually reads it).
#
# Run after ./setup.sh has built work/synaTudor/build.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYNA="$REPO/work/synaTudor"
BUILD="$SYNA/build"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run with sudo (writes /usr/bin/tudor and /usr/lib)."
    exit 2
fi
if [ ! -d "$BUILD" ]; then
    echo "ERROR: $BUILD missing; run ./setup.sh first."
    exit 1
fi

echo "[1/5] Installing binaries and the TOD module..."
# Use meson's install, not a plain copy: meson rewrites the build-tree rpath
# ($ORIGIN/../libtudor) to $ORIGIN at install time. Copying the build output by
# hand leaves the build rpath in place, and tudor_host then cannot find
# libtudor.so even though it sits next to it.
meson install -C "$BUILD" --quiet

# meson's udevdir is one level above where systemd-udev reads rules, so the rule
# it installs there is inert; step 3 places the real one in rules.d.
rm -f /usr/lib/udev/60-tudor-libfprint-tod.rules

echo "[2/5] Installing systemd unit and D-Bus policy..."
install -Dm644 "$SYNA/tudor-host-launcher/tudor-host-launcher.service" \
    /usr/lib/systemd/system/tudor-host-launcher.service
install -Dm644 "$SYNA/tudor-host-launcher/net.reactivated.TudorHostLauncher.conf" \
    /usr/share/dbus-1/system.d/net.reactivated.TudorHostLauncher.conf
install -Dm644 "$REPO/packaging/net.reactivated.TudorHostLauncher.service" \
    /usr/share/dbus-1/system-services/net.reactivated.TudorHostLauncher.service

# udev only reads *.rules from udevdir/rules.d; meson's udevdir points one level
# too high, which is why the upstream install placed an inert file in /usr/lib/udev.
echo "[3/5] Installing udev rule into rules.d..."
install -Dm644 "$REPO/packaging/60-tudor-libfprint-tod.rules" \
    /usr/lib/udev/rules.d/60-tudor-libfprint-tod.rules
rm -f /usr/lib/udev/60-tudor-libfprint-tod.rules

echo "[4/5] Reloading systemd, udev, and D-Bus..."
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb
systemctl reload dbus 2>/dev/null || systemctl restart dbus

echo "[5/5] Starting the Tudor host launcher..."
# The launcher unit is Type=dbus with no [Install] section: it is started by
# D-Bus activation, not enabled.
systemctl restart tudor-host-launcher.service
systemctl restart fprintd.service

echo
echo "Installed. Check with:"
echo "  fprintd-list \"\$USER\""
echo "  sudo omarchy setup security fingerprint   # enrolls right index + writes PAM"
