#!/bin/bash
# =============================================================================
# lib.sh — shared helpers sourced by all build scripts
# =============================================================================

# ── Build variables (override via environment) ────────────────────────────────
# Using := so env vars set before the script win, but defaults are always set
: "${IMAGE_NAME:=xemu-kiosk}"
: "${IMAGE_SIZE_MB:=8192}"
: "${BOOT_SIZE_MB:=256}"
: "${SYSTEM_SIZE_MB:=4096}"
: "${ALPINE_BRANCH:=edge}"
: "${ALPINE_MIRROR:=https://dl-cdn.alpinelinux.org/alpine}"
: "${ARCH:=x86_64}"
: "${ROOTFS_DIR:=/builder/rootfs}"
: "${OUTPUT_DIR:=/output}"
: "${OVERLAY_DIR:=/builder/rootfs-overlay}"
: "${EXTOVERLAY_DIR:=/builder/overlay}"
: "${CONFIG_DIR:=/builder/config}"
: "${XEMU_USE_APPIMAGE:=auto}"
: "${ENABLE_NVIDIA_OPEN:=true}"
: "${ENABLE_PIPEWIRE:=true}"
: "${KIOSK_URL:=}"
: "${CREATE_XBOX_HDD:=true}"
: "${kioskusername:=}"
: "${kioskuserhome:=}"
: "${kioskappname:=}"


IMAGE_FILE="$OUTPUT_DIR/${IMAGE_NAME}.img"

export IMAGE_NAME IMAGE_SIZE_MB BOOT_SIZE_MB SYSTEM_SIZE_MB
export ALPINE_BRANCH ALPINE_MIRROR ARCH
export ROOTFS_DIR OUTPUT_DIR OVERLAY_DIR CONFIG_DIR
export XEMU_USE_APPIMAGE ENABLE_NVIDIA_OPEN ENABLE_PIPEWIRE
export KIOSK_URL CREATE_XBOX_HDD IMAGE_FILE
export kioskappname kioskusername kioskuserhome

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}── Step $1: $2${NC}"; }

# Run a command inside the rootfs chroot
chroot_run() {
    chroot "$ROOTFS_DIR" /bin/sh -c "$*"
}

# Run apk inside the chroot
chroot_apk() {
    chroot "$ROOTFS_DIR" apk "$@"
}

# Write a file into the rootfs
rootfs_write() {
    local path="$1"
    local dir
    dir="$(dirname "${ROOTFS_DIR}${path}")"
    mkdir -p "$dir"
    cat > "${ROOTFS_DIR}${path}"
}

# Make a file executable inside the rootfs
rootfs_chmod_x() {
    chmod +x "${ROOTFS_DIR}${1}"
}

# Setup chroot mounts (proc/sys/dev)
mount_chroot() {
    mount -t proc none "$ROOTFS_DIR/proc" 2>/dev/null || true
    mount --bind /sys  "$ROOTFS_DIR/sys"  2>/dev/null || true
    mount --bind /dev  "$ROOTFS_DIR/dev"  2>/dev/null || true
}

# Tear down chroot mounts
umount_chroot() {
    umount "$ROOTFS_DIR/proc" 2>/dev/null || true
    umount "$ROOTFS_DIR/sys"  2>/dev/null || true
    umount "$ROOTFS_DIR/dev"  2>/dev/null || true
}

# Attach image to a loop device, returns loop device path
attach_image() {
    local img="$1"
    # Explicitly find a free loop device first, then attach
    local dev
    dev=$(losetup -f 2>/dev/null) || {
        # If losetup -f fails, try to create the next available loop device
        local n=0
        while [ -e "/dev/loop$n" ]; do n=$((n+1)); done
        mknod -m 0660 "/dev/loop$n" b 7 "$n"
        dev="/dev/loop$n"
    }
    losetup --partscan "$dev" "$img"
    echo "$dev"
}

# Detach loop device
detach_image() {
    losetup -d "$1" 2>/dev/null || true
}

# Wait for partition nodes to appear after attaching a loop device
wait_for_parts() {
    local dev="$1"
    local n="$2"

    # partx is the correct tool for loop devices — explicitly registers
    # partitions with the kernel rather than asking it to re-read
    partx -a "$dev" 2>/dev/null || partx -u "$dev" 2>/dev/null || true
    sleep 0.5

    # Poll up to 5 seconds
    for i in $(seq 1 25); do
        [ -e "${dev}p${n}" ] && return 0
        sleep 0.2
    done

    # Hard fallback: mknod the partition nodes manually
    # (works in --privileged containers where the kernel won't auto-create them)
    info "Partition nodes not auto-created, using mknod fallback..."
    local base_minor
    base_minor=$(( $(stat -c '%T' "$dev" 2>/dev/null || echo 0) ))
    # For loop devices: loop0=7:0, loop0p1=7:1, loop1=7:1... use /proc/partitions
    while IFS= read -r line; do
        local major minor blocks name
        read -r major minor blocks name <<< "$line"
        # Match partitions of our loop device (e.g. loop1p1, loop1p2...)
        local devname
        devname=$(basename "$dev")
        if [[ "$name" == "${devname}p"* ]]; then
            local node="/dev/$name"
            [ -e "$node" ] || mknod -m 0660 "$node" b "$major" "$minor"
        fi
    done < <(tail -n +3 /proc/partitions)

    [ -e "${dev}p${n}" ] || { error "Partition node ${dev}p${n} never appeared"; return 1; }
}
