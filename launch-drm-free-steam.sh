#!/bin/bash

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


##### CONFIGURE HERE #####
OVERRIDE_EXE=FALSE   #TRUE/FALSE
GAME_EXE="$ROOT/SteamLibrary/steamapps/common/Cyberpunk 2077/bin/x64/Cyberpunk2077.exe"
##### CONFIGURE HERE #####

# ==========================================
# Restore graphical session environment
# ==========================================

echo "Detecting graphical session..."

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"


# Import user systemd environment
if command -v systemctl >/dev/null; then

    while IFS= read -r line; do
        export "$line"
    done < <(systemctl --user show-environment)

fi


# Fallback: detect Wayland socket
if [ -z "$WAYLAND_DISPLAY" ]; then
    WAYLAND_DISPLAY=$(find "$XDG_RUNTIME_DIR" \
        -maxdepth 1 \
        -name "wayland-*" \
        -printf "%f\n" \
        | head -1)

    export WAYLAND_DISPLAY
fi


# Fallback: detect X11
if [ -z "$DISPLAY" ] && [ -S "/tmp/.X11-unix/X0" ]; then
    export DISPLAY=:0
fi


echo "Environment:"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "DISPLAY=$DISPLAY"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"


# ==========================================
# Proton standalone launcher
# ==========================================



echo "Launcher root: $ROOT"
echo


# ------------------------------------------
# Find compatdata folder
# ------------------------------------------

COMPATDATA_DIR=$(find "$ROOT" -type d -name "compatdata" -print -quit)

if [ -z "$COMPATDATA_DIR" ]; then
    echo "ERROR: Could not find compatdata folder"
    exit 1
fi

echo "Compatdata: $COMPATDATA_DIR"
echo


# ------------------------------------------
# Find game ID folder
# ------------------------------------------

GAME_COMPAT_DIR=$(find "$COMPATDATA_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -print -quit)

if [ -z "$GAME_COMPAT_DIR" ]; then
    echo "ERROR: No game ID folder inside compatdata"
    exit 1
fi

GAME_ID=$(basename "$GAME_COMPAT_DIR")

echo "Game ID: $GAME_ID"
echo


# ------------------------------------------
# Find Proton installation from config_info
# ------------------------------------------

CONFIG_FILE="$GAME_COMPAT_DIR/config_info"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config_info not found:"
    echo "$CONFIG_FILE"
    exit 1
fi


PROTON_LIB_PATH=$(grep "/steamapps/common/.*files/lib/" "$CONFIG_FILE" | head -1)


if [ -z "$PROTON_LIB_PATH" ]; then
    echo "ERROR: Could not find Proton path in config_info"
    exit 1
fi


# Convert:
# /home/user/.local/share/Steam/steamapps/common/Proton - Experimental/files/lib/
#
# into:
# /home/user/.local/share/Steam/steamapps/common/Proton - Experimental/

PROTON_DIR=$(echo "$PROTON_LIB_PATH" | sed 's|\(.*steamapps/common/[^/]*/\).*|\1|')


if [ ! -f "$PROTON_DIR/proton" ]; then
    echo "ERROR: Proton executable not found:"
    echo "$PROTON_DIR/proton"
    exit 1
fi


echo "Proton: $PROTON_DIR"
echo


# ------------------------------------------
# Find game executable
# ------------------------------------------

if [ "$OVERRIDE_EXE" = "TRUE" ]; then

    if [ ! -f "$GAME_EXE" ]; then
        echo "ERROR: Override executable not found:"
        echo "$GAME_EXE"
        exit 1
    fi

else

    GAME_EXE=$(find "$ROOT" \
        -type f \
        -iname "*.exe" \
        ! -path "*/compatdata/*" \
        -print \
        -quit)

    if [ -z "$GAME_EXE" ]; then
        echo "ERROR: Could not automatically find game executable"
        exit 1
    fi

fi


echo "Game executable: $GAME_EXE"
echo


# ------------------------------------------
# Proton environment
# ------------------------------------------

STEAM_PATH=$(echo "$PROTON_DIR" | sed 's|\(/steamapps/common/.*\)||')

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_PATH"
export STEAM_COMPAT_DATA_PATH="$GAME_COMPAT_DIR"
export STEAM_COMPAT_TOOL_PATH="$PROTON_DIR"
export PROTON_ENABLE_WAYLAND=0


# Optional but useful
export PROTON_LOG=0


echo "Launching game..."
echo


# ------------------------------------------
# Launch
# ------------------------------------------

cd "$(dirname "$GAME_EXE")"
"$PROTON_DIR/proton" run "$GAME_EXE"
