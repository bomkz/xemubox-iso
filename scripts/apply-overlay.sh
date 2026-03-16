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

inittabvar=$(<"$EXTOVERLAY_DIR/etc/inittab")
expanded=$(printf '%s' "$inittabvar" | envsubst)

rootfs_write /etc/inittab << EOF
$expanded
EOF

# ── /usr/local/bin/detect-gpu.sh
chmod +x "$ROOTFS_DIR/usr/local/bin/detect-gpu.sh"

# ── /usr/local/bin/launch-xemu.sh
chmod +x "$ROOTFS_DIR/usr/local/bin/launch-xemu.sh"

# ── /usr/local/bin/start-kiosk.sh — cage launcher
chmod +x "$ROOTFS_DIR/usr/local/bin/start-kiosk.sh"

# ── /etc/init.d/kiosk — OpenRC service 
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk"

# Fix kiosk home
cp -r $OVERLAY_DIR/etc/skel/. $ROOTFS_DIR/etc/skel/.
cp -r $ROOTFS_DIR/etc/skel/. $ROOTFS_DIR/home/$kioskuserhome/.
echo $ROOTFS_DIR
chroot "$ROOTFS_DIR" chown -R $kioskusername:$kioskusername /home/$kioskuserhome

# Enable kiosk services now that the init scripts exist
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk"
chmod +x "$ROOTFS_DIR/etc/init.d/kiosk-firstboot"
chroot "$ROOTFS_DIR" rc-update add kiosk default
chroot "$ROOTFS_DIR" rc-update add kiosk-firstboot default


success "Overlay applied"
