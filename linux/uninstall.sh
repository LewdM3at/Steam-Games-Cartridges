#!/bin/bash

set -e

echo "Uninstalling PC Cartridge System..."

########################################
# Check root
########################################

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi


########################################
# Stop running services
########################################

echo "Stopping cartridge services..."

systemctl stop 'game-cartridge@*' 2>/dev/null || true


########################################
# Remove launcher helper
########################################

echo "Removing launcher helper..."

rm -f /usr/local/bin/cartridge-launcher-helper
rm -f /usr/local/bin/pc-cartridge-system-helper


########################################
# Remove systemd service
########################################

echo "Removing systemd service..."

rm -f /etc/systemd/system/game-cartridge@.service


########################################
# Remove udev rule
########################################

echo "Removing udev rule..."

rm -f /etc/udev/rules.d/99-steam-game-cartridge.rules
rm -f /etc/udev/rules.d/99-game-cartridge.rules

#######################################################################
# Remove steam-games-cartridges config directory in User's HOME
#######################################################################

if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME="$USER"
fi

USER_HOME=$(eval echo "~$USERNAME")

echo "Removing config directory..."

rm -rf "$USER_HOME/.config/steam-games-cartridges"
rm -rf "$USER_HOME/.config/pc-cartridge-system"


########################################
# Reload services
########################################

echo "Reloading system services..."

systemctl daemon-reload
systemctl reset-failed

udevadm control --reload-rules
udevadm trigger


########################################
# Done
########################################

echo ""
echo "=========================================="
echo " PC Cartridge System removed"
echo "=========================================="
echo ""