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

Press Ctrl+C to stop.

## Configuration

Edit `led_jetson.py` to customize:

- `NUM_LEDS`: Number of LEDs in your strip (default: 8)
- `LED_PIN`: GPIO pin number (default: 18)
- `BRIGHTNESS_FACTOR`: Global brightness (default: 0.15)
- `UPDATE_DELAY`: Animation speed (default: 0.08 seconds)

## Troubleshooting

### LEDs not working
- Check LED strip power supply
- Verify GPIO pin connection (Pin 12 / GPIO18)
- Check permissions: `sudo usermod -a -G gpio $USER`
- Try running with sudo: `sudo python3 led_jetson.py`

### Library errors
- The script tries `rpi_ws281x` first, then falls back to `adafruit-circuitpython-neopixel`
- Reinstall: `sudo pip3 install --upgrade rpi_ws281x`

### Service not starting
- Check logs: `sudo journalctl -u jetson-led.service -xe`
- Verify script path in service file
- Test manually: `sudo python3 led_jetson.py`
