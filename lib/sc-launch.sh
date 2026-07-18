#!/usr/bin/env bash

# This script launches Star Citizen using Wine or Proton.
# It is meant to be used after installation via the LUG Helper.
#
# Usage:
# Run from your terminal or use the .desktop files installed by the Helper.
#
# version: 2.6
# License: GPLv3.0

############################################################################
# ENVIRONMENT VARIABLES
############################################################################
# Keep user-tunable exports grouped here for easy edits.
# Runtime-specific values are exported later in the matching runtime blocks.
############################################################################
export WINEPREFIX="$HOME/Games/star-citizen"

launch_log="$WINEPREFIX/sc-launch.log"
launcher_win_path="C:\Program Files\Roberts Space Industries\RSI Launcher\RSI Launcher.exe"
launcher_host_path="$WINEPREFIX/drive_c/Program Files/Roberts Space Industries/RSI Launcher/RSI Launcher.exe"
# Force X11/XWayland unless the user explicitly opts into a Wayland workaround below.
unset SDL_VIDEODRIVER

trace_launch_log() {
    mkdir -p "$WINEPREFIX"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$launch_log"
}

########################
# Shared (Wine + Proton)
########################
export WINEDLLOVERRIDES="winemenubuilder.exe=d" # Prevent updates from overwriting our .desktop entries
export WINEDEBUG=-all # Cut down on console debug messages
# Performance options
#export DXVK_ASYNC=1
#export WINEESYNC=1
#export WINEFSYNC=1
# Optional HUDs
#export DXVK_HUD=fps,compiler
#export MANGOHUD=1
#export MANGOHUD_CONFIG=fps,frametime,version

########################
# NVIDIA-only
########################
# Optional Nvidia shader cache tuning
#export __GL_SHADER_DISK_CACHE=1
#export __GL_SHADER_DISK_CACHE_SIZE=10737418240
#export __GL_SHADER_DISK_CACHE_PATH="$WINEPREFIX"
#export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
# Auto-enable NVAPI in Proton when Nvidia is detected.
export ENABLE_PROTON_NVAPI_AUTODETECT=1
# Manual Proton NVAPI overrides (take precedence if set)
#export PROTON_ENABLE_NVAPI=1
#export PROTON_HIDE_NVIDIA_GPU=0

########################
# AMD / Intel (Mesa)
########################
#export MESA_SHADER_CACHE_DIR="$WINEPREFIX"
#export MESA_SHADER_CACHE_MAX_SIZE="10G"

########################
# Wine-only
########################
#export STAGING_SHARED_MEMORY=1

########################
# Proton-only
########################
# Keep disabled unless troubleshooting Wayland-specific issues.
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

resolve_runner_root_from_bin_path() {
    local runner_bin_path runner_parent
    runner_bin_path="$1"

    if [ "$(basename "$runner_bin_path")" = "bin" ]; then
        runner_parent="$(dirname "$runner_bin_path")"
        if [ "$(basename "$runner_parent")" = "files" ]; then
            dirname "$runner_parent"
            return 0
        fi
        printf "%s" "$runner_parent"
        return 0
    fi

    printf "%s" "$runner_bin_path"
}

detect_system_xkb_layout() {
    local layout

    if [ -n "${XKB_DEFAULT_LAYOUT:-}" ]; then
        layout="$XKB_DEFAULT_LAYOUT"
    elif command -v setxkbmap >/dev/null 2>&1; then
        layout="$(setxkbmap -query 2>/dev/null | awk '/layout:/ {print $2; exit}')"
    elif command -v localectl >/dev/null 2>&1; then
        layout="$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/ {print $2; exit}')"
    fi

    layout="${layout%%,*}"
    printf "%s" "$(printf "%s" "$layout" | tr '[:upper:]' '[:lower:]')"
}

