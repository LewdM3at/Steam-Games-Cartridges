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

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)

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
echo "  launch.sh"
echo ""
echo "Example:"
echo ""
echo "  #!/bin/bash"
echo "  steam steam://rungameid/12345"
echo ""
echo "The SSD must be automatically mounted by"
echo "your desktop environment."
echo ""
echo "If your distro does not automount drives,"
echo "configure automount manually or install"
echo "a tool such as udiskie."
echo ""
echo "Create a 'launch.sh' script on the cartridge and trust it with 'trust-script-linux.sh'"
echo "Then re-insert the cartridge to test."
echo ""