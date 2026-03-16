# Auto-start kiosk on tty1
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    exec /usr/local/bin/start-kiosk.sh
fi