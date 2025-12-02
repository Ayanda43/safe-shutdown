# Safe Shutdown Service for RevPi

A self-installing systemd service that monitors a digital input and triggers a safe shutdown sequence with on-screen display message for Revolution Pi devices.

## Features

- Monitors digital input for falling edge (1→0 transition)
- Displays "SHUTTING DOWN" message on screen (framebuffer)
- Sends trigger pulse to timer relay
- Activates relay coil output
- Stops display services (lightdm, startx, etc.)
- Auto-configures based on hostname (lnk*/tnk*)
- Self-installing systemd service
- Downloads required font automatically

## Configuration

The script auto-configures based on hostname:

| Hostname | Input | Trigger Count | Relay Coil |
|----------|-------|---------------|------------|
| `lnk*`   | I_6   | O_11          | O_12       |
| `tnk*`   | I_7   | O_1           | O_12       |

## Circuit Diagram

![PLC Timer Relay Circuit](plc-timer-relay-circuit.svg)

## Installation

```bash
./shutdown_service.sh
```

First run will:
1. Download the Arian LT Bold font
2. Create the systemd service file
3. Enable the service to start on boot
4. Start the service in background

## Uninstall

```bash
./shutdown_service.sh uninstall
```

## Usage

### Service Commands

```bash
# Check status
systemctl status shutdown-monitor

# View logs
journalctl -u shutdown-monitor -f

# Stop service
sudo systemctl stop shutdown-monitor

# Start service
sudo systemctl start shutdown-monitor

# Restart (to apply script changes)
sudo systemctl restart shutdown-monitor

# Disable auto-start
sudo systemctl disable shutdown-monitor
```

## Behavior

1. **On startup**: Activates relay coil (O_12) immediately
2. **Monitors** the configured input at 100ms intervals
3. **On falling edge** (input goes from 1 to 0):
   - Displays "SHUTTING DOWN" message (red text, centered, rotated for portrait display)
   - Sends a pulse to the trigger count output (starts timer relay)
   - Activates the relay coil output
   - Stops display services (`startx.service`, `cmdr-field.service`, `lightdm.service`)

## Display Configuration

The shutdown message can be customized by editing the Python section in `shutdown_service.sh`:

- `TEXT_COLOR` - Text color (e.g., "red", "white", "#FF0000")
- `FONT_SIZE` - Font size in pixels
- `ROTATION` - Screen rotation in degrees
- `SCREEN_WIDTH` / `SCREEN_HEIGHT` - Display dimensions

## Requirements

- RevPi with piTest tool
- Python 3 with PIL/Pillow
- fbi (framebuffer image viewer)
- wget (for font download)

## Files

- `shutdown_service.sh` - Main script (auto-installs service)
- `/home/developer/fonts/Arian-LT-Bold.ttf` - Font file (downloaded during setup)
- `/etc/systemd/system/shutdown-monitor.service` - Systemd unit (auto-created)

## License

MIT
