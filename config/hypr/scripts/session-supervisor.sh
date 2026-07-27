#!/bin/bash
# Run from .zprofile on TTY1 login instead of dropping to an interactive
# shell -- replaces SDDM's own "which session, and start the next one when
# this one ends" role, now that SDDM is disabled entirely (its own VT
# selection and autologin timing turned out to be unreliable for repeated
# session switching -- see plans.md).
#
# Loops forever: reads which session is wanted from a marker file, execs
# it, and whenever that session's own process exits -- a clean switch
# (the "switch to gamescope" keybind, or Steam's "Switch to Desktop") or a
# crash alike -- loops back and checks the marker again for what to start
# next. Defaults to hyprland if the marker is missing (fresh install, or
# never switched away yet), matching the intended cold-boot default.
MARKER="$HOME/.local/state/next-session"
mkdir -p "$(dirname "$MARKER")"

while true; do
	session="$(cat "$MARKER" 2>/dev/null || echo hyprland)"
	case "$session" in
	gamescope)
		start-gamescope-session
		;;
	*)
		start-hyprland
		;;
	esac
done
