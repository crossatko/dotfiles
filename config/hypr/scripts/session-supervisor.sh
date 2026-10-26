#!/bin/bash
# Run from .zprofile on TTY1 login instead of dropping to an interactive
# shell -- replaces SDDM's own "which session, and start the next one when
# this one ends" role, now that SDDM is disabled entirely (its own VT
# selection and autologin timing turned out to be unreliable for repeated
# session switching).
#
# Loops forever: reads which session is wanted from a marker file, execs
# it, and whenever that session's own process exits -- a clean switch
# (the "switch to gamescope" keybind, or Steam's "Switch to Desktop") or a
# crash alike -- loops back and checks the marker again for what to start
# next.
MARKER="$HOME/.local/state/next-session"
mkdir -p "$(dirname "$MARKER")"

# This script only runs once per boot (getty autologin -> .zprofile), so
# resetting the marker here -- not just relying on "missing -> hyprland"
# -- is what makes cold boot always land on Hyprland regardless of
# whatever was last selected before shutdown/reboot. Switches made during
# the live session below still work normally: they overwrite the marker
# and the loop re-reads it on the next iteration, this reset only ever
# runs once, before the loop starts.
echo hyprland >"$MARKER"

while true; do
	session="$(cat "$MARKER" 2>/dev/null || echo hyprland)"
	case "$session" in
	gamescope)
		start-gamescope-session
		;;
	kde)
		startplasma-wayland >"$HOME/.local/state/kde-session.log" 2>&1
		;;
	*)
		start-hyprland
		;;
	esac
done