map_xkb_layout_to_windows_klid() {
    case "$1" in
        us) printf "00000409" ;;
        gb) printf "00000809" ;;
        de) printf "00000407" ;;
        fr) printf "0000040c" ;;
        it) printf "00000410" ;;
        es) printf "0000040a" ;;
        pt) printf "00000816" ;;
        br) printf "00000416" ;;
        ru) printf "00000419" ;;
        ua) printf "00000422" ;;
        pl) printf "00000415" ;;
        cs) printf "00000405" ;;
        tr) printf "0000041f" ;;
        fi) printf "0000040b" ;;
        se) printf "0000041d" ;;
        no) printf "00000414" ;;
        dk) printf "00000406" ;;
        hu) printf "0000040e" ;;
        ro) printf "00000418" ;;
        nl) printf "00000413" ;;
        be) printf "00000813" ;;
    esac
}

sync_windows_keyboard_layout() {
    local runtime_name proton_path xkb_layout klid

    runtime_name="$1"
    proton_path="$2"
    xkb_layout="$(detect_system_xkb_layout)"
    klid="$(map_xkb_layout_to_windows_klid "$xkb_layout")"

    if [ -z "$xkb_layout" ]; then
        trace_launch_log "keyboard-layout: could not detect system XKB layout"
        return 0
    fi

    if [ -z "$klid" ]; then
        trace_launch_log "keyboard-layout: XKB '$xkb_layout' is not mapped; leaving current Wine/Proton layout unchanged"
        return 0
    fi

    if [ "$runtime_name" = "Proton" ] && [ -n "$proton_path" ] && [ -x "$proton_path/proton" ]; then
        if env WINEPREFIX="$WINEPREFIX" \
            STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
            STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$proton_path}" \
            UMU_ID=0 \
            "$proton_path/proton" run reg add "HKCU\\Keyboard Layout\\Preload" /v 1 /t REG_SZ /d "$klid" /f >/dev/null 2>&1; then
            trace_launch_log "keyboard-layout: applied XKB '$xkb_layout' -> KLID '$klid' (Proton)"
        else
            trace_launch_log "keyboard-layout: failed to apply XKB '$xkb_layout' -> KLID '$klid' (Proton)"
        fi
    else
        if "$wine_path"/wine reg add "HKCU\\Keyboard Layout\\Preload" /v 1 /t REG_SZ /d "$klid" /f >/dev/null 2>&1; then
            trace_launch_log "keyboard-layout: applied XKB '$xkb_layout' -> KLID '$klid' (Wine)"
        else
            trace_launch_log "keyboard-layout: failed to apply XKB '$xkb_layout' -> KLID '$klid' (Wine)"
        fi
    fi
}

setup_openxr_vr_env() {
    custom_wivrn_runtime_json=""

    if [ -z "${XR_RUNTIME_JSON:-}" ]; then
        custom_wivrn_runtime_json="$(ensure_wivrn_runtime_json)"
        if [ -n "$custom_wivrn_runtime_json" ] && [ -f "$custom_wivrn_runtime_json" ]; then
            export XR_RUNTIME_JSON="$custom_wivrn_runtime_json"
        fi
    fi

    # Respect user-provided runtime settings.
    if [ -z "${XR_RUNTIME_JSON:-}" ]; then
        if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -f "${XDG_CONFIG_HOME}/openxr/1/active_runtime.json" ]; then
            export XR_RUNTIME_JSON="${XDG_CONFIG_HOME}/openxr/1/active_runtime.json"
        elif [ -f "$HOME/.config/openxr/1/active_runtime.json" ]; then
            export XR_RUNTIME_JSON="$HOME/.config/openxr/1/active_runtime.json"
        elif [ -f "/usr/share/openxr/1/openxr_wivrn.json" ]; then
            export XR_RUNTIME_JSON="/usr/share/openxr/1/openxr_wivrn.json"
        elif [ -f "/usr/share/openxr/1/openxr_monado.json" ]; then
            export XR_RUNTIME_JSON="/usr/share/openxr/1/openxr_monado.json"
        fi
    fi

    # Ensure pressure-vessel can see host OpenXR IPC sockets used by WiVRn/Monado.
    xr_rw_paths=""
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        for xr_path in "$XDG_RUNTIME_DIR/wivrn" "$XDG_RUNTIME_DIR/monado_comp_ipc"; do
            if [ -e "$xr_path" ]; then
                if [ -n "$xr_rw_paths" ]; then
                    xr_rw_paths="${xr_rw_paths}:$xr_path"
                else
                    xr_rw_paths="$xr_path"
                fi
            fi
        done
    fi

    if [ -n "$xr_rw_paths" ]; then
        if [ -n "${PRESSURE_VESSEL_FILESYSTEMS_RW:-}" ]; then
            export PRESSURE_VESSEL_FILESYSTEMS_RW="${PRESSURE_VESSEL_FILESYSTEMS_RW}:$xr_rw_paths"
        else
            export PRESSURE_VESSEL_FILESYSTEMS_RW="$xr_rw_paths"
        fi
    fi
}

