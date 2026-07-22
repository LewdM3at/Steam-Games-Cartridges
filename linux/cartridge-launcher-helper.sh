#!/bin/bash

set -e

DEVICE="$1"

TRUST_DIR="$HOME/.config/pc-cartridge-system"
TRUST_FILE="$TRUST_DIR/trusted_scripts.sha256"
CONFIG_FILE="$TRUST_DIR/settings.conf"

echo "Game cartridge detected: $DEVICE"


# Wait for desktop automounter
MOUNT_POINT=""

for i in {1..60}; do

    MOUNT_POINT=$(findmnt -n -o TARGET "/dev/$DEVICE" 2>/dev/null || true)

    if [ -n "$MOUNT_POINT" ]; then
        break
    fi

    sleep 0.5

done


if [ -z "$MOUNT_POINT" ]; then
    echo "No mount point found for /dev/$DEVICE"
    exit 0
fi


echo "Mounted at: $MOUNT_POINT"


SCRIPT="$MOUNT_POINT/launch.sh"


if [ ! -f "$SCRIPT" ]; then
    echo "No launch.sh found on cartridge"
    exit 0
fi

# Check auto-launch mode
if [ -f "$CONFIG_FILE" ]; then

    MODE=$(grep "^MODE=" "$CONFIG_FILE" | cut -d '=' -f2)

    if [ "$MODE" != "running" ]; then

        echo "Cartridge execution is disabled."
        echo "Current mode: $MODE"
        echo "Skipping launch."

        exit 0

    fi

else

    echo "No settings file found."
    echo "Defaulting to blocked mode."

    exit 0

fi


echo "Found launch.sh"


# Check trusted scripts database exists
if [ ! -f "$TRUST_FILE" ]; then
    echo "No trusted scripts database found."
    echo "Cartridge blocked."
    exit 0
fi


# Calculate hash
SCRIPT_HASH=$(sha256sum "$SCRIPT" | awk '{print $1}')

echo "Script SHA256:"
echo "$SCRIPT_HASH"


# Check trust database
if grep -qx "$SCRIPT_HASH" "$TRUST_FILE"; then

    echo "Script is trusted."
    echo "Launching cartridge..."

    chmod +x "$SCRIPT"
    bash "$SCRIPT" > "$TRUST_DIR/cartridge.log" 2>/dev/null

else

    echo "Script is NOT trusted."
    echo "Cartridge blocked."

fi