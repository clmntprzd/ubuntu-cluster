#!/usr/bin/env bash
set -euo pipefail

# install_service.sh
# Idempotent installer for the aneo LED systemd service.
# Usage: sudo ./install_service.sh [--user USER]

# Default values
SERVICE_USER="root"
SERVICE_GROUP="root"

print_usage() {
  cat <<EOF
Usage: sudo $0 [--user USER]

Options:
  --user USER   Run the service as USER (will create system user if missing). Default: root

This script will:
  - copy deploy/aneo-led.service to /etc/systemd/system/aneo-led.service (modifying User/Group if requested)
  - reload systemd, enable and start the service
  - install Python deps: pi5neo, psutil, spidev (system-wide via pip3)
  - create a udev rule to set /dev/spidev* mode=0660 group=spi and add the service user to the spi group if needed

Run as root (it will re-exec with sudo if needed).
EOF
}

# Simple arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--user requires an argument"
        exit 1
      fi
      SERVICE_USER="$1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1"
      print_usage
      exit 1
      ;;
  esac
done

# Re-run under sudo if not root
if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_SRC="$SCRIPT_DIR/aneo-led.service"
SERVICE_DEST="/etc/systemd/system/aneo-led.service"
UDEV_RULE="/etc/udev/rules.d/99-aneo-spi.rules"

if [[ ! -f "$SERVICE_SRC" ]]; then
  echo "Service source file not found: $SERVICE_SRC"
  exit 1
fi

# If requested user is not root, ensure user exists or create system user
if [[ "$SERVICE_USER" != "root" ]]; then
  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    echo "Creating system user: $SERVICE_USER"
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
  SERVICE_GROUP="$SERVICE_USER"
fi

# Ensure spi group exists (common on Raspbian)
if ! getent group spi >/dev/null 2>&1; then
  echo "Creating group 'spi'"
  groupadd spi || true
fi

# If non-root service user, add to spi group so it can access /dev/spidev*
if [[ "$SERVICE_USER" != "root" ]]; then
  echo "Adding $SERVICE_USER to group spi"
  usermod -a -G spi "$SERVICE_USER" || true
fi

# Prepare modified service file content (adjust User/Group lines)
TMP_SERVICE="/tmp/aneo-led.service.$$"

# Replace User= and Group= lines if present, otherwise append them
awk -v user="$SERVICE_USER" -v group="$SERVICE_GROUP" '
  BEGIN{u="User="user; g="Group="group}
  /^(User|Group)=/ {next}
  {print}
  END{print u; print g}
' "$SERVICE_SRC" > "$TMP_SERVICE"

# Install service file
echo "Installing systemd unit to $SERVICE_DEST"
cp "$TMP_SERVICE" "$SERVICE_DEST"
chmod 644 "$SERVICE_DEST"
rm -f "$TMP_SERVICE"

# Create udev rule to set permissions for spidev devices
if [[ ! -f "$UDEV_RULE" ]]; then
  echo "Creating udev rule $UDEV_RULE"
  cat > "$UDEV_RULE" <<EOF
# aneo LED: ensure SPI device is accessible
KERNEL=="spidev*", SUBSYSTEM=="spidev", MODE="0660", GROUP="spi"
EOF
fi

# Reload udev rules (so permission changes apply immediately)
udevadm control --reload-rules || true
udevadm trigger --action=change || true

# Install Python dependencies (system-wide pip)
if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "Python3 not found. Please install python3." >&2
  exit 1
fi

if command -v pip3 >/dev/null 2>&1; then
  PIP=pip3
else
  # try to bootstrap pip
  echo "pip3 not found — attempting to install python3-pip via apt"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y python3-pip
    PIP=pip3
  else
    echo "No pip3 and no apt-get. Please install pip3 and rerun." >&2
    exit 1
  fi
fi

# Install required python packages (idempotent)
echo "Installing Python packages: pi5neo psutil spidev"
$PIP install --upgrade pi5neo psutil spidev --break-system-packages

# Reload systemd, enable and start service
systemctl daemon-reload
systemctl enable aneo-led.service

# Start (or restart) the service
if systemctl is-active --quiet aneo-led.service; then
  systemctl restart aneo-led.service
else
  systemctl start aneo-led.service
fi

# Show status
systemctl status aneo-led.service --no-pager

cat <<EOF

Installation complete.
Notes:
 - Service unit: $SERVICE_DEST
 - Service runs as: $SERVICE_USER:$SERVICE_GROUP
 - Udev rule: $UDEV_RULE (sets /dev/spidev* to group 'spi' + mode 0660)
 - If you used a non-root service user, you may need to log out/login or reboot for group membership to take effect for that user.

If the service fails to start, check logs with:
  sudo journalctl -u aneo-led.service -f

EOF
