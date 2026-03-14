#!/bin/bash
# =============================================================================
# build.sh — Main build orchestrator
# Runs inside the Docker builder container
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Entrypoint ─────────────────────────────────────────────────────────────────
main() {
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info " $kioskappname Builder"
    info " Image:   $IMAGE_FILE"
    info " Size:    ${IMAGE_SIZE_MB}MB total"
    info " Alpine:  $ALPINE_BRANCH / $ARCH"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    mkdir -p "$OUTPUT_DIR" "$ROOTFS_DIR"

    step "1/7" "Bootstrap Alpine rootfs"
    "$SCRIPT_DIR/bootstrap-rootfs.sh"

    step "2/7" "Install packages"
    "$SCRIPT_DIR/install-packages.sh"

    step "3/7" "Install xemu"
    "$SCRIPT_DIR/install-xemu.sh"

    step "4/7" "Apply rootfs overlay and configuration"
    "$SCRIPT_DIR/apply-overlay.sh"

    step "5/7" "Configure bootloader"
    "$SCRIPT_DIR/install-bootloader.sh"

    step "6/7" "Create disk image"
    "$SCRIPT_DIR/create-image.sh"

    step "7/7" "Finalize and validate"
    "$SCRIPT_DIR/finalize.sh"

    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "Build complete!"
    info "  Image:  $IMAGE_FILE"
    info "  Size:   $(du -sh "$IMAGE_FILE" | cut -f1)"
    info ""
    info "  Flash:  sudo bash /output/flash.sh /dev/sdX"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
