#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run this installer with sudo."
    exit 1
fi

echo "Installing Steam Game Cartridge launcher..."

# Check for important files

for FILE in \
    "linux/cartridge-launcher-helper.sh" \
    "linux/game-cartridge@.service" \
    "linux/99-game-cartridge.rules"
do
    if [ ! -f "$FILE" ]; then
        echo "Missing file: $FILE"
        exit 1
    fi
done

########################################
# Detect user
########################################

if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME="$USER"
fi

USER_HOME=$(eval echo "~$USERNAME")

echo "Installing for user: $USERNAME"
echo "Home directory: $USER_HOME"


########################################
# Install launcher helper
########################################

echo "Installing launcher helper..."

install -m 755 linux/cartridge-launcher-helper.sh /usr/local/bin/cartridge-launcher-helper


########################################
# Install systemd template
########################################

echo "Installing systemd service..."

sed "s/__USERNAME__/$USERNAME/g" \
    "linux/game-cartridge@.service" \
    > /etc/systemd/system/game-cartridge@.service


########################################
# Install udev rule
########################################

echo "Installing udev rule..."

install -m 644 linux/99-game-cartridge.rules /etc/udev/rules.d/99-steam-game-cartridge.rules


########################################
# Reload services
########################################

systemctl daemon-reload

udevadm control --reload-rules

udevadm trigger


########################################
# Done
########################################

echo ""
echo "=========================================="
echo " Steam Game Cartridge installed"
echo "=========================================="
echo ""
echo "Create cartridges with:"
echo ""
echo "  cartridge.json"
echo ""
echo "Example:"
echo ""
echo "  {"
echo '    "version": 1,'
echo '    "name": "Cyberpunk 2077",'
echo '    "action": "run",'
echo '    "steamAppId": "1091500",'
echo '    "hashValidationEnabled": false'
echo "  }"
echo ""
echo "The SSD must be automatically mounted by"
echo "your desktop environment."
echo ""
echo "The cartridge must contain:"
echo ""
echo "  cartridge.json"
echo "  SteamLibrary/steamapps/appmanifest_<steamAppId>.acf"
echo ""
echo "If your distro does not automount drives,"
echo "configure automount manually or install"
echo "a tool such as udiskie."
echo ""
echo "Insert a cartridge SSD to test."
echo ""
