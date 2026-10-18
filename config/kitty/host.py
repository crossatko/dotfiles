# Per-host overrides, included from kitty.conf via `geninclude`: whatever this prints is read as kitty config.
# Same host test as config/hypr/hyprland/host.lua (hostname contains BATTLESTATION).
import socket

if "BATTLESTATION" in socket.gethostname().upper():
    print("background_opacity 0.2")
