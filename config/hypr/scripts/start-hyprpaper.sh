#!/usr/bin/env bash
# Wallpaper at login: hyprpaper (only for theme.toml wallpaper_backend = "hyprpaper"), then the video players.
#
# With the default backend "quickshell" the shell draws the image itself (config/quickshell/WallpaperLayer.qml, from
# out/wallpaper.json) as soon as it is up; until then Hyprland's background colour shows. Nothing here waits for it.
#
# hyprpaper backend: started straight from hyprland.start (2 s after the compositor) hyprpaper raced the monitor setup
# and came up "running" with every output black (hyprpaper itself reported the wallpaper active); only a manual
# restart fixed it. So: wait for the outputs and let them settle before starting it. (A blind second start a few
# seconds later was tried and removed: it fixed nothing visible and made the wallpaper blink on every login. If the
# black screen ever comes back, re-add it.)
log="${XDG_RUNTIME_DIR:-/tmp}/start-hyprpaper.log"
exec >"$log" 2>&1
theme="$HOME/.config/theme/theme.py"

wait_for_monitors() {
  local n=0
  for _ in $(seq 1 60); do                          # up to 30 s
    n=$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    [ "${n:-0}" -ge 1 ] && return 0
    sleep 0.5
  done
  return 1
}

start() {
  pkill -x hyprpaper
  while pgrep -x hyprpaper >/dev/null; do sleep 0.1; done
  setsid hyprpaper >/dev/null 2>&1 </dev/null &
}

backend=$(python3 -I "$theme" wallpaper-backend 2>/dev/null || echo quickshell)
echo "wallpaper backend: $backend"

wait_for_monitors && echo "monitors up: $(hyprctl monitors -j | jq -r '[.[].name] | join(",")')"
sleep 3                                              # outputs / DRM still settling after the count is non-zero
if [ "$backend" = hyprpaper ]; then
  start
  echo "started hyprpaper"
fi

# Video wallpapers (mpvpaper, bottom layer: above the wallpaper image of either backend). `video start` starts the
# players the state file asks for and is a no-op without any (and for players that already run); with the hyprpaper
# backend it first waits for hyprpaper to answer. Also re-run on monitor.added (hyprland/autostart.lua).
python3 -I "$theme" video start

# Wallpaper library: analyse what is not cached yet (lowest CPU / I/O priority), so a switch in Settings needs no analysis.
(sleep 60; exec python3 -I "$theme" analyze) >/dev/null 2>&1 &
