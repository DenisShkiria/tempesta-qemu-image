#!/bin/sh
set -e

# Enable autologin to the serial console
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d/
cat <<'EOF' > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ubuntu --noclear %I $TERM
EOF
systemctl daemon-reload
systemctl restart serial-getty@ttyS0.service || true