#!/bin/bash
# Installation script for LED driver on Jetson Orin Nano
# This script installs required dependencies and sets up the LED service

set -e  # Exit on any error

echo "=========================================="
echo "LED Driver Installation for Jetson Orin Nano"
echo "=========================================="

# Check if running on Jetson
if [ ! -f /etc/nv_tegra_release ]; then
    echo "Warning: This doesn't appear to be a Jetson device."
    echo "Continuing anyway..."
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Get the actual user (not root)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER=$SUDO_USER
else
    ACTUAL_USER=$(logname)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Step 1: Updating package list..."
apt-get update

echo ""
echo "Step 2: Installing Python3 and pip..."
apt-get install -y python3 python3-pip python3-dev

echo ""
echo "Step 3: Installing system dependencies..."
# Required for rpi_ws281x library compilation
apt-get install -y build-essential swig scons git

echo ""
echo "Step 4: Installing Python libraries..."
# Install psutil for CPU monitoring
pip3 install psutil

# Try to install rpi_ws281x (primary library)
echo "Attempting to install rpi_ws281x..."
if pip3 install rpi_ws281x; then
    echo "✓ rpi_ws281x installed successfully"
    LIBRARY="rpi_ws281x"
else
    echo "! rpi_ws281x installation failed, trying alternative..."
    # Fallback to adafruit libraries
    pip3 install adafruit-circuitpython-neopixel
    echo "✓ adafruit-circuitpython-neopixel installed"
    LIBRARY="neopixel"
fi

echo ""
echo "Step 5: Configuring GPIO permissions..."
# Add user to gpio group if it exists
if getent group gpio > /dev/null; then
    usermod -a -G gpio $ACTUAL_USER
    echo "✓ Added $ACTUAL_USER to gpio group"
fi

# Create udev rules for GPIO access
echo 'SUBSYSTEM=="gpio", KERNEL=="gpiochip*", MODE="0660", GROUP="gpio"' > /etc/udev/rules.d/99-gpio.rules
echo 'SUBSYSTEM=="pwm", KERNEL=="pwmchip*", MODE="0660", GROUP="gpio"' >> /etc/udev/rules.d/99-gpio.rules

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

echo ""
echo "Step 6: Making LED script executable..."
chmod +x "$SCRIPT_DIR/led_jetson.py"

echo ""
echo "Step 7: Creating systemd service..."
cat > /etc/systemd/system/jetson-led.service << EOF
[Unit]
Description=Jetson LED CPU Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/python3 $SCRIPT_DIR/led_jetson.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "Step 8: Enabling and starting service..."
systemctl daemon-reload
systemctl enable jetson-led.service
systemctl start jetson-led.service

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Service Status:"
systemctl status jetson-led.service --no-pager
echo ""
echo "Useful commands:"
echo "  - View logs:      sudo journalctl -u jetson-led.service -f"
echo "  - Stop service:   sudo systemctl stop jetson-led.service"
echo "  - Start service:  sudo systemctl start jetson-led.service"
echo "  - Restart:        sudo systemctl restart jetson-led.service"
echo "  - Disable:        sudo systemctl disable jetson-led.service"
echo ""
echo "Note: You may need to log out and back in for GPIO group changes to take effect."
echo ""
