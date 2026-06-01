#!/bin/bash

# ============================================================
#  fix-touch.sh — Map external touchscreen to correct monitor
#                 on GNOME Wayland (Arch Linux)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Fix Touchscreen Monitor — GNOME       ${NC}"
echo -e "${CYAN}========================================${NC}\n"

# --- 1. Check dependencies ---
for cmd in libinput gsettings; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}ERROR: '$cmd' not found. Install with: sudo pacman -S libinput glib2${NC}"
        exit 1
    fi
done

MONITORS_XML="$HOME/.config/monitors.xml"
if [ ! -f "$MONITORS_XML" ]; then
    echo -e "${RED}ERROR: $MONITORS_XML not found.${NC}"
    echo "Connect the external monitor and configure displays in GNOME Settings before running this script."
    exit 1
fi

# --- 2. List available monitors (excluding internal eDP) ---
echo -e "${YELLOW}Monitors found in monitors.xml:${NC}\n"

mapfile -t VENDORS    < <(grep -oP '(?<=<vendor>)[^<]+' "$MONITORS_XML")
mapfile -t PRODUCTS   < <(grep -oP '(?<=<product>)[^<]+' "$MONITORS_XML")
mapfile -t SERIALS    < <(grep -oP '(?<=<serial>)[^<]+' "$MONITORS_XML")
mapfile -t CONNECTORS < <(grep -oP '(?<=<connector>)[^<]+' "$MONITORS_XML")

declare -a EXT_IDX=()
for i in "${!CONNECTORS[@]}"; do
    echo -e "  [$i] ${CYAN}${CONNECTORS[$i]}${NC} — ${VENDORS[$i]} ${PRODUCTS[$i]} (serial: ${SERIALS[$i]})"
    if [[ "${CONNECTORS[$i]}" != eDP* ]]; then
        EXT_IDX+=($i)
    fi
done

echo ""

