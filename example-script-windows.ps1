
##########################################################################################
#   Edit the actions here. What should happen after the Cartridge has been plugged in    #
##########################################################################################
# Put this script on your SSD at root level and name it "launch.ps1" (without quotes).
# The script will be executed when the Cartridge is plugged in.


# Navigate to game's page
Start-Process "steam://nav/games/details/1091500"

# Runs the game, will be installed if necessary
Start-Process "steam://run/1091500"

# Same as run, but with support for mods and non-Steam shortcuts.
#Start-Process "steam://rungameid/1091500"

# Same as run, but with support for multiple launch options.
#Start-Process "steam://launch/1091500"

# For other Steam URL Protocol commands check the documentation:
# https://developer.valvesoftware.com/wiki/Steam_browser_protocol