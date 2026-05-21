#!/bin/bash
# Disable USB autosuspend on the fingerprint sensor + enable fprintd/libfprint debug logging.
set -e

SENSOR=/sys/bus/usb/devices/3-7
echo "on" > "$SENSOR/power/control"
echo "autosuspend control now: $(cat $SENSOR/power/control)  (want: on)"

mkdir -p /etc/systemd/system/fprintd.service.d
cat > /etc/systemd/system/fprintd.service.d/debug.conf <<'EOF'
[Service]
Environment=G_MESSAGES_DEBUG=all
EOF

systemctl daemon-reload
systemctl restart fprintd
echo
echo "Debug logging ON, sensor kept awake."
echo "Now run:   fprintd-enroll      (touch the sensor repeatedly until it finishes or fails)"
echo "Then run:  journalctl -u fprintd -n 120 --no-pager"