# Auto-select if only one external monitor is found
if [ ${#EXT_IDX[@]} -eq 1 ]; then
    SEL=${EXT_IDX[0]}
    echo -e "${GREEN}External monitor auto-detected: ${CONNECTORS[$SEL]} — ${VENDORS[$SEL]} ${PRODUCTS[$SEL]}${NC}"
else
    read -rp "Enter the number of the external touch monitor (e.g. 0, 1, 2): " SEL
fi

MON_VENDOR="${VENDORS[$SEL]}"
MON_PRODUCT="${PRODUCTS[$SEL]}"
MON_SERIAL="${SERIALS[$SEL]}"

echo -e "\n${YELLOW}Target monitor:${NC} $MON_VENDOR | $MON_PRODUCT | $MON_SERIAL"

# --- 3. Detect touch device ---
echo -e "\n${YELLOW}Looking for touchscreen devices...${NC}\n"

TOUCH_DEVICES=$(sudo libinput list-devices 2>/dev/null | awk '
    /^Device:/ { dev=$0 }
    /Capabilities:.*touch/ { print dev }
' | sed 's/Device: *//')

if [ -z "$TOUCH_DEVICES" ]; then
    echo -e "${YELLOW}Trying via /proc/bus/input/devices...${NC}"
    TOUCH_DEVICES=$(grep -B5 'ABS_MT\|EV=.*d' /proc/bus/input/devices 2>/dev/null | grep "Name=" | sed 's/.*Name="\(.*\)"/\1/' || true)
fi

if [ -z "$TOUCH_DEVICES" ]; then
    echo -e "${RED}ERROR: No touchscreen device found.${NC}"
    exit 1
fi

echo -e "${GREEN}Touchscreen(s) found:${NC}"
echo "$TOUCH_DEVICES"

# --- 4. Identify Vendor:Product ID from /proc ---
echo -e "\n${YELLOW}Identifying touchscreen Vendor:Product ID...${NC}"

TOUCH_ID=""

while IFS= read -r line; do
    SYSFS_PATH=$(sudo libinput list-devices 2>/dev/null | grep -A20 "$line" | grep "Kernel:" | head -1 | awk '{print $2}')
    if [ -n "$SYSFS_PATH" ]; then
        EVENT=$(basename "$SYSFS_PATH")
        UEVENT=$(find /sys/class/input/$EVENT/ -name uevent 2>/dev/null | head -1)
        if [ -n "$UEVENT" ]; then
            VID=$(grep 'ID_VENDOR_ID\|HID_ID' "$UEVENT" 2>/dev/null | head -1 | grep -oP '[0-9a-fA-F]{4}' | head -1 | tr '[:upper:]' '[:lower:]')
            PID=$(grep 'ID_VENDOR_ID\|HID_ID' "$UEVENT" 2>/dev/null | head -1 | grep -oP '[0-9a-fA-F]{4}' | tail -1 | tr '[:upper:]' '[:lower:]')
            if [ -n "$VID" ] && [ -n "$PID" ]; then
                TOUCH_ID="${VID}:${PID}"
            fi
        fi
    fi
done <<< "$TOUCH_DEVICES"

# Fallback: look up via lsusb
if [ -z "$TOUCH_ID" ]; then
    echo -e "${YELLOW}Could not auto-detect ID. Showing lsusb output:${NC}\n"
    lsusb
    echo ""
    read -rp "Paste the Vendor:Product ID of your touchscreen (e.g. 04f3:2d4a): " TOUCH_ID
fi

if [ -z "$TOUCH_ID" ]; then
    echo -e "${RED}ERROR: Could not determine touchscreen ID.${NC}"
    read -rp "Enter Vendor:Product ID manually (e.g. 04f3:2d4a): " TOUCH_ID
fi

TOUCH_ID=$(echo "$TOUCH_ID" | tr '[:upper:]' '[:lower:]')
echo -e "${GREEN}Touch device ID: $TOUCH_ID${NC}"

SCHEMA_PATH="/org/gnome/desktop/peripherals/touchscreens/${TOUCH_ID}/"

# --- 5. Show current mapping ---
echo -e "\n${YELLOW}Current touchscreen mapping:${NC}"
gsettings list-recursively "org.gnome.desktop.peripherals.touchscreen:${SCHEMA_PATH}" 2>/dev/null || \
    echo "(no previous configuration found)"

# --- 6. Apply mapping ---
echo -e "\n${YELLOW}Applying mapping...${NC}"
echo -e "  Schema:  org.gnome.desktop.peripherals.touchscreen:${SCHEMA_PATH}"
echo -e "  Output:  ['$MON_VENDOR', '$MON_PRODUCT', '$MON_SERIAL']"

gsettings set "org.gnome.desktop.peripherals.touchscreen:${SCHEMA_PATH}" \
    output "['$MON_VENDOR', '$MON_PRODUCT', '$MON_SERIAL']"

# --- 7. Confirm ---
echo -e "\n${YELLOW}Applied configuration:${NC}"
gsettings list-recursively "org.gnome.desktop.peripherals.touchscreen:${SCHEMA_PATH}"

echo -e "\n${GREEN}✓ Done! Touch input should now go to the external monitor.${NC}"
echo -e "${CYAN}If it doesn't work immediately, log out and log back in.${NC}\n"

# --- 8. Optional: create systemd user service for autostart ---
read -rp "Create a systemd user service to apply this automatically on every login? [y/N] " AUTOSTART
if [[ "$AUTOSTART" =~ ^[Yy]$ ]]; then
    SCRIPT_PATH="$HOME/.local/bin/fix-touch.sh"
    mkdir -p "$HOME/.local/bin"
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_DIR/fix-touch.service" << SVCEOF
[Unit]
Description=Fix touchscreen monitor mapping
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH --auto
Environment=DISPLAY=:0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus

[Install]
WantedBy=graphical-session.target
SVCEOF

    systemctl --user daemon-reload
    systemctl --user enable fix-touch.service
    echo -e "${GREEN}✓ Service created and enabled!${NC}"
fi
