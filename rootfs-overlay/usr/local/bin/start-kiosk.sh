#!/bin/sh
. /etc/env.conf
set -e

# Load GPU detection + env exports
. /usr/local/bin/detect-gpu.sh

# Tell libseat to use seatd directly — avoids wasting time probing logind
# (which doesn't exist on Alpine/OpenRC)
export LIBSEAT_BACKEND=seatd

# XDG runtime dir — /run/user must be created by root at boot (see tmpfiles/openrc)
# We create it here as a fallback if it wasn't pre-created
UID=$(id -u)
export XDG_RUNTIME_DIR="/run/user/$UID"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    # Try with sudo/su-exec, fall back to direct (works if we're root or dir is writable)
    mkdir -p "/run/user" 2>/dev/null || true
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || {
        # Last resort: use /tmp
        export XDG_RUNTIME_DIR="/tmp/runtime-$UID"
        mkdir -p "$XDG_RUNTIME_DIR"
    }
fi
chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Session D-Bus
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

allclear=true

# Retry loop — if xemu crashes, cage exits and we restart
if [ ! -f $XEMUHDD_IMGDIR ]; then
    dialog --title "Error" --msgbox "Xbox HDD Image not found at $XEMUHDD_IMGDIR\nPlease make sure to add it before booting." 8 60
    allclear=false
fi
if [ ! -f $XEMUMCPX_IMGDIR ]; then
    dialog --title "Error" --msgbox "Xbox MCPX Image not found at $XEMUMCPX_IMGDIR\nPlease make sure to add it before booting." 8 60
    allclear=false
fi
if [ ! -f $XEMUBIOS_IMGDIR ]; then
    dialog --title "Error" --msgbox "Xbox BIOS Image not found at $XEMUBIOS_IMGDIR\nPlease make sure to add it before booting." 8 60
    allclear=false
fi

if [ $allclear = false ]; then
    su -c poweroff
fi


while true; do
    cage -s -- /usr/local/bin/launch-xemu.sh
    logger -t $kioskusername "xemu exited, restarting in 2s..." 2>/dev/null || true
    sleep 2
done