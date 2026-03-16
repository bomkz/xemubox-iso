FROM alpine:edge AS builder

LABEL description="xemu Kiosk Image Builder"
LABEL maintainer="you"

# ── Build tools ────────────────────────────────────────────────────────────────
RUN apk add --no-cache \
    # rootfs bootstrap
    alpine-base \
    apk-tools \
    # image/partition tools
    parted \
    e2fsprogs \
    e2fsprogs-extra \
    dosfstools \
    util-linux \
    util-linux-misc \
    sgdisk \
    lsblk \
    # build utilities
    bash \
    coreutils \
    rsync \
    wget \
    curl \
    squashfs-tools \
    xz \
    tar \
    gzip \
    # bootloader
    grub \
    grub-efi \
    mtools \
    # qcow2 tools (for pre-creating xbox HDD image)
    qemu-img \
    # misc
    jq \
    pv \
    file \
    envsubst

# ── Copy build scripts and overlay ────────────────────────────────────────────
COPY scripts/           /builder/scripts/
COPY rootfs-overlay/    /builder/rootfs-overlay/
COPY overlay/           /builder/overlay
COPY config/            /builder/config/

RUN chmod +x /builder/scripts/*.sh

# ── Output lives here (mount a volume to /output) ─────────────────────────────
VOLUME ["/output"]

WORKDIR /builder

ENTRYPOINT ["/builder/scripts/build.sh"]
