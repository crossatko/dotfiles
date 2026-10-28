#!/usr/bin/env bash
# Wallpaper engine supervisor (theme.toml wallpaper_backend = "engine"; config/quickshell/engine.qml): runs the engine as
# its own Quickshell instance and starts it again when it exits: after a crash it is back within ~1 s (0.1 s pause +
# start; the engine shows the still first, then its clips resume where they were). Quick repeated deaths (< 30 s each)
# back off: 3rd in a row 2 s, then 4, 8, 16, 30 s. Started at login by hyprland/autostart.lua; exits at once for the
# other backends, and stops when the backend is no longer "engine" (checked after each exit). One supervisor per login
# (flock). Files in $XDG_RUNTIME_DIR/wallpaper-engine/: pid (the engine: bin/engine-ipc, theme.py wallpaper-engine),
# supervisor.pid, engine.log (its output, truncated at each supervisor start).
# Restart the engine on purpose: `theme.py wallpaper-engine restart` (kills it by pid; this loop starts it again).
# Hyprland instance: every (re)start passes the RUNNING instance's signature and Wayland socket (current_instance: the
# caller's when it is alive, else the $XDG_RUNTIME_DIR/hypr/*/hyprland.lock whose pid is a live Hyprland), never a stale
# one inherited from an old shell (Quickshell reads it once: a dead signature = no workspace events, no monitors).
# No live Hyprland = the session is over: the supervisor exits.
d="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-engine"
mkdir -p "$d"
exec 9> "$d/supervisor.lock"
flock -n 9 || exit 0
theme="$HOME/.config/theme/theme.py"
qml="${WALLPAPER_ENGINE_QML:-$HOME/.config/quickshell/engine.qml}"
log="$d/engine.log"
backend() { python3 -I "$theme" wallpaper-backend 2>/dev/null || echo quickshell; }
alive() { [ -n "$1" ] && [ "$(cat "/proc/$1/comm" 2> /dev/null)" = Hyprland ]; }
current_instance() {   # prints "<signature> <wayland socket>" of the running Hyprland, or nothing
  local d pid way sig best=""
  for d in "${XDG_RUNTIME_DIR:-/tmp}"/hypr/*/; do
    [ -f "$d/hyprland.lock" ] || continue
    { read -r pid; read -r way; } < "$d/hyprland.lock"
    alive "$pid" || continue
    sig=$(basename "$d")
    [ "$sig" = "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && { echo "$sig $way"; return; }
    [ -z "$best" ] || [ "$way" = "${WAYLAND_DISPLAY##*/}" ] && best="$sig $way"
  done
  [ -n "$best" ] && echo "$best"
}
[ "$(backend)" = engine ] || exit 0
echo $$ > "$d/supervisor.pid"
: > "$log"
inst=$(current_instance)
[ -n "$inst" ] || { rm -f "$d/supervisor.pid"; exit 0; }
export HYPRLAND_INSTANCE_SIGNATURE=${inst% *} WAYLAND_DISPLAY=${inst#* }
# the player records live in the per-login runtime dir: write them now (a no-op when they exist; the still shows meanwhile)
python3 -I "$theme" video start > /dev/null 2>&1 9>&- &
child=
stop() { [ -n "$child" ] && kill "$child" 2> /dev/null; rm -f "$d/pid" "$d/supervisor.pid"; exit 0; }
trap stop TERM INT HUP
fails=0
while :; do
  t0=$SECONDS
  inst=$(current_instance)
  [ -n "$inst" ] || { echo "$(date '+%F %T') no running Hyprland: supervisor exits" >> "$log"; break; }
  export HYPRLAND_INSTANCE_SIGNATURE=${inst% *} WAYLAND_DISPLAY=${inst#* }
  echo "$(date '+%F %T') starting the engine for Hyprland $HYPRLAND_INSTANCE_SIGNATURE ($WAYLAND_DISPLAY)" >> "$log"
  # Quickshell's own crash handler is off: it re-launched a crashed instance as a NEW detached process (seen in a nested
  # SEGV test), which next to this loop's restart left two engines drawing; here a crash is just an exit
  QS_DISABLE_CRASH_HANDLER=1 QS_NO_RELOAD_POPUP=1 QSG_USE_SIMPLE_ANIMATION_DRIVER=1 quickshell -p "$qml" >> "$log" 2>&1 < /dev/null 9>&- &
  child=$!
  echo "$child" > "$d/pid"
  wait "$child"
  rc=$?
  child=
  rm -f "$d/pid"
  [ "$(backend)" = engine ] || break
  if [ $((SECONDS - t0)) -ge 30 ]; then fails=0; else fails=$((fails + 1)); fi
  delay=0.1
  [ $fails -ge 3 ] && delay=$((fails >= 7 ? 30 : 1 << (fails - 2)))
  echo "$(date '+%F %T') engine exited ($rc), restart in ${delay} s" >> "$log"
  sleep "$delay" 9>&- & wait $!   # (interruptible: a TERM stops the supervisor at once)
done
rm -f "$d/supervisor.pid"
