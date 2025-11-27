# Jetson "Could not determine Jetson model" Fix

## Problem
When running `led_jetson.py`, you get this error:
```
Exception: Could not determine Jetson model
```

## Root Cause
Outdated `Jetson.GPIO` library (versions < 2.1.9) cannot properly detect Jetson Orin Nano model.

## Solution

### Quick Fix (Manual)
```bash
# 1. Upgrade Jetson.GPIO to version 2.1.9 or higher
sudo pip3 install --upgrade "Jetson.GPIO>=2.1.9"

# 2. Add your user to the spi group
sudo usermod -aG spi $USER

# 3. Log out and back in, or reboot
# Then test:
sudo python3 led_jetson.py
```

### Automatic Fix (Using Installer)
The installation script handles this automatically:
```bash
cd deploy
sudo ./install_service_jetson.sh
```

The script will:
- Upgrade `Jetson.GPIO` to >= 2.1.9
- Add both the service user AND the sudo user to the `spi` group
- Configure udev rules for SPI device access
- Install and start the systemd service

## Verification

### Check Jetson.GPIO Version
```bash
pip3 show Jetson.GPIO
# Should show Version: 2.1.9 or higher
```

### Check Group Membership
```bash
groups
# Should include "spi" in the list
```

### Check SPI Device Access
```bash
ls -l /dev/spidev0.0
# Should show: crw-rw---- 1 root spi ...
```

## Additional Notes

- This fix works in both dev containers and on the Jetson host
- The `spi` group membership allows non-root access to `/dev/spidev0.0`
- A reboot or re-login is required after adding user to group
- The service runs as root by default (no group issues)
- For non-root service users, the installer adds them to the `spi` group automatically

## Related Files
- `/workspaces/ubuntu-cluster/led_jetson.py` - LED driver script
- `/workspaces/ubuntu-cluster/deploy/install_service_jetson.sh` - Automated installer
- `/workspaces/ubuntu-cluster/deploy/jetson-led.service` - Systemd service template
