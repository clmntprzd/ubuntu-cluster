#!/usr/bin/env bash
set -euo pipefail

# install_service.sh
# Idempotent installer for the aneo LED systemd service.
# Usage: sudo ./install_service.sh [--user USER]

# Default values
SERVICE_USER="root"
SERVICE_GROUP="root"
# Where to install the project on the target system. Default: /opt/aneo_led
INSTALL_DIR="/opt/aneo_led"
# Create and use a virtualenv under the install dir when true
USE_VENV="false"

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
    --install-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--install-dir requires an argument"
        exit 1
      fi
      INSTALL_DIR="$1"
      shift
      ;;
    --venv)
      USE_VENV="true"
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
INSTALL_DIR="$(readlink -f "$INSTALL_DIR")"
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

# Copy project to install dir (idempotent). We copy the entire project folder so the service
# runs from a predictable location independent of where the user ran the installer.
echo "Installing project to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$PROJECT_ROOT/" "$INSTALL_DIR/"
else
  # fallback to tar/untar for portability
  (cd "$PROJECT_ROOT" && tar -c .) | (cd "$INSTALL_DIR" && tar -x --overwrite)
fi
# Ensure ownership matches the requested service user so files are accessible when service runs
chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$INSTALL_DIR" || true

# If requested, create a virtualenv in the install dir and install python deps into it
VENV_DIR="$INSTALL_DIR/venv"
VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"
if [[ "$USE_VENV" == "true" ]]; then
  echo "Setting up virtualenv at $VENV_DIR"
  if [[ ! -d "$VENV_DIR" ]]; then
    # Use system python3 to create venv
    if command -v python3 >/dev/null 2>&1; then
      python3 -m venv "$VENV_DIR"
    else
      echo "python3 not found; cannot create virtualenv" >&2
      exit 1
    fi
  fi
  # Upgrade pip inside venv and install packages
  "$VENV_PYTHON" -m pip install --upgrade pip
  "$VENV_PIP" install --upgrade pi5neo psutil spidev
else
  # Will install system-wide later if venv not used
  VENV_DIR=""
fi

# Prepare modified service file content (adjust ExecStart/WorkingDirectory and User/Group lines)
TMP_SERVICE="/tmp/aneo-led.service.$$"

# Decide ExecStart python command: venv python if created, otherwise system env python3
if [[ -n "${VENV_DIR}" && -x "${VENV_PYTHON}" ]]; then
  PY_CMD="${VENV_PYTHON}"
else
  PY_CMD="/usr/bin/env python3"
fi

# Replace User=, Group=, ExecStart= and WorkingDirectory= lines if present, otherwise append them
awk -v user="$SERVICE_USER" -v group="$SERVICE_GROUP" \
    -v execpath="$INSTALL_DIR/led_aneo.py" -v workdir="$INSTALL_DIR" -v pycmd="$PY_CMD" '
  BEGIN{u="User="user; g="Group="group; es = "ExecStart=" pycmd " " execpath; wdline = "WorkingDirectory=" workdir}
  /^(User|Group|ExecStart|WorkingDirectory)=/ {next}
  {print}
  END{print es; print wdline; print u; print g}
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
