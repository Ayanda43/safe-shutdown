#!/bin/bash
# Shutdown Service
# Monitors a digital input based on hostname and triggers timer relay actions on falling edge
# Creates/updates its own systemd service on first run if not already installed

SERVICE_NAME="shutdown-monitor"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_PATH="/home/developer/shutdown_service.sh"
FONT_DIR="/home/developer/fonts"
FONT_FILE="${FONT_DIR}/Arian-LT-Bold.ttf"
FONT_URL="https://db.onlinewebfonts.com/t/7583a571c6edf39e350bac12619613b5.ttf"

# === UNINSTALL ===
if [[ "$1" == "uninstall" ]]; then
    echo "Uninstalling ${SERVICE_NAME} service..."
    sudo systemctl stop "${SERVICE_NAME}.service" 2>/dev/null
    sudo systemctl disable "${SERVICE_NAME}.service" 2>/dev/null
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Service uninstalled."
    exit 0
fi

# === AUTO-INSTALL SERVICE IF NOT EXISTS ===
if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "Service not installed. Installing..."

    # Download font if not exists
    if [[ ! -f "$FONT_FILE" ]]; then
        echo "Downloading Arian LT Bold font..."
        mkdir -p "$FONT_DIR"
        wget -q -O "$FONT_FILE" "$FONT_URL" || echo "Warning: Could not download font"
    fi

    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Shutdown Monitor Service - Monitors digital input for timer relay trigger
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash ${SCRIPT_PATH}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo chmod +x "$SCRIPT_PATH"
    sudo systemctl daemon-reload
    sudo systemctl enable "${SERVICE_NAME}.service"
    sudo systemctl start "${SERVICE_NAME}.service"
    echo "Service installed, enabled and started in background."
    echo "Check status: systemctl status ${SERVICE_NAME}"
    echo "View logs: journalctl -u ${SERVICE_NAME} -f"
    exit 0
fi

# === CONFIGURATION BASED ON HOSTNAME ===
HOSTNAME=$(hostname)
PREVIOUS_STATE=""
PULSE_DURATION=0.5

if [[ "$HOSTNAME" == lnk* ]]; then
    INPUT="I_6"
    OUTPUT_TRIGGER="O_11"
    OUTPUT_RELAY="O_12"
    echo "Configured for LNK device: Input=$INPUT, TriggerOutput=$OUTPUT_TRIGGER, RelayOutput=$OUTPUT_RELAY"
elif [[ "$HOSTNAME" == tnk* ]]; then
    INPUT="I_7"
    OUTPUT_TRIGGER="O_1"
    OUTPUT_RELAY="O_12"
    echo "Configured for TNK device: Input=$INPUT, TriggerOutput=$OUTPUT_TRIGGER, RelayOutput=$OUTPUT_RELAY"
else
    echo "Unknown hostname pattern: $HOSTNAME. Exiting."
    exit 1
fi

# === FUNCTIONS ===
read_input() {
    piTest -q -1 -r "$INPUT" 2>/dev/null
}

send_trigger_pulse() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sending trigger pulse to $OUTPUT_TRIGGER"
    piTest -w "$OUTPUT_TRIGGER,1" 2>/dev/null
    sleep "$PULSE_DURATION"
    piTest -w "$OUTPUT_TRIGGER,0" 2>/dev/null
}

activate_relay() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Activating relay coil $OUTPUT_RELAY"
    piTest -w "$OUTPUT_RELAY,1" 2>/dev/null
}

display_shutdown_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Displaying shutdown message on screen"
    # Create shutdown image with Python and display with fbi
    python3 - << 'PYTHON_SCRIPT'
from PIL import Image, ImageDraw, ImageFont

# Configuration
TEXT_COLOR = "red"  # Can be: red, white, yellow, orange, or hex like "#FF0000"
FONT_PATH = "/home/developer/fonts/Arian-LT-Bold.ttf"
FONT_SIZE = 180
ROTATION = -270  # Rotation in degrees

# Final screen dimensions (after rotation)
SCREEN_WIDTH = 1080
SCREEN_HEIGHT = 1920

# For -270 or 90 degree rotation, swap dimensions for the initial canvas
if ROTATION in [-270, 90, -90, 270]:
    canvas_width, canvas_height = SCREEN_HEIGHT, SCREEN_WIDTH
else:
    canvas_width, canvas_height = SCREEN_WIDTH, SCREEN_HEIGHT

img = Image.new('RGB', (canvas_width, canvas_height), color='black')
draw = ImageDraw.Draw(img)

# Load font
try:
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
except:
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", FONT_SIZE)
    except:
        font = ImageFont.load_default()

text = "SHUTTING DOWN"
x = canvas_width // 2
y = canvas_height // 2

draw.text((x, y), text, fill=TEXT_COLOR, font=font, anchor="mm")

# Rotate
img = img.rotate(ROTATION, expand=True)

img.save('/tmp/shutdown_screen.png')
PYTHON_SCRIPT

    # Display image on framebuffer
    sudo fbi -T 1 -d /dev/fb0 --noverbose -a /tmp/shutdown_screen.png 2>/dev/null &
}

perform_shutdown_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Performing shutdown actions..."
    # Display shutdown message first
    display_shutdown_message
    sleep 1
    # Stop services
    systemctl stop startx.service 2>/dev/null || echo "Warning: Could not stop startx.service"
    systemctl stop cmdr-field.service 2>/dev/null || echo "Warning: Could not stop cmdr-field.service"
    systemctl stop lightdm.service 2>/dev/null || echo "Warning: Could not stop lightdm.service"
}

cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Shutdown monitor service stopping..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# === MAIN LOOP ===
echo "$(date '+%Y-%m-%d %H:%M:%S') - Shutdown monitor service started on $HOSTNAME"
echo "Monitoring input $INPUT for falling edge (1->0 transition)"

# Activate relay coil on start
echo "$(date '+%Y-%m-%d %H:%M:%S') - Activating relay coil $OUTPUT_RELAY on startup"
piTest -w "$OUTPUT_RELAY,1" 2>/dev/null

PREVIOUS_STATE=$(read_input)
echo "Initial input state: $PREVIOUS_STATE"

while true; do
    CURRENT_STATE=$(read_input)

    # Falling edge detection (1 -> 0)
    if [[ "$PREVIOUS_STATE" == "1" && "$CURRENT_STATE" == "0" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Falling edge detected on $INPUT!"
        send_trigger_pulse
        activate_relay
        perform_shutdown_action
    fi

    PREVIOUS_STATE="$CURRENT_STATE"
    sleep 0.1
done
