#!/bin/bash
# Turn the extra debug logging back off (does NOT touch the autosuspend fix).
rm -f /etc/systemd/system/fprintd.service.d/debug.conf
rmdir --ignore-fail-on-non-empty /etc/systemd/system/fprintd.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl restart fprintd
echo "Debug logging removed; fprintd restarted normally."
