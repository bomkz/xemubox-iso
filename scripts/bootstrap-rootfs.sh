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

# ── Locale / timezone 
echo "UTC" > "$ROOTFS_DIR/etc/timezone"

# ── DNS
cat > "$ROOTFS_DIR/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# ── Hosts
cat > "$ROOTFS_DIR/etc/hosts" <<EOF
127.0.0.1   localhost $hostname
::1         localhost $hostname
EOF

# ── fstab
cat > "$ROOTFS_DIR/etc/fstab" <<EOF
# <device>        <mountpoint>  <type>  <options>                          <dump> <pass>
LABEL=${kioskrootpartlabel}     /             ext4    defaults,noatime,errors=remount-ro  0      1
LABEL=${kioskbootpartlabel}   /boot/efi     vfat    defaults,noatime                    0      2
LABEL=${kioskdatapartlabel}   /media/data   ext4    defaults,nofail,noatime             0      2
tmpfs             /tmp          tmpfs   defaults,nosuid,nodev,size=256m     0      0
EOF

# ── env
cat > "$ROOTFS_DIR/etc/env.conf" <<EOF
kioskappname="$kioskappname"
kioskusername="$kioskusername"
kioskuserhome="$kioskuserhome"

firstbootname="$firstbootname"
firstbootdesc="$firstbootdesc"
firstbootflag="$firstbootflag"

kioskrootpartlabel="$kioskrootpartlabel"
kioskbootpartlabel="$kioskbootpartlabel"
kioskdatapartlabel="$kioskdatapartlabel"


XEMUHDD_IMGDIR="$XEMUHDD_IMGDIR"
XEMUMCPX_IMGDIR="$XEMUMCPX_IMGDIR"
XEMUBIOS_IMGDIR="$XEMUBIOS_IMGDIR"


hostname="$hostname"
EOF


success "Alpine rootfs bootstrapped"
