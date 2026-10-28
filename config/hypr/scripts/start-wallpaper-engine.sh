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
# Race at login: autostart runs this ~0.2 s BEFORE Hyprland writes its hyprland.lock (seen on a real boot: no instance
# found, the supervisor exited silently, no wallpaper). So the instance is waited for: up to 60 s at start, 15 s before
# each restart; only then "no live Hyprland" = the session is over and the supervisor exits (and says so in engine.log).
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
    pid= way=
    { read -r pid; read -r way; } < "$d/hyprland.lock"
    [ -n "$way" ] && [ -S "${XDG_RUNTIME_DIR:-/tmp}/$way" ] || continue   # lock half written / socket not up yet
    alive "$pid" || continue
    sig=$(basename "$d")
    [ "$sig" = "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && { echo "$sig $way"; return; }
    [ -z "$best" ] || [ "$way" = "${WAYLAND_DISPLAY##*/}" ] && best="$sig $way"
  done
  [ -n "$best" ] && echo "$best"
}
wait_instance() {   # wait_instance <seconds>: current_instance, polled every 0.25 s until it answers or time is up
  local i inst
  for ((i = 0; i < $1 * 4; i++)); do
    inst=$(current_instance)
    [ -n "$inst" ] && { echo "$inst"; return 0; }
    sleep 0.25
  done
  return 1
}
[ "$(backend)" = engine ] || exit 0
echo $$ > "$d/supervisor.pid"
: > "$log"
echo "$(date '+%F %T') supervisor $$ started, waiting for Hyprland" >> "$log"
inst=$(wait_instance 60) || { echo "$(date '+%F %T') no running Hyprland after 60 s: supervisor exits" >> "$log"; rm -f "$d/supervisor.pid"; exit 0; }
export HYPRLAND_INSTANCE_SIGNATURE=${inst% *} WAYLAND_DISPLAY=${inst#* }
# the player records live in the per-login runtime dir: write them now (a no-op when they exist; the still shows meanwhile)
python3 -I "$theme" video start > /dev/null 2>&1 9>&- &
child=
stop() { [ -n "$child" ] && kill "$child" 2> /dev/null; rm -f "$d/pid" "$d/supervisor.pid"; exit 0; }
trap stop TERM INT HUP
fails=0
while :; do
  t0=$SECONDS
  inst=$(wait_instance 15) || { echo "$(date '+%F %T') no running Hyprland: supervisor exits" >> "$log"; break; }
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
