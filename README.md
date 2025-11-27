# Ubuntu Cluster LED Monitoring

Real-time CPU monitoring visualization using WS2812B/NeoPixel LED strips for Ubuntu-based single-board computers. This package provides LED driver implementations for both **Raspberry Pi** and **Jetson Orin Nano** platforms.

## Overview

This project displays CPU usage as a dynamic, color-coded bar graph on an LED strip:
- **Green** (LEDs 0-1): Low CPU usage (0-25%)
- **Yellow** (LEDs 2-3): Medium-low CPU usage (25-50%)
- **Orange** (LEDs 4-5): Medium-high CPU usage (50-75%)
- **Red** (LEDs 6-7): High CPU usage (75-100%)

Features:
- Smooth transitions with subtle jitter effects
- Peak hold indicator with decay
- Scanning wave animation
- Last LED blinks when active
- Boot animation sequence
- Systemd service integration for auto-start

## Hardware Setup

### Raspberry Pi (tested on Pi 5)

**Hardware Requirements:**
- Raspberry Pi (Pi 5 or compatible)
- WS2812B/NeoPixel LED strip (8 LEDs recommended)
- Power supply for LED strip (5V, adequate amperage for your LED count)

**Wiring:**
- SPI MOSI (Pin 19 / GPIO 10) → LED strip DIN
- Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39) → LED strip GND
- External 5V power supply → LED strip VIN (recommended for >8 LEDs)

**Software:**
- Uses `pi5neo` library for SPI-based NeoPixel control
- Script: `led_aneo.py`
- SPI device: `/dev/spidev0.0`

### Jetson Orin Nano

**Hardware Requirements:**
- NVIDIA Jetson Orin Nano
- WS2812B/NeoPixel LED strip (8 LEDs recommended)
- Power supply for LED strip (5V, adequate amperage for your LED count)

**Wiring:**
- SPI MOSI (Pin 19) → LED strip DIN
- Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39) → LED strip GND
- External 5V power supply → LED strip VIN (recommended for >8 LEDs)

**Software:**
- Uses `adafruit-circuitpython-neopixel-spi` library for SPI-based NeoPixel control
- Script: `led_jetson.py`
- Requires SPI1 to be enabled via `jetson-io`

## Installation

### Raspberry Pi Installation

#### Option 1: Quick Install (Root Service)

Run the simple installer from the repository root:

```bash
sudo ./install_jetson.sh
```

This installs the service to run from the current directory as root.

#### Option 2: Production Install (Recommended)

Use the advanced installer for production deployments:

```bash
cd deploy
sudo ./install_service.sh --install-dir /opt/aneo_led --venv --user pi
```

**Installer Options:**
- `--user USER` — Run service as specified user (creates system user if needed). Default: `root`
- `--install-dir DIR` — Install location. Default: `/opt/aneo_led`
- `--venv` — Create Python virtualenv for isolated dependencies

**What it does:**
1. Installs Python dependencies (`pi5neo`, `psutil`)
2. Configures SPI device permissions (udev rules)
3. Copies `led_aneo.py` to install directory
4. Creates and enables systemd service
5. Starts the LED monitoring service

### Jetson Orin Nano Installation

#### Option 1: Quick Install (Root Service)

Run the simple installer from the repository root:

```bash
sudo ./install_jetson.sh
```

This installs the service to run from the current directory as root.

#### Option 2: Production Install (Recommended)

Use the advanced installer for production deployments:

```bash
cd deploy
sudo ./install_service_jetson.sh --install-dir /opt/jetson_led --venv --user jetson
```

**Installer Options:**
- `--user USER` — Run service as specified user (creates system user if needed). Default: `root`
- `--install-dir DIR` — Install location. Default: `/opt/jetson_led`
- `--venv` — Create Python virtualenv for isolated dependencies

**What it does:**
1. Enables SPI1 interface via `jetson-io` (if available)
2. Installs Python dependencies (`adafruit-circuitpython-neopixel-spi`, `adafruit-blinka`, `psutil`)
3. Configures SPI device permissions (udev rules for `spidev` group)
4. Copies `led_jetson.py` to install directory
5. Creates and enables systemd service
6. Starts the LED monitoring service

## Service Management

### Check Service Status

```bash
sudo systemctl status aneo-led.service      # For Raspberry Pi
sudo systemctl status jetson-led.service    # For Jetson
```

### View Live Logs

```bash
sudo journalctl -u aneo-led.service -f      # For Raspberry Pi
sudo journalctl -u jetson-led.service -f    # For Jetson
```

### Control Service

```bash
# Stop service
sudo systemctl stop aneo-led.service        # Raspberry Pi
sudo systemctl stop jetson-led.service      # Jetson

# Start service
sudo systemctl start aneo-led.service       # Raspberry Pi
sudo systemctl start jetson-led.service     # Jetson

# Restart service
sudo systemctl restart aneo-led.service     # Raspberry Pi
sudo systemctl restart jetson-led.service   # Jetson

# Disable auto-start
sudo systemctl disable aneo-led.service     # Raspberry Pi
sudo systemctl disable jetson-led.service   # Jetson

# Re-enable auto-start
sudo systemctl enable aneo-led.service      # Raspberry Pi
sudo systemctl enable jetson-led.service    # Jetson
```

## Manual Testing

You can run the LED scripts manually for testing before installing the service:

### Raspberry Pi

```bash
sudo python3 led_aneo.py
```

