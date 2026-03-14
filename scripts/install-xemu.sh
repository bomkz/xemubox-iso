#!/bin/bash
# =============================================================================
# install-xemu.sh — Install xemu via package or AppImage
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

XEMU_BIN="$ROOTFS_DIR/usr/local/bin/xemu"
XEMU_DIR="$ROOTFS_DIR/opt/xemu"

# Decide install method
resolve_method() {
    if [ "$XEMU_USE_APPIMAGE" = "appimage" ]; then
        echo "appimage"; return
    fi
    if [ "$XEMU_USE_APPIMAGE" = "package" ]; then
        echo "package"; return
    fi
    # auto: try package first, fall back to AppImage
    if chroot "$ROOTFS_DIR" apk search --no-cache xemu 2>/dev/null | grep -q "^xemu-"; then
        echo "package"
    else
        echo "appimage"
    fi
}

install_via_package() {
    info "Installing xemu via apk package..."
    mount_chroot
    chroot_apk add --no-cache xemu
    umount_chroot
    success "xemu installed via package"
}

install_via_appimage() {
    info "Installing xemu via AppImage..."

    # Get latest release URL from GitHub API
    info "Fetching latest xemu release info..."
    RELEASE_JSON=$(curl -sf "https://api.github.com/repos/xemu-project/xemu/releases/latest" || true)

    if [ -n "$RELEASE_JSON" ]; then
        APPIMAGE_URL=$(echo "$RELEASE_JSON" | \
            grep -o '"browser_download_url": *"[^"]*\.AppImage"' | \
            grep -i "x86_64\|amd64" | \
            head -1 | \
            sed 's/.*": *"\(.*\)"/\1/')
    fi

    # Fallback URL pattern if API unavailable
    if [ -z "${APPIMAGE_URL:-}" ]; then
        warn "Could not fetch release info, using fallback download logic"
        APPIMAGE_URL="https://github.com/xemu-project/xemu/releases/latest/download/xemu-v0-x86_64.AppImage"
    fi

    info "Downloading: $APPIMAGE_URL"
    APPIMAGE_TMP="$(mktemp /tmp/xemu.XXXXXX.AppImage)"
    curl -L --progress-bar "$APPIMAGE_URL" -o "$APPIMAGE_TMP"

    # Extract AppImage (avoids FUSE requirement on Alpine)
    info "Extracting AppImage..."
    mkdir -p "$XEMU_DIR"
    cd /tmp
    chmod +x "$APPIMAGE_TMP"
    "$APPIMAGE_TMP" --appimage-extract 2>/dev/null || {
        # If host can't run it (arch mismatch), extract as zip
        warn "Cannot exec AppImage directly, extracting as squashfs..."
        unsquashfs -d "$XEMU_DIR" "$APPIMAGE_TMP" || \
            unzip -q "$APPIMAGE_TMP" -d "$XEMU_DIR" || \
            error "Failed to extract AppImage"
    }

    if [ -d /tmp/squashfs-root ]; then
        cp -a /tmp/squashfs-root/. "$XEMU_DIR/"
        rm -rf /tmp/squashfs-root
    fi

    rm -f "$APPIMAGE_TMP"

    # Create wrapper that sets needed env
    mkdir -p "$(dirname "$XEMU_BIN")"
    cat > "$XEMU_BIN" <<'WRAPPER'
#!/bin/sh
# xemu AppImage wrapper
exec /opt/xemu/AppRun "$@"
WRAPPER
    chmod +x "$XEMU_BIN"

    # Symlink xemu desktop file if present
    if [ -f "$XEMU_DIR/xemu.desktop" ]; then
        mkdir -p "$ROOTFS_DIR/usr/share/applications"
        cp "$XEMU_DIR/xemu.desktop" "$ROOTFS_DIR/usr/share/applications/"
    fi

    success "xemu installed via AppImage at /opt/xemu"
}

# ── Main ──────────────────────────────────────────────────────────────────────
METHOD=$(resolve_method)
info "xemu install method: $METHOD"

case "$METHOD" in
    package)  install_via_package  ;;
    appimage) install_via_appimage ;;
    *)        error "Unknown install method: $METHOD" ;;
esac

# Verify
if [ -x "$XEMU_BIN" ] || \
   chroot "$ROOTFS_DIR" which xemu &>/dev/null; then
    success "xemu binary present"
else
    error "xemu binary not found after install!"
fi
