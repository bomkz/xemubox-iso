#!/bin/sh
# GPU detection and environment setup
# Sourced by start-kiosk.sh before launching cage/xemu

detect_gpu() {
    # Prefer proprietary Nvidia if module loaded
    if lsmod 2>/dev/null | grep -q "^nvidia "; then
        export GBM_BACKEND=nvidia-drm
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
        export WLR_NO_HARDWARE_CURSORS=1
        export WLR_RENDERER=gles2
        GPU_NAME="nvidia-proprietary"
        return 0
    fi

    # AMD
    if lspci 2>/dev/null | grep -qi "amd\|radeon\|amdgpu"; then
        export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
        export AMD_VULKAN_ICD=RADV
        export WLR_RENDERER=vulkan
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
        GPU_NAME="amd"
        return 0
    fi

    # Intel
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*uhd\|intel.*hd graphics\|intel.*iris"; then
        export MESA_LOADER_DRIVER_OVERRIDE=iris
        export WLR_RENDERER=vulkan
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
        GPU_NAME="intel"
        return 0
    fi

    # Nouveau fallback
    GPU_NAME="nouveau"
    export WLR_RENDERER=gles2
    return 0
}

detect_gpu
# Log GPU detection result — /dev/kmsg requires root, fall back to logger
if [ -w /dev/kmsg ]; then
    echo "[kiosk-gpu] Detected: $GPU_NAME" >/dev/kmsg
else
    logger -t kiosk-gpu "Detected: $GPU_NAME" 2>/dev/null || true
fi
export KIOSK_GPU="$GPU_NAME"