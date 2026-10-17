#!/usr/bin/env bash
# Start hyprpaper once the monitors are really up.
#
# Started straight from hyprland.start (2 s after the compositor) hyprpaper raced the monitor setup
# and came up "running" with every output black (hyprpaper itself reported the wallpaper active);
# only a manual restart fixed it. So: wait for the outputs and let them settle before starting it.
# (A blind second start a few seconds later was tried and removed: it fixed nothing visible and made
# the wallpaper blink on every login. If the black screen ever comes back, re-add it.)
log="${XDG_RUNTIME_DIR:-/tmp}/start-hyprpaper.log"
exec >"$log" 2>&1

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

wait_for_monitors && echo "monitors up: $(hyprctl monitors -j | jq -r '[.[].name] | join(",")')"
sleep 3                                              # outputs / DRM still settling after the count is non-zero
start
echo "started"