ensure_wivrn_runtime_json() {
    local xr_json_out home_lib sys_lib search_path

    xr_json_out="$WINEPREFIX/xr-wivrn-runtime.json"
    home_lib="$HOME/.local/lib/wivrn/libopenxr_wivrn.so"
    sys_lib=""

    for search_path in \
        /usr/lib/wivrn/libopenxr_wivrn.so \
        /usr/lib/x86_64-linux-gnu/wivrn/libopenxr_wivrn.so \
        /usr/lib64/wivrn/libopenxr_wivrn.so \
        /usr/local/lib/wivrn/libopenxr_wivrn.so; do
        if [ -f "$search_path" ]; then
            sys_lib="$search_path"
            break
        fi
    done

    if [ -n "$sys_lib" ] && { [ ! -f "$home_lib" ] || [ "$sys_lib" -nt "$home_lib" ]; }; then
        mkdir -p "$HOME/.local/lib/wivrn"
        cp -p "$sys_lib" "$home_lib" 2>/dev/null || true
    fi

    if [ ! -f "$home_lib" ]; then
        return 1
    fi

    printf '{\n    "file_format_version": "1.0.0",\n    "runtime": {\n        "name": "WiVRn",\n        "library_path": "%s"\n    }\n}\n' "$home_lib" > "$xr_json_out"
    printf "%s" "$xr_json_out"
}

