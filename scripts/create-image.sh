#!/bin/bash
# =============================================================================
# create-image.sh — Partition, format, and populate the disk image
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

BOOT_END_MB=$((BOOT_SIZE_MB + 1))
SYSTEM_END_MB=$((BOOT_END_MB + SYSTEM_SIZE_MB))

info "Ensuring loop devices exist..."
for i in $(seq 0 7); do
    [ -e "/dev/loop$i" ] || mknod -m 0660 "/dev/loop$i" b 7 "$i"
done
modprobe loop 2>/dev/null || true

info "Creating disk image: $IMAGE_FILE (${IMAGE_SIZE_MB}MB)"

# ── 1. Allocate image file ────────────────────────────────────────────────────
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count="$IMAGE_SIZE_MB" status=progress

# ── 2. Partition table ────────────────────────────────────────────────────────
info "Partitioning..."
parted -s "$IMAGE_FILE" \
    mklabel gpt \
    mkpart $kioskbootpartlabel fat32   1MiB      ${BOOT_END_MB}MiB \
    set 1 esp on \
    mkpart $kioskrootpartlabel   ext4    ${BOOT_END_MB}MiB  ${SYSTEM_END_MB}MiB \
    mkpart $kioskdatapartlabel ext4    ${SYSTEM_END_MB}MiB 100%

# ── 3. Attach loop device ─────────────────────────────────────────────────────
info "Attaching loop device..."
LOOP=$(attach_image "$IMAGE_FILE")
info "Loop device: $LOOP"
sleep 1   # give the kernel a moment to process the partition table
wait_for_parts "$LOOP" 3

# ── 4. Format partitions ──────────────────────────────────────────────────────
info "Formatting partitions..."
mkfs.fat  -F32  -n "$kioskbootpartlabel" "${LOOP}p1"
mkfs.ext4 -L $kioskrootpartlabel   -F "${LOOP}p2"
mkfs.ext4 -L $kioskdatapartlabel -F "${LOOP}p3"

# ── 5. Mount and populate ─────────────────────────────────────────────────────
info "Mounting system partition..."
TARGET=/mnt/kiosk-target
mkdir -p "$TARGET"
mount "${LOOP}p2" "$TARGET"

mkdir -p "$TARGET/boot/efi"
mount "${LOOP}p1" "$TARGET/boot/efi"

info "Copying rootfs to image (this takes a while)..."
rsync -aAX \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/run \
    --exclude=/tmp \
    --info=progress2 \
    "$ROOTFS_DIR/" "$TARGET/"

# Recreate excluded dirs
mkdir -p "$TARGET"/{proc,sys,dev,run,tmp}
chmod 1777 "$TARGET/tmp"

# ── 6. Install GRUB ───────────────────────────────────────────────────────────
info "Installing GRUB EFI bootloader..."
grub-install \
    --target=x86_64-efi \
    --efi-directory="$TARGET/boot/efi" \
    --boot-directory="$TARGET/boot" \
    --removable \
    --no-nvram \
    "$LOOP" || warn "grub-install had warnings (may be fine)"

# ── 7. Mount and init data partition ─────────────────────────────────────────
info "Initializing data partition..."
DATA_MNT=/mnt/kiosk-data
mkdir -p "$DATA_MNT"
mount "${LOOP}p3" "$DATA_MNT"

mkdir -p "$DATA_MNT/xbox"

# Placeholder README
cat > "$DATA_MNT/README.txt" <<DREAD
$kioskappname - Data Partition
============================

Required files (copy here before booting):
  xbox/mcpx_1.0.bin   — Xbox MCPX boot ROM
  xbox/bios.bin        — Xbox BIOS dump
  xbox/xbox_hdd.qcow2  — Xbox HDD image (pre-created blank, or your own)

Optional:
  xbox/games/*.iso     — Game ISO images
                         (first .iso found will auto-launch)

Config:
  xemu settings are stored at /home/$kioskuserhome/.config/xemu/xemu.toml on the OS partition.
DREAD

# ── 8. Cleanup ────────────────────────────────────────────────────────────────
info "Unmounting..."
umount "$DATA_MNT"
umount "$TARGET/boot/efi"
umount "$TARGET"
detach_image "$LOOP"

success "Disk image created: $IMAGE_FILE"
