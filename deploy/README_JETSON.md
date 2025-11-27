# LED Driver for Jetson Orin Nano

This directory contains the LED driver setup for Jetson Orin Nano devices.

## Files

- `led_jetson.py` - Main LED driver script for CPU visualization
- `install_jetson.sh` - Installation script for dependencies and service setup
- `jetson-led.service` - Systemd service file (created during installation)

## Hardware Requirements

- Jetson Orin Nano
- WS2812B/NeoPixel LED strip (8 LEDs recommended)
- Connect LED strip to GPIO18 (Pin 12)
- Power supply for LED strip (5V)

## Installation

Run the installation script with sudo:

```bash
sudo ./install_jetson.sh
```

This will:
1. Install Python3 and required dependencies
2. Install LED control libraries (rpi_ws281x or adafruit-circuitpython-neopixel)
3. Configure GPIO permissions
4. Create and enable systemd service
5. Start the LED service

## LED Visualization

The script displays CPU usage as a color-coded bar graph:
- **Green** (LEDs 0-1): Low CPU usage
- **Yellow** (LEDs 2-3): Medium-low CPU usage
- **Orange** (LEDs 4-5): Medium-high CPU usage
- **Red** (LEDs 6-7): High CPU usage

Features:
- Smooth transitions with jitter effects
- Peak hold indicator
- Scanning animation
- Last LED blinks when active
- Boot animation on startup

## Service Management

```bash
# View status
sudo systemctl status jetson-led.service

# View logs
sudo journalctl -u jetson-led.service -f

# Stop service
sudo systemctl stop jetson-led.service

# Start service
sudo systemctl start jetson-led.service

# Restart service
sudo systemctl restart jetson-led.service

# Disable auto-start
sudo systemctl disable jetson-led.service
```

## Manual Testing

To test the LED driver without the service:

```bash
sudo python3 led_jetson.py
```

**If you get "Could not determine Jetson model" error:**
1. Upgrade Jetson.GPIO: `sudo pip3 install --upgrade "Jetson.GPIO>=2.1.9"`
2. Add your user to spi group: `sudo usermod -aG spi $USER`
3. Log out and back in (or reboot)

Press Ctrl+C to stop.

## Configuration

Edit `led_jetson.py` to customize:

- `NUM_LEDS`: Number of LEDs in your strip (default: 8)
- `LED_PIN`: GPIO pin number (default: 18)
- `BRIGHTNESS_FACTOR`: Global brightness (default: 0.15)
- `UPDATE_DELAY`: Animation speed (default: 0.08 seconds)

## Troubleshooting

### "Could not determine Jetson model" error
- **Root cause**: Outdated Jetson.GPIO library (needs version >= 2.1.9)
- **Fix**:
  ```bash
  sudo pip3 install --upgrade "Jetson.GPIO>=2.1.9"
  sudo usermod -aG spi $USER
  # Log out and back in, or reboot
  ```
- Verify fix: `pip3 show Jetson.GPIO` (check version)
- Verify group: `groups` (should show "spi")

### SPI device not found
- Check SPI is enabled: `ls -l /dev/spidev0.0`
- Enable SPI: `sudo /opt/nvidia/jetson-io/jetson-io.py`
- Reboot after enabling SPI

### LEDs not working
- Check LED strip power supply (5V, adequate amperage)
- Verify SPI MOSI connection (Pin 19 to LED DIN)
- Check ground connection
- Verify SPI permissions: `ls -l /dev/spidev0.0`
- Ensure user is in spi group: `groups`

### Library errors
- Install dependencies: `pip3 install adafruit-circuitpython-neopixel-spi adafruit-blinka`
- Check Jetson.GPIO: `pip3 show Jetson.GPIO` (should be >= 2.1.9)

### Service not starting
- Check logs: `sudo journalctl -u jetson-led.service -xe`
- Verify script path in service file
- Check Jetson.GPIO version
- Verify service user is in spi group
- Test manually: `sudo python3 led_jetson.py`