ensure_wine_vr_key() {
    local proton_path compat_client_path reg_file vk_pair vk_vid vk_pid vid_dword pid_dword

    proton_path="$1"
    if [ -z "$proton_path" ] || [ ! -x "$proton_path/proton" ]; then
        return 0
    fi

    compat_client_path="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$proton_path}"

    if env WINEPREFIX="$WINEPREFIX" \
        STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$compat_client_path" \
        UMU_ID=0 \
        "$proton_path/proton" run reg query "HKCU\\Software\\Wine\\VR" /v state >/dev/null 2>&1; then
        return 0
    fi

    reg_file="$WINEPREFIX/drive_c/wivrn_vr_init.reg"
    vk_vid=""
    vk_pid=""
    vid_dword=""
    pid_dword=""

    if command -v vulkaninfo >/dev/null 2>&1; then
        vk_pair="$(vulkaninfo --summary 2>/dev/null | awk '
            /vendorID/{vid=$3}
            /deviceID/{did=$3}
            /DISCRETE_GPU/{print vid " " did; found=1; exit}
            END{if(!found && vid && did) print vid " " did}
        ')"
        if [ -n "$vk_pair" ]; then
            vk_vid="${vk_pair%% *}"
            vk_pid="${vk_pair##* }"
        fi
    fi

    if [ -n "$vk_vid" ] && [ -n "$vk_pid" ]; then
        vid_dword="$(printf '%08x' "$((16#${vk_vid#0x}))" 2>/dev/null)"
        pid_dword="$(printf '%08x' "$((16#${vk_pid#0x}))" 2>/dev/null)"
    fi

    cat > "$reg_file" <<REGEOF
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Wine\\VR]
"openxr_vulkan_instance_extensions"="VK_KHR_external_fence_capabilities VK_KHR_external_memory_capabilities VK_KHR_external_semaphore_capabilities VK_KHR_get_physical_device_properties2"
"openxr_vulkan_device_extensions"="VK_KHR_dedicated_allocation VK_KHR_external_fence VK_KHR_external_memory VK_KHR_external_semaphore VK_KHR_get_memory_requirements2 VK_KHR_image_format_list VK_KHR_external_memory_fd VK_KHR_external_semaphore_fd VK_KHR_external_fence_fd"
"state"=dword:00000001
"is_hmd_present"=dword:00000001
REGEOF

    if [ -n "$vid_dword" ] && [ -n "$pid_dword" ]; then
        printf '"openxr_vulkan_device_vid"=dword:%s\n' "$vid_dword" >> "$reg_file"
        printf '"openxr_vulkan_device_pid"=dword:%s\n' "$pid_dword" >> "$reg_file"
    fi

    env WINEPREFIX="$WINEPREFIX" \
        STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$compat_client_path" \
        UMU_ID=0 \
        "$proton_path/proton" run regedit /s "C:\\wivrn_vr_init.reg" >/dev/null 2>&1 || true

    rm -f "$reg_file"
}

# Detect runtime from configured runner path for user-facing messages.
runtime_label="Wine"
if printf "%s" "$wine_path" | grep -qi "proton"; then
    runtime_label="Proton"
fi

# Proton-specific defaults for non-Steam prefixes created by this helper.
# These are only applied when a Proton runner is configured.
# Current helper layout uses the selected install root directly as WINEPREFIX
# and creates a compatibility pfx symlink that points back to that same root.
if [ "$runtime_label" = "Proton" ]; then
    # Required when launching Proton outside Steam with a non-Steam prefix.
    export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
    export PROTON_GAMEID="umu-starcitizen"
    export PROTONPATH="$(resolve_runner_root_from_bin_path "$wine_path")"

    # Recommended when a local Steam install exists.
    if [ -d "$HOME/.steam/steam" ]; then
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/steam}"
    elif [ -d "$HOME/.local/share/Steam" ]; then
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
    fi

    # Improve VRAM reporting on Nvidia by exposing NVAPI in Proton.
    if [ "${ENABLE_PROTON_NVAPI_AUTODETECT:-1}" = "1" ] && [ -e "/proc/driver/nvidia/version" ]; then
        export PROTON_ENABLE_NVAPI="${PROTON_ENABLE_NVAPI:-1}"
        export PROTON_HIDE_NVIDIA_GPU="${PROTON_HIDE_NVIDIA_GPU:-0}"
    fi
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

# Start a fresh launch log and preserve pre-launch traces.
: > "$launch_log"
trace_launch_log "launch-start: runtime=$runtime_label prefix=$WINEPREFIX"

############################################################################
# Launch the game
############################################################################
if [ "$runtime_label" = "Proton" ]; then
    if [ -x "$(command -v umu-run)" ]; then
        launcher_umu_target="$launcher_win_path"
        if [ -f "$launcher_host_path" ]; then
            launcher_umu_target="$launcher_host_path"
            trace_launch_log "launch-target: using host path for umu-run ($launcher_host_path)"
        else
            trace_launch_log "launch-target: host path missing, falling back to Wine path for umu-run ($launcher_win_path)"
        fi
        GAMEID="${PROTON_GAMEID:-umu-starcitizen}"
        export GAMEID
        ensure_wine_vr_key "$PROTONPATH"
        sync_windows_keyboard_layout "$runtime_label" "$PROTONPATH"
        setup_openxr_vr_env
        umu-run "$launcher_umu_target" >> "$launch_log" 2>&1
    else
        echo "Proton runner detected, but umu-run is not installed. Falling back to direct runner launch." >&2
        trace_launch_log "launch-warning: umu-run missing, using direct Wine command with Proton runner"
        sync_windows_keyboard_layout "$runtime_label" "$PROTONPATH"
        "$wine_path"/wine "$launcher_win_path" >> "$launch_log" 2>&1
    fi
else
    sync_windows_keyboard_layout "$runtime_label" ""
    "$wine_path"/wine "$launcher_win_path" >> "$launch_log" 2>&1
fi
