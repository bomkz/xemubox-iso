#!/bin/bash
# =============================================================================
# bootstrap-rootfs.sh — Create a minimal Alpine rootfs using apk
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

info "Bootstrapping Alpine $ALPINE_BRANCH ($ARCH) into $ROOTFS_DIR"

mkdir -p "$ROOTFS_DIR"/etc/apk

# ── APK repositories
cat > "$ROOTFS_DIR/etc/apk/repositories" <<EOF
${ALPINE_MIRROR}/${ALPINE_BRANCH}/main
${ALPINE_MIRROR}/${ALPINE_BRANCH}/community
${ALPINE_MIRROR}/${ALPINE_BRANCH}/testing
EOF

# ── Bootstrap with apk (no-install-recommends equivalent)
apk add \
    --root "$ROOTFS_DIR" \
    --initdb \
    --arch "$ARCH" \
    --no-cache \
    --allow-untrusted \
    alpine-base \
    openrc \
    busybox \
    busybox-openrc \
    util-linux \
    e2fsprogs \
    dosfstools \

# ── Basic filesystem structure 
mkdir -p "$ROOTFS_DIR"/{proc,sys,dev,run,tmp,media/data,mnt}
chmod 1777 "$ROOTFS_DIR/tmp"

# ── Hostname
echo "$hostname" > "$ROOTFS_DIR/etc/hostname"

# Locale

cp $OVERLAY_DIR/etc/timezone $ROOTFS_DIR/etc/timezone 

# DNS
cp $OVERLAY_DIR/etc/resolv.conf $ROOTFS_DIR/etc/resolv.conf

# Hosts
hostsvar=$(<"$EXTOVERLAY_DIR/etc/hosts")
expanded=$(printf '%s' "$hostsvar" | envsubst)

rootfs_write /etc/hosts << EOF
$expanded
EOF

# ── fstab
fstabvar=$(<"$EXTOVERLAY_DIR/etc/fstab")
expanded=$(printf '%s' "$fstabvar" | envsubst)

rootfs_write /etc/fstab << EOF
$expanded
EOF

# ── env

envvar=$(<"$EXTOVERLAY_DIR/etc/env.conf")
expanded=$(printf '%s' "$envvar" | envsubst)

rootfs_write /etc/env.conf << EOF
$expanded
EOF

success "Alpine rootfs bootstrapped"
