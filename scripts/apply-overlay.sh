#!/bin/bash
# =============================================================================
# apply-overlay.sh — Write all config files into the rootfs
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# ── Copy static overlay files
info "Copying rootfs overlay files..."
rsync -aAX "$OVERLAY_DIR/" "$ROOTFS_DIR/"

# ── /etc/inittab — auto-login user on tty1
info "Configuring auto-login..."
# Append autologin for tty1 (replace existing tty1 line if present)
if grep -q "tty1" "$ROOTFS_DIR/etc/inittab" 2>/dev/null; then
    sed -i "s|^tty1.*|tty1::respawn:/sbin/agetty --autologin $kioskusername --noclear tty1 linux|" \
        "$ROOTFS_DIR/etc/inittab"
else
    echo "tty1::respawn:/sbin/agetty --autologin $kioskusername --noclear tty1 linux" \
        >> "$ROOTFS_DIR/etc/inittab"
fi

# ── /home/<kioskusername>/.profile — start compositor on tty1
rootfs_write /home/$kioskuserhome/.profile <<'EOF'
# Auto-start kiosk on tty1
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    exec /usr/local/bin/start-kiosk.sh
fi
EOF
rootfs_write /home/$kioskuserhome/.bash_profile <<'EOF'
. ~/.profile
EOF

# ── /usr/local/bin/detect-gpu.sh
rootfs_write /usr/local/bin/detect-gpu.sh <<'EOF'
#!/bin/sh
# GPU detection and environment setup
# Sourced by start-kiosk.sh before launching cage/xemu

detect_gpu() {
    # Prefer proprietary Nvidia if module loaded
    if lsmod 2>/dev/null | grep -q "^nvidia "; then
        export GBM_BACKEND=nvidia-drm
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
        export WLR_NO_HARDWARE_CURSORS=1
        export WLR_RENDERER=gles2
        GPU_NAME="nvidia-proprietary"
        return 0
    fi

    # AMD
    if lspci 2>/dev/null | grep -qi "amd\|radeon\|amdgpu"; then
        export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
        export AMD_VULKAN_ICD=RADV
        export WLR_RENDERER=vulkan
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
        GPU_NAME="amd"
        return 0
    fi

    # Intel
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*uhd\|intel.*hd graphics\|intel.*iris"; then
        export MESA_LOADER_DRIVER_OVERRIDE=iris
        export WLR_RENDERER=vulkan
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
        GPU_NAME="intel"
        return 0
    fi

    # Nouveau fallback
    GPU_NAME="nouveau"
    export WLR_RENDERER=gles2
    return 0
}

detect_gpu
# Log GPU detection result — /dev/kmsg requires root, fall back to logger
if [ -w /dev/kmsg ]; then
    echo "[kiosk-gpu] Detected: $GPU_NAME" >/dev/kmsg
else
    logger -t kiosk-gpu "Detected: $GPU_NAME" 2>/dev/null || true
fi
export KIOSK_GPU="$GPU_NAME"
EOF
chmod +x "$ROOTFS_DIR/usr/local/bin/detect-gpu.sh"

# ── /usr/local/bin/launch-xemu.sh
rootfs_write /usr/local/bin/launch-xemu.sh <<EOF
#!/bin/sh
# xemu launcher — called by cage inside the Wayland session

# Wayland / SDL env
export SDL_VIDEODRIVER=wayland
export EGL_PLATFORM=wayland
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export MESA_GL_VERSION_OVERRIDE=4.0
export MESA_GLSL_VERSION_OVERRIDE=400

# Audio
if command -v pipewire >/dev/null 2>&1; then
    export SDL_AUDIODRIVER=pipewire
    # Start pipewire in background if not running
    pipewire &
    wireplumber &
    sleep 0.5
else
    export SDL_AUDIODRIVER=alsa
fi

exec xemu $XEMU_ARGS
EOF
chmod +x "$ROOTFS_DIR/usr/local/bin/launch-xemu.sh"

# ── /usr/local/bin/start-kiosk.sh — cage launcher
rootfs_write /usr/local/bin/start-kiosk.sh <<'EOF'
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
    dialog --title "Error" --msgbox "Xbox MCPX Image not found at $XEMUHDD_IMGDIR\nPlease make sure to add it before booting." 8 60
    allclear=false
fi
if [ ! -f $XEMUBIOS_IMGDIR ]; then
    dialog --title "Error" --msgbox "Xbox BIOS Image not found at $XEMUHDD_IMGDIR\nPlease make sure to add it before booting." 8 60
    allclear=false
fi

if [ $allclear == false ]; then
    su -c poweroff
fi


while true; do
    cage -s -- /usr/local/bin/launch-xemu.sh
    logger -t $kioskusername "xemu exited, restarting in 2s..." 2>/dev/null || true
    sleep 2
done
EOF
chmod +x "$ROOTFS_DIR/usr/local/bin/start-kiosk.sh"

# ── /etc/init.d/kiosk — OpenRC service 
rootfs_write /etc/init.d/kiosk <<'EOF'
#!/sbin/openrc-run

extra_config="/etc/env.conf"

depend() {
    need dbus udev seatd
    after localmount
    after alsa
}

description="$kioskappname auto-start"
name="$kioskappname"

start() {
    . $extra_config
    ebegin "Preparing kiosk runtime dirs"
    # Create /run/user/<uid> for the kiosk user before their session starts
    local uid
    uid=$(id -u $kioskusername 2>/dev/null || echo 1000)
    mkdir -p "/run/user/$uid"
    chmod 0700 "/run/user/$uid"
    chown $kioskusername:$kioskusername "/run/user/$uid"
    eend 0
}
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk"

# ── /etc/modprobe.d/kiosk.conf — kernel module options
rootfs_write /etc/modprobe.d/kiosk.conf <<'EOF'
# AMD
options amdgpu dc=1 dpm=1 runpm=0

# Nvidia
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1

# Disable PC speaker beep
blacklist pcspkr
EOF

# ── /etc/modules-load.d/kiosk.conf — auto-load modules
rootfs_write /etc/modules-load.d/kiosk.conf <<'EOF'
# GPU
amdgpu
i915
nouveau

# USB input
usbhid
hid-generic
xpad

# USB storage (for game ISOs on additional USB)
usb-storage
EOF

# ── /etc/sysctl.d/kiosk.conf
rootfs_write /etc/sysctl.d/kiosk.conf <<'EOF'
# Reduce console spam
kernel.printk = 3 4 1 3

# Better VM behavior for games
vm.swappiness = 10
vm.dirty_ratio = 40
EOF

# ── xemu config
info "Writing xemu config..."
XEMU_CFG_DIR="$ROOTFS_DIR/home/$kioskusername/.config/xemu"
mkdir -p "$XEMU_CFG_DIR"

cat > "$XEMU_CFG_DIR/xemu.toml" <<EOF
[system]
  bootrom_path   = "$XEMUMCPX_IMGDIR"
  flashrom_path  = "$XEMUBIOS_IMGDIR"
  hdd_path       = "$XEMUHDD_IMGDIR"
  dvd_path       = ""          # auto-set by launch-xemu.sh
  mem_limit      = "64"        # "64" | "128" — original Xbox RAM
  avpack         = "hdtv"      # "composite" | "hdtv" | "scart"

[display]
  fullscreen         = true
  scale              = "stretch"   # "fit" | "stretch" | "integer"
  vsync              = true
  show_fps           = false

[audio]
  backend  = "sdl"
  use_dsp  = false

[network]
  enabled = false        # enable if you want Xbox Live emulation (Xemu.net)
  backend = "user"

[input]
  # Controllers are detected automatically
  # To bind: launch xemu manually once to configure
EOF

# Fix kiosk home ownership (UID/GID 1000 from adduser)
echo $ROOTFS_DIR
chroot "$ROOTFS_DIR" chown -R $kioskusername:$kioskusername /home/$kioskuserhome

# Enable kiosk services now that the init scripts exist
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk"
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk-firstboot"
chroot "$ROOTFS_DIR" rc-update add kiosk default
chroot "$ROOTFS_DIR" rc-update add kiosk-firstboot default


success "Overlay applied"
