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
# aneo LED - systemd service install instructions

This directory contains a systemd unit file and an installer script to run `led_aneo.py` at boot.

Files:
- `deploy/aneo-led.service` — template unit. The installer will rewrite ExecStart and WorkingDirectory
	to the actual install location and may point ExecStart at a venv python.
- `deploy/install_service.sh` — idempotent installer that copies the project to a chosen location,
	optionally creates a Python virtualenv, installs dependencies, creates a udev rule for SPI, and
	enables/starts the service.

Quick install (recommended: use the installer script):

1. Run the installer (default installs to `/opt/aneo_led` as `root`):

```bash
cd /path/to/aneo_led
sudo deploy/install_service.sh
```

2. Install to `/opt` and create a virtualenv (recommended):

```bash
sudo deploy/install_service.sh --install-dir /opt/aneo_led --venv --user pi
```

Installer flags:
- `--user USER`    — run the service as USER (creates a system user if missing). Default: root
- `--install-dir`  — install project to this directory. Default: `/opt/aneo_led`
- `--venv`         — create a venv at `<install-dir>/venv` and install Python deps into it

Systemd unit notes
- The template defaults to `WorkingDirectory=/opt/aneo_led` and `ExecStart=/usr/bin/env python3 /opt/aneo_led/led_aneo.py`.
	The installer will rewrite these to match the actual install location. If `--venv` is used, ExecStart
	will point at `<install-dir>/venv/bin/python`.
- The unit uses `Wants=dev-spidev0.0.device` and `After=dev-spidev0.0.device` to wait for the SPI device node.

Enabling and controlling the service (if you installed manually):

```bash
sudo cp deploy/aneo-led.service /etc/systemd/system/aneo-led.service
sudo systemctl daemon-reload
sudo systemctl enable aneo-led.service
sudo systemctl start aneo-led.service
sudo systemctl status aneo-led.service
sudo journalctl -u aneo-led.service -n 200 --no-pager
```

Troubleshooting & notes
- If the service fails because of missing Python modules, use the installer with `--venv` or install packages into
	the environment used by ExecStart. The installer will install `pi5neo`, `psutil`, and `spidev` automatically.
- The installer creates a udev rule `/etc/udev/rules.d/99-aneo-spi.rules` that sets `/dev/spidev*` to group `spi`
	and mode `0660`. If your platform uses different device names, adjust the rule accordingly.
- If you selected a non-root service user, you may need to log out/login or reboot for group membership changes to apply.
- To see live logs:

```bash
sudo journalctl -u aneo-led.service -f
```

If you'd like, I can:
- automatically install the unit here (I will run the installer),
- change the installer to use a specific package manager instead of pip, or
- modify the unit to write logs to a dedicated file instead of the journal.
