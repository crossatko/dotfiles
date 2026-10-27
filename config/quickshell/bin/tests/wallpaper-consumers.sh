#!/usr/bin/env bash
# Wallpaper consumers follow a switch (nested test session only): bash wallpaper-consumers.sh <shell pid> <image A> <image B> [video]
# Needs the environment of a NESTED test session (HOME under /tmp with .config/theme = a sandboxed engine copy, its own
# XDG_RUNTIME_DIR, HYPRLAND_INSTANCE_SIGNATURE / WAYLAND_DISPLAY of the nested Hyprland; AGENTS.md "Nested Hyprland").
# Checks over IPC, every 100 ms during each switch: the layer ends on the new image within 2 s (`wallpaper status`), and
# what the lock / desktop clock / bar contrast use (LockWallpapers.stillFor, seen in `lock status`) is always a file that
# exists (never a video still that is still being extracted) and ends on the new one. Pixels (the clock refracting the
# new wallpaper, no flat frame) were checked by hand with frame grabs; this is the cheap regression.
set -u
case "$HOME" in /tmp/*) ;; *) echo "refusing: HOME is not a test home under /tmp"; exit 2 ;; esac
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || { echo "refusing: no nested HYPRLAND_INSTANCE_SIGNATURE"; exit 2; }
pid=$1 a=$2 b=$3 video=${4:-}
theme=(python3 -I "$HOME/.config/theme/theme.py")
ipc() { quickshell ipc --pid "$pid" call "$@"; }
fail=0
stills() { ipc lock status | python3 -I -c 'import json,sys; print("\n".join(s["screen"] + " " + s["still"] for s in json.load(sys.stdin)["screens"]))'; }
switch() {   # switch <label> <file name prefix it must end on> <theme.py apply args...>
    local label=$1 want=$2; shift 2
    "${theme[@]}" apply "$@" >/dev/null 2>&1 &
    local t0 ok=0 i
    t0=$(date +%s%N)
    for i in $(seq 1 40); do
        sleep 0.1
        local st; st=$(ipc wallpaper status)
        # every still a consumer uses must exist (the lock status prints base names: resolve against the state)
        while read -r scr still; do
            [ -z "$still" ] && continue
            if ! find "$HOME/.cache/theme" "$(dirname "$a")" "$(dirname "$b")" ${video:+"$(dirname "$video")"} -maxdepth 3 -name "$still" 2>/dev/null | grep -q .; then
                echo "FAIL $label: $scr uses a missing still $still"; fail=1
            fi
        done < <(stills)
        # done: every layer shows a file starting with `want` (ready) and every consumer uses one too
        if ! grep -qvE "shown=${want}[^ ]* ready$" <<<"$st" && ! stills | awk '{print $2}' | grep -qv "^${want}"; then ok=1; break; fi
    done
    wait
    local ms=$(( ($(date +%s%N) - t0) / 1000000 ))
    if [ $ok = 1 ]; then echo "ok   $label (${ms} ms)"; else echo "FAIL $label: not switched after ${ms} ms"; ipc wallpaper status; stills; fail=1; fi
}
switch "image -> image (setup)" "$(basename "$a")" "$a"
switch "image -> image" "$(basename "$b")" "$b"
if [ -n "$video" ]; then
    switch "image -> loop video (still pending -> still)" "$(basename "${video%.*}")-loop" "$video" --mode loop
    switch "video -> image" "$(basename "$a")" "$a"
fi
exit $fail
