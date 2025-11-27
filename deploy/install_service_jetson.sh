#!/usr/bin/env bash
set -euo pipefail

# install_service_jetson.sh
# Idempotent installer for the jetson LED systemd service.
# Usage: sudo ./install_service_jetson.sh [--user USER]

# Default values
SERVICE_USER="root"
SERVICE_GROUP="root"
# Where to install the project on the target system. Default: /opt/jetson_led
INSTALL_DIR="/opt/jetson_led"
# Create and use a virtualenv under the install dir when true
USE_VENV="false"

print_usage() {
  cat <<EOF
Usage: sudo $0 [--user USER]

Options:
  --user USER   Run the service as USER (will create system user if missing). Default: root

This script will:
  - copy deploy/jetson-led.service to /etc/systemd/system/jetson-led.service (modifying User/Group if requested)
  - reload systemd, enable and start the service
  - install Python deps: adafruit-circuitpython-neopixel, adafruit-blinka, psutil
  - configure GPIO permissions for Jetson Orin Nano

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

# Enable SPI1 using jetson-io.py if available
if command -v jetson-io >/dev/null 2>&1; then
  echo "Configuring SPI1 using jetson-io..."
  # Check if SPI1 is already enabled
  if ! jetson-io -l 2>/dev/null | grep -q "spi1.*enabled"; then
    echo "Enabling SPI1..."
    jetson-io -o spi1 || echo "Warning: Could not enable SPI1 automatically. You may need to enable it manually with: sudo jetson-io"
  else
    echo "SPI1 is already enabled"
  fi
elif [ -f /opt/nvidia/jetson-io/jetson-io.py ]; then
  echo "Configuring SPI1 using jetson-io.py..."
  if ! python3 /opt/nvidia/jetson-io/jetson-io.py -l 2>/dev/null | grep -q "spi1.*enabled"; then
    echo "Enabling SPI1..."
    python3 /opt/nvidia/jetson-io/jetson-io.py -o spi1 || echo "Warning: Could not enable SPI1 automatically. You may need to enable it manually."
  else
    echo "SPI1 is already enabled"
  fi
else
  echo "Warning: jetson-io not found. SPI may need to be enabled manually."
  echo "To enable SPI manually, run: sudo /opt/nvidia/jetson-io/jetson-io.py"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="$(readlink -f "$INSTALL_DIR")"
SERVICE_SRC="$SCRIPT_DIR/jetson-led.service"
SERVICE_DEST="/etc/systemd/system/jetson-led.service"
UDEV_RULE="/etc/udev/rules.d/99-jetson-gpio.rules"

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

# Ensure spi group exists (for SPI device access)
if ! getent group spi >/dev/null 2>&1; then
  echo "Creating group 'spi'"
  groupadd spi || true
fi

# If non-root service user, add to spi group for SPI access
if [[ "$SERVICE_USER" != "root" ]]; then
  echo "Adding $SERVICE_USER to group spi"
  usermod -a -G spi "$SERVICE_USER" || true
fi

# Copy only the Jetson LED script to install dir
echo "Installing LED script to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp "$PROJECT_ROOT/led_jetson.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/led_jetson.py"
# Ensure ownership matches the requested service user
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
  "$VENV_PIP" install --upgrade adafruit-circuitpython-neopixel adafruit-blinka psutil
else
  # Will install system-wide later if venv not used
  VENV_DIR=""
fi

# Prepare modified service file content
TMP_SERVICE="/tmp/jetson-led.service.$$"

# Decide ExecStart python command: venv python if created, otherwise system env python3
if [[ -n "${VENV_DIR}" && -x "${VENV_PYTHON}" ]]; then
  PY_CMD="${VENV_PYTHON}"
else
  PY_CMD="/usr/bin/env python3"
fi

# Replace User=, Group=, ExecStart= and WorkingDirectory= lines if present
awk -v user="$SERVICE_USER" -v group="$SERVICE_GROUP" \
    -v execpath="$INSTALL_DIR/led_jetson.py" -v workdir="$INSTALL_DIR" -v pycmd="$PY_CMD" '
  BEGIN{
    u="User="user; g="Group="group;
    es = "ExecStart=" pycmd " " execpath;
    wdline = "WorkingDirectory=" workdir;
    in_service=0; inserted=0;
  }
  # remove any existing directives we will set
  /^(User|Group|ExecStart|WorkingDirectory)=/ {next}

  # detect Service section start
  /^\[Service\]/ { in_service=1; print; next }

  # when leaving Service section and not yet inserted, insert our directives before the next section
  (/^\[.*\]/ && in_service==1 && inserted==0) {
    print es; print wdline; print u; print g; inserted=1; in_service=0;
    print; next
  }

  { print }

  END{
    if(inserted==0) { print es; print wdline; print u; print g }
  }
' "$SERVICE_SRC" > "$TMP_SERVICE"

# Install service file
echo "Installing systemd unit to $SERVICE_DEST"
cp "$TMP_SERVICE" "$SERVICE_DEST"
chmod 644 "$SERVICE_DEST"
rm -f "$TMP_SERVICE"

# Create udev rule for SPI access on Jetson
if [[ ! -f "$UDEV_RULE" ]]; then
  echo "Creating udev rule $UDEV_RULE"
  cat > "$UDEV_RULE" <<EOF
# Jetson LED: ensure SPI devices are accessible
SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
KERNEL=="spidev*", GROUP="spi", MODE="0660"
EOF
fi

# Reload udev rules
udevadm control --reload-rules || true
udevadm trigger --action=change || true

# Install Python dependencies
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

# Install required python packages for Jetson NeoPixels via SPI
echo "Installing Python packages: adafruit-circuitpython-neopixel-spi psutil"
$PIP install --upgrade adafruit-circuitpython-neopixel-spi psutil

# Reload systemd, enable and start service
systemctl daemon-reload
systemctl enable jetson-led.service

# Start (or restart) the service
if systemctl is-active --quiet jetson-led.service; then
  systemctl restart jetson-led.service
else
  systemctl start jetson-led.service
fi

# Show status
systemctl status jetson-led.service --no-pager

cat <<EOF

Installation complete.
Notes:
 - Service unit: $SERVICE_DEST
 - Service runs as: $SERVICE_USER:$SERVICE_GROUP
 - Udev rule: $UDEV_RULE (sets SPI devices to group 'spi' + mode 0660)
 - NeoPixels connected via SPI (default: /dev/spidev0.0)
 - If you used a non-root service user, you may need to log out/login or reboot for group membership to take effect.

If the service fails to start, check logs with:
  sudo journalctl -u jetson-led.service -f

EOF
