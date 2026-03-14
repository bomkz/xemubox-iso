#!/bin/bash
# =============================================================================
# finalize.sh — Validate image and write flash utility to /output
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# ── Validate image ────────────────────────────────────────────────────────────
info "Validating image..."

if [ ! -f "$IMAGE_FILE" ]; then
    error "Image file not found: $IMAGE_FILE"
fi

IMAGE_SIZE=$(stat -c%s "$IMAGE_FILE")
if [ "$IMAGE_SIZE" -lt $((512 * 1024 * 1024)) ]; then
    error "Image seems too small ($IMAGE_SIZE bytes) — something went wrong"
fi

# Check GPT is valid
parted -s "$IMAGE_FILE" print | grep -q "gpt" || warn "GPT not detected in image"
parted -s "$IMAGE_FILE" print | grep -q "$kioskrootpartlabel" || warn "$kioskrootpartlabel partition not found"

# ── Write flash script ────────────────────────────────────────────────────────
info "Writing flash utility..."

cat > "$OUTPUT_DIR/flash.sh" <<'FLASHSCRIPT'
#!/bin/bash
# =============================================================================
# flash.sh — Flash xemu kiosk image to a USB drive
# Usage: sudo bash flash.sh /dev/sdX [image.img]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
IMAGE="${2:-$SCRIPT_DIR/${IMAGE_NAME}.img}"

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Must run as root: sudo bash flash.sh /dev/sdX"
[ -f "$IMAGE" ]      || error "Image not found: $IMAGE"

# ── Show available drives ────────────────────────────────────────────────────
echo ""
info "Available block devices:"
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -v "loop\|sr0\|zram" | column -t
echo ""

if [ -z "$TARGET" ]; then
    read -rp "Enter target device (e.g. /dev/sdb): " TARGET
fi

[[ "$TARGET" =~ ^/dev/ ]] || TARGET="/dev/$TARGET"
[ -b "$TARGET" ]           || error "Not a block device: $TARGET"

# Safety checks
DISK_SIZE=$(blockdev --getsize64 "$TARGET" 2>/dev/null || stat -c%s "$TARGET")
IMAGE_SIZE=$(stat -c%s "$IMAGE")
DISK_SIZE_MB=$((DISK_SIZE / 1024 / 1024))
IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))

if [ "$DISK_SIZE" -lt "$IMAGE_SIZE" ]; then
    error "Target ($DISK_SIZE_MB MB) is smaller than image ($IMAGE_SIZE_MB MB)"
fi

# Prevent flashing to system disk
ROOT_DISK=$(lsblk -no pkname $(findmnt -n -o SOURCE /) 2>/dev/null || true)
if [[ "$TARGET" == "/dev/$ROOT_DISK" ]] || [[ "$TARGET" == "/dev/sda" && "$ROOT_DISK" == "sda" ]]; then
    warn "Target appears to be your system disk!"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Image:   ${BLUE}$IMAGE${NC} (${IMAGE_SIZE_MB}MB)"
echo -e "  Target:  ${RED}$TARGET${NC} (${DISK_SIZE_MB}MB)"
echo -e "  ${RED}⚠  ALL DATA ON $TARGET WILL BE ERASED${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -rp "Type YES to continue: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Aborted."; exit 0; }

# Unmount any partitions on target
info "Unmounting $TARGET partitions..."
umount "${TARGET}"* 2>/dev/null || true
sleep 1

# Flash
info "Flashing... (${IMAGE_SIZE_MB}MB)"
if command -v pv >/dev/null 2>&1; then
    pv "$IMAGE" | dd of="$TARGET" bs=4M conv=fsync
else
    dd if="$IMAGE" of="$TARGET" bs=4M conv=fsync status=progress
fi

sync

echo ""
success "Flash complete!"
info "  Eject $TARGET and boot the target machine from it."
info "  The data partition will automatically expand to fill the drive on first boot."
info "  Before first boot, copy your Xbox BIOS files to the data partition:"
info "    xbox/mcpx_1.0.bin"
info "    xbox/bios.bin"
echo ""
FLASHSCRIPT

chmod +x "$OUTPUT_DIR/flash.sh"
success "Finalization complete"
info ""
info "Output files:"
ls -lh "$OUTPUT_DIR/"
