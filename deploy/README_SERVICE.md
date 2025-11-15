aneo LED - systemd service install instructions

This directory contains a systemd unit file to run `led_aneo.py` as early as possible during boot.

Files added:
- `aneo-led.service` - systemd unit to run `/home/clement/apps/aneo_led/led_aneo.py`.

Quick install (requires root):

1. Copy the service file to systemd's system directory:

```bash
sudo cp deploy/aneo-led.service /etc/systemd/system/aneo-led.service
```

2. Reload systemd to pick up the new unit:

```bash
sudo systemctl daemon-reload
```

3. Enable the service so it starts at boot:

```bash
sudo systemctl enable aneo-led.service
```

4. Start it now (optional):

```bash
sudo systemctl start aneo-led.service
```

5. Check status and logs:

```bash
sudo systemctl status aneo-led.service
sudo journalctl -u aneo-led.service -n 200 --no-pager
```

Notes and considerations
- The unit uses `Wants=dev-spidev0.0.device` and `After=dev-spidev0.0.device` to wait for the SPI device node. If your hardware exposes a different device name, update the unit file accordingly.
- The service runs as `root` by default to ensure access to `/dev/spidev0.0`. If you'd prefer a less privileged user (e.g., `pi`), create the user, add it to the appropriate groups, adjust `User=` and `Group=` in the unit, and verify permissions on `/dev/spidev0.0`.
- If the service should start even earlier than `multi-user.target` (very rarely needed), you can adjust the `[Install]` section, but doing so may require careful dependency handling. The current config starts very early while still ensuring kernel modules and the SPI device are available.
- If you modify the unit after installing, run `sudo systemctl daemon-reload` then `sudo systemctl restart aneo-led.service`.

Troubleshooting
- If the process fails because of missing Python modules, install them system-wide or into the python environment used by the `ExecStart` command. For example:

```bash
sudo apt update
sudo apt install python3-pip
sudo pip3 install spidev psutil
```

(Prefer virtualenvs or system packages depending on your setup.)

- If you need to test the script manually, run:

```bash
cd /home/clement/apps/aneo_led
/usr/bin/env python3 led_aneo.py
```

- For rapid debugging, view recent logs:

```bash
sudo journalctl -u aneo-led.service -f
```

If you want, I can:
- install the unit into `/etc/systemd/system` automatically (I will need to run shell commands),
- change the unit to run as a specific user (tell me which), or
- make the unit start even earlier (I can draft that but it may need extra checks).