### Jetson Orin Nano

```bash
sudo python3 led_jetson.py
```

**If you get "Could not determine Jetson model" error:**
1. Upgrade Jetson.GPIO: `sudo pip3 install --upgrade "Jetson.GPIO>=2.1.9"`
2. Add user to spi group: `sudo usermod -aG spi $USER`
3. Log out and back in (or reboot)

Press `Ctrl+C` to stop.

## Configuration

Both scripts have configuration sections at the top that you can modify:

```python
NUM_LEDS = 8                    # Number of LEDs in your strip
BRIGHTNESS_FACTOR = 0.15        # Global brightness (0.0-1.0)
UPDATE_DELAY = 0.08             # Update frequency (seconds)
SMOOTHING_FACTOR = 0.3          # CPU reading smoothing (0.0-1.0)
JITTER_INTENSITY = 0.12         # Animation jitter amount (0.0-1.0)
```

For Raspberry Pi, you can also adjust:
```python
SPI_DEVICE = '/dev/spidev0.0'   # SPI device path
SPI_FREQ = 800                   # SPI frequency (kHz)
```

## Troubleshooting

### Raspberry Pi Issues

**Service fails to start:**
1. Check SPI is enabled: `ls -l /dev/spidev0.0`
2. Verify Python dependencies: `pip3 list | grep pi5neo`
3. Check logs: `sudo journalctl -u aneo-led.service -n 50`

**Wrong colors or no LEDs:**
- Verify wiring (MOSI to DIN, GND to GND)
- Check LED strip requires 5V power
- Adjust `SPI_FREQ` if needed (try 800, 1200, or 2400)

**Permission denied on `/dev/spidev0.0`:**
- Ensure udev rules are installed: `ls -l /etc/udev/rules.d/99-aneo-spi.rules`
- Reload udev: `sudo udevadm control --reload-rules && sudo udevadm trigger`

### Jetson Orin Nano Issues

**"Could not determine Jetson model" error:**
- **Root cause**: Outdated Jetson.GPIO library
- **Fix**: Upgrade Jetson.GPIO to version 2.1.9 or higher:
  ```bash
  sudo pip3 install --upgrade "Jetson.GPIO>=2.1.9"
  ```
- **Additional step**: Add your user to the spi group:
  ```bash
  sudo usermod -aG spi $USER
  # Then log out and back in, or reboot
  ```
- The installation script handles this automatically

**Service fails to start:**
1. Check SPI is enabled: `ls -l /dev/spidev0.0`
2. Enable SPI manually if needed: `sudo /opt/nvidia/jetson-io/jetson-io.py`
3. Verify Python dependencies: `pip3 list | grep -E "Jetson.GPIO|adafruit"`
4. Check Jetson.GPIO version: `pip3 show Jetson.GPIO` (should be >= 2.1.9)
5. Verify user is in spi group: `groups` (should show "spi")
6. Check logs: `sudo journalctl -u jetson-led.service -n 50`

**Wrong colors or no LEDs:**
- Verify wiring (MOSI Pin 19 to DIN, GND to GND)
- Check LED strip has adequate 5V power supply
- Verify SPI device permissions: `ls -l /dev/spidev0.0`

**Permission denied on `/dev/spidev0.0`:**
- Ensure user is in `spi` group: `groups jetson` (or your username)
- Check udev rules: `ls -l /etc/udev/rules.d/99-jetson-gpio.rules`
- Reload udev: `sudo udevadm control --reload-rules && sudo udevadm trigger`
- Log out and back in (or reboot) for group changes to take effect

## Network Configuration

The repository includes a sample netplan configuration (`90-cluster.yaml`) for static IP assignment:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      renderer: networkd
      addresses:
        - 192.168.2.13/24
```

To apply network configuration:

```bash
sudo cp 90-cluster.yaml /etc/netplan/
sudo netplan apply
```

## Platform-Specific Notes

### Raspberry Pi
- Uses SPI for reliable LED control (more stable than PWM/GPIO)
- `pi5neo` library optimized for Raspberry Pi 5
- Runs on `/dev/spidev0.0` by default
- No special hardware configuration needed (SPI auto-enabled on most Pi OS)

### Jetson Orin Nano
- Uses SPI for LED control (NeoPixel SPI library)
- Requires SPI1 to be explicitly enabled via `jetson-io`
- Uses Adafruit Blinka for hardware abstraction
- May require manual SPI configuration on first boot

## File Structure

```
.
├── README.md                          # This file
├── 90-cluster.yaml                    # Sample netplan network config
├── led_aneo.py                        # Raspberry Pi LED driver
├── led_jetson.py                      # Jetson Orin Nano LED driver
├── install_jetson.sh                  # Simple Jetson installer
└── deploy/
    ├── README_SERVICE.md              # Raspberry Pi service details
    ├── README_JETSON.md               # Jetson service details
    ├── aneo-led.service               # Raspberry Pi systemd unit template
    ├── jetson-led.service             # Jetson systemd unit template
    ├── install_service.sh             # Advanced Raspberry Pi installer
    └── install_service_jetson.sh      # Advanced Jetson installer
```

## License

This project is provided as-is for monitoring Ubuntu cluster nodes with LED indicators.

## Contributing

When adding support for new platforms:
1. Create a new `led_<platform>.py` script
2. Add corresponding installer script
3. Create systemd service template
4. Update this README with platform-specific instructions
