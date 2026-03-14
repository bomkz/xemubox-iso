# xemu Kiosk Builder

Builds a bootable Alpine Linux USB image running xemu in a fullscreen Wayland
kiosk session. Supports AMD, Intel, and Nvidia GPUs. The remaining USB space is
formatted as a writable data partition for your Xbox BIOS files and game ISOs.

## Prerequisites

- Docker (with `--privileged` support — standard Docker Desktop or Engine)
- `make`
- ~10GB of free disk space during build

## Quick Start

```bash
# 1. Build the image
make build

# 2. Flash to USB (replace /dev/sdX with your drive!)
make flash DEV=/dev/sdX

# 3. Copy your Xbox BIOS files to the KIOSKDATA partition
cp mcpx_1.0.bin  /path/to/KIOSKDATA/xbox/
cp bios.bin      /path/to/KIOSKDATA/xbox/

# 4. Drop game ISOs
cp mygame.iso  /path/to/KIOSKDATA/xbox/games/

# 5. Boot the target machine from the USB
```

## Configuration

Edit `config/build.env` before building:

| Variable           | Default        | Description                              |
|--------------------|----------------|------------------------------------------|
| `IMAGE_SIZE_MB`    | `8192`         | Total image size (match your USB)        |
| `SYSTEM_SIZE_MB`   | `4096`         | OS partition size (rest → data)          |
| `XEMU_USE_APPIMAGE`| `auto`         | `auto` / `package` / `appimage`          |
| `ENABLE_NVIDIA_OPEN`| `true`        | Include Nvidia open kernel modules       |
| `ENABLE_PIPEWIRE`  | `true`         | PipeWire audio (false = ALSA only)       |
| `CREATE_XBOX_HDD`  | `true`         | Pre-create blank 8GB xbox_hdd.qcow2      |

## Project Structure

```
xemu-kiosk-builder/
├── Dockerfile                  # Builder container definition
├── Makefile                    # Build, flash, shell shortcuts
├── config/
│   └── build.env               # Build configuration
├── scripts/
│   ├── build.sh                # Main orchestrator
│   ├── lib.sh                  # Shared helpers
│   ├── bootstrap-rootfs.sh     # Alpine rootfs bootstrap
│   ├── install-packages.sh     # APK package install
│   ├── install-xemu.sh         # xemu install (package or AppImage)
│   ├── apply-overlay.sh        # Config file generation
│   ├── install-bootloader.sh   # GRUB config + initramfs
│   ├── create-image.sh         # Disk image creation + partition
│   └── finalize.sh             # Validation + flash.sh output
└── rootfs-overlay/             # Files copied verbatim into rootfs
    └── etc/
        ├── init.d/kiosk-firstboot
        ├── modprobe.d/
        ├── udev/rules.d/99-kiosk.rules
        └── ...
```

## Data Partition Layout

```
KIOSKDATA partition (/media/data)
├── xbox/
│   ├── mcpx_1.0.bin     ← Required: MCPX 1.0 boot ROM (8KB)
│   ├── bios.bin          ← Required: Xbox BIOS dump
│   ├── xbox_hdd.qcow2    ← Pre-created blank HDD image
│   └── games/
│       └── *.iso         ← Game ISOs (first found auto-launches)
└── README.txt
```

## GPU Support

Detection runs automatically at boot via `/usr/local/bin/detect-gpu.sh`:

| GPU       | Driver            | Renderer  |
|-----------|-------------------|-----------|
| AMD       | amdgpu + Mesa     | Vulkan    |
| Intel     | i915/xe + Mesa    | Vulkan    |
| Nvidia (proprietary) | nvidia-open | GLES2 |
| Nvidia (fallback)    | nouveau    | GLES2 |

## Debugging

Drop into the builder container to poke around:

```bash
make shell
# Inside the container:
bash /builder/scripts/bootstrap-rootfs.sh
# Inspect the rootfs at /builder/rootfs
```

To get a shell on the booted kiosk, hold **Shift** during boot to show the
GRUB menu, then select "recovery shell".

## Customization Tips

- **Change the auto-launched app**: Edit `launch-xemu.sh` in `apply-overlay.sh`
- **Add startup splash**: Install `plymouth` and configure in GRUB cmdline
- **Network/Xemu.net**: Set `network.enabled = true` in `xemu.toml`
- **Multiple games menu**: Replace `launch-xemu.sh` with a simple shell menu
  using `whiptail` or `dialog`
- **SSH access**: `apk add openssh` and `rc-update add sshd default` in
  `install-packages.sh`
