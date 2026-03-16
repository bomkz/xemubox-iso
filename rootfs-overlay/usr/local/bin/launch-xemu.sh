#!/bin/sh
# xemu launcher — called by cage inside the Wayland session

# Wayland / SDL env
export SDL_VIDEODRIVER=wayland
export EGL_PLATFORM=wayland
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export MESA_GL_VERSION_OVERRIDE=4.0
export MESA_GLSL_VERSION_OVERRIDE=400

. /etc/env.conf

# Audio
if command -v pipewire >/dev/null 2>&1; then
    export SDL_AUDIODRIVER=pipewire
    # Start pipewire in background if not running
    pipewire &
    wireplumber &
    sleep 0.5
else
    export SDL_AUDIODRIVER=alsa
fi

exec xemu $XEMU_ARGS
