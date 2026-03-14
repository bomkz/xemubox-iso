#!/bin/bash
# =============================================================================
# install-packages.sh — Install all kiosk packages into the rootfs
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mount_chroot
trap umount_chroot EXIT

APK="chroot_apk --no-cache"

info "Installing base system packages..."
$APK add \
    alpine-base \
    openrc \
    busybox-extras \
    bash \
    shadow \
    sudo \
    util-linux \
    util-linux-misc \
    pciutils \
    usbutils \
    eudev \
    eudev-openrc \
    dbus \
    dbus-openrc \
    tzdata \
    ca-certificates \
    curl \
    wget \
    nano

# ── Kernel
info "Installing kernel..."
$APK add \
    linux-lts \
    linux-firmware-none

# ── GPU firmware & drivers 
info "Installing GPU drivers (AMD + Intel + Nvidia open)..."

# Mesa core — Alpine ships its own GL dispatch; libglvnd is not a separate package
$APK add \
    mesa \
    mesa-egl \
    mesa-gl \
    mesa-gbm \
    mesa-dri-gallium \
    libdrm

# AMD — note: Alpine calls this mesa-vulkan-ati, not mesa-vulkan-radeon
$APK add \
    mesa-vulkan-ati \
    linux-firmware-amdgpu \
    linux-firmware-radeon

# Intel
$APK add \
    mesa-vulkan-intel \
    linux-firmware-i915 \
    intel-media-driver || warn "intel-media-driver unavailable, skipping"

# Nouveau (Nvidia open-source fallback) — firmware lives in linux-firmware-nvidia on Alpine
$APK add \
    linux-firmware-nvidia

# Nvidia open kernel modules (optional, Turing+ / GTX 1600+, RTX)
if [ "$ENABLE_NVIDIA_OPEN" = "true" ]; then
    info "Installing Nvidia open kernel modules..."
    $APK add \
        gcompat \
        libc6-compat \
        nvidia-open || warn "nvidia-open unavailable on this Alpine branch, skipping"
fi

# ── Wayland compositor stack 
info "Installing Wayland stack..."
# wayland pulls wayland-libs-{client,server,egl,cursor} automatically
$APK add \
    wayland \
    wayland-utils \
    wayland-protocols \
    libinput \
    xkeyboard-config \
    libxkbcommon \
    libseat \
    seatd \
    cage

# Xwayland for any X11 fallback needs
$APK add xwayland || warn "xwayland unavailable, skipping"

# ── Audio 
info "Installing audio..."
$APK add alsa-utils alsa-lib

if [ "$ENABLE_PIPEWIRE" = "true" ]; then
    $APK add \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        wireplumber || {
        warn "PipeWire unavailable, falling back to ALSA only"
    }
fi

# ── Input
info "Installing input support..."
$APK add \
    libevdev \
    libinput \
    udev-init-scripts \
    udev-init-scripts-openrc

# ── SDL2 (required by xemu)
info "Installing SDL2..."
$APK add \
    sdl2 \
    sdl2_ttf \
    sdl2_image \
    sdl2_net

# ── xemu runtime dependencies
info "Installing xemu runtime dependencies..."
$APK add \
    libepoxy \
    pixman \
    zlib \
    libpng \
    libjpeg-turbo \
    glib \
    libstdc++ \
    gtk+3.0 || warn "gtk+3.0 unavailable, skipping"




# ── System utilities
$APK add \
    e2fsprogs \
    e2fsprogs-extra \
    parted \
    gptfdisk \
    dosfstools \
    lsblk \
    findmnt \
    procps \
    htop \
    strace \
    less \
    vim \
    sgdisk\
    dialog

# ── Fonts (needed for xemu UI)
$APK add \
    font-noto \
    font-noto-emoji || warn "font-noto-emoji unavailable, skipping"

# ── Create kiosk user
info "Creating $kioskappname user..."
chroot "$ROOTFS_DIR" /bin/sh -c '
    # Ensure optional groups exist before assigning
    for g in video audio input seat render; do
        getent group $g >/dev/null 2>&1 || addgroup -S $g
    done

    if ! id '"$kioskusername"' >/dev/null 2>&1; then
        adduser -D -h /home/'"$kioskuserhome"' '"$kioskusername"'
        passwd -d '"$kioskusername"'
    fi

    for g in video audio input seat render; do
        addgroup '"$kioskusername"' $g
    done
'

# ── OpenRC services
info "Enabling OpenRC services..."
chroot "$ROOTFS_DIR" /bin/sh -c "
    rc-update add devfs sysinit
    rc-update add dmesg sysinit
    rc-update add mdev sysinit
    rc-update add hwdrivers sysinit
    rc-update add udev sysinit
    rc-update add udev-trigger sysinit
    rc-update add udev-settle sysinit
    rc-update add modules boot
    rc-update add sysctl boot
    rc-update add hostname boot
    rc-update add bootmisc boot
    rc-update add syslog boot
    rc-update add mount-ro shutdown
    rc-update add killprocs shutdown
    rc-update add savecache shutdown
    rc-update add dbus default
    rc-update add alsa default
    rc-update add seatd default
"

success "Packages installed"
