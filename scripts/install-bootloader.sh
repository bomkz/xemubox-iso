#!/bin/bash
# =============================================================================
# install-bootloader.sh — Install GRUB config into rootfs
# (actual grub-install runs during image creation when we have a loop device)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

info "Writing GRUB configuration..."

mkdir -p "$ROOTFS_DIR/boot/grub"

cat > "$ROOTFS_DIR/boot/grub/grub.cfg" <<GRUBCFG
set default=0
set timeout=0
set timeout_style=hidden

# Allow holding SHIFT at boot to show menu
if keystatus --shift; then
    set timeout=5
    set timeout_style=menu
fi

menuentry "$kioskappname" {
    insmod part_gpt
    insmod ext2
    search --no-floppy --label --set=root $kioskrootpartlabel

    linux  /boot/vmlinuz-lts \
        root=LABEL=$kioskrootpartlabel \
        rootfstype=ext4 \
        rw \
        quiet \
        loglevel=3 \
        vt.global_cursor_default=0 \
        amdgpu.dc=1 \
        nvidia-drm.modeset=1 \
        i915.modeset=1 \
        plymouth.enable=0 \
        consoleblank=0

    initrd /boot/initramfs-lts
}

menuentry "$kioskappname (recovery shell)" {
    insmod part_gpt
    insmod ext2
    search --no-floppy --label --set=root $kioskrootpartlabel

    linux  /boot/vmlinuz-lts \
        root=LABEL=$kioskrootpartlabel \
        rootfstype=ext4 \
        rw \
        single \
        init=/bin/sh

    initrd /boot/initramfs-lts
}
GRUBCFG

# ── Generate initramfs ────────────────────────────────────────────────────────
info "Generating initramfs..."
mount_chroot
chroot "$ROOTFS_DIR" mkinitfs -o /boot/initramfs-lts \
    $(ls "$ROOTFS_DIR/lib/modules/" | head -1) || \
    warn "mkinitfs failed — you may need to run it manually in the rootfs"
umount_chroot

success "Bootloader configuration written"
