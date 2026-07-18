#!/usr/bin/env bash

# This script launches Star Citizen using Wine or Proton.
# It is meant to be used after installation via the LUG Helper.
#
# Usage:
# Run from your terminal or use the .desktop files installed by the Helper.
#
# version: 2.8
# License: GPLv3.0

############################################################################
# ENVIRONMENT VARIABLES
############################################################################
# Only keep broadly safe defaults enabled here.
# Proton-required variables are applied further below when a Proton runner is detected.
# Optional GPU- or Wayland-specific overrides are listed disabled by default.
############################################################################
export WINEPREFIX="$HOME/Games/star-citizen"

launch_log="$WINEPREFIX/sc-launch.log"
# Force X11/XWayland unless the user explicitly opts into a Wayland workaround below.
unset SDL_VIDEODRIVER

export WINEDLLOVERRIDES="winemenubuilder.exe=d" # Prevent updates from overwriting our .desktop entries
export WINEDEBUG=-all # Cut down on console debug messages

# Optional Nvidia shader cache tuning
#export __GL_SHADER_DISK_CACHE=1
#export __GL_SHADER_DISK_CACHE_SIZE=10737418240
#export __GL_SHADER_DISK_CACHE_PATH="$WINEPREFIX"
#export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1

# Optional Mesa shader cache tuning (AMD/Intel)
#export MESA_SHADER_CACHE_DIR="$WINEPREFIX"
#export MESA_SHADER_CACHE_MAX_SIZE="10G"

# Performance options
#export DXVK_ASYNC=1
#export WINEESYNC=1
#export WINEFSYNC=1
# Optional HUDs
#export DXVK_HUD=fps,compiler
#export MANGOHUD=1

# Optional Wayland workarounds
# Keep these disabled unless you are troubleshooting a specific Wayland issue.
#export SDL_VIDEODRIVER=wayland
#export PROTON_ENABLE_WAYLAND=1

############################################################################
# END ENVIRONMENT VARIABLES
############################################################################

####################
# Runtime binary path
####################
# To use a custom runner, set the path to its bin directory
# export wine_path="/path/to/custom/runner/bin"
export wine_path="$(command -v wine | xargs dirname)"

# Detect runtime from configured runner path for user-facing messages.
runtime_label="Wine"
if printf "%s" "$wine_path" | grep -qi "proton"; then
    runtime_label="Proton"
fi

# Proton-specific defaults for non-Steam prefixes created by this helper.
# These are only applied when a Proton runner is configured.
if [ "$runtime_label" = "Proton" ]; then
    # Required when launching Proton outside Steam with a non-Steam prefix.
    export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"

    # Recommended when a local Steam install exists.
    if [ -d "$HOME/.steam/steam" ]; then
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/steam}"
    elif [ -d "$HOME/.local/share/Steam" ]; then
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
    fi

    # Optional Proton tuning examples
    #export PROTON_ENABLE_NVAPI=1
    #export PROTON_HIDE_NVIDIA_GPU=0
fi

########################
# Command line arguments
########################
# shell - Drop into a Wine maintenance shell
# config - Wine configuration
# controllers - Game controller configuration
# Usage: ./sc-launch.sh shell
case "$1" in
    "shell")
        echo "Entering ${runtime_label} prefix maintenance shell. Type 'exit' when done."
        export PATH="$wine_path:$PATH"; export PS1="${runtime_label}: "
        cd "$WINEPREFIX"; pwd; /usr/bin/env bash --norc; exit 0
        ;;
    "config")
        /usr/bin/env bash --norc -c "\"${wine_path}\"/wine winecfg"; exit 0
        ;;
    "controllers")
        /usr/bin/env bash --norc -c "\"${wine_path}\"/wine control joy.cpl"; exit 0
        ;;
esac

##########################
# Update check and cleanup
##########################
# Kill existing wine processes before launch
update_check() {
    while "$wine_path"/winedbg --command "info proc" | grep -qi "rsi.*setup"; do
        echo "RSI Setup process detected. Exiting."; exit 0
    done
}
"$wine_path"/wineserver -k

############################################################################
# Launch the game
############################################################################
"$wine_path"/wine "C:\Program Files\Roberts Space Industries\RSI Launcher\RSI Launcher.exe" > "$launch_log" 2>&1
