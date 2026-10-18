#!/usr/bin/env bash
# SHIFT+Print (hyprland/binds.lua): stop a running recording, otherwise open the Quickshell recording menu
# (RecordMenu.qml, `qs ipc call record menu`, toggles). If the shell can't take the call (not running, or
# the record target is missing after a failed reload), fall back to a region recording so the key never
# does nothing. The recorder itself is screenrec.sh; this only decides what the key does.
# Test overrides: SCREENREC_KEY_RECORDER (recorder script), SCREENREC_KEY_QS (qs binary).
rec=${SCREENREC_KEY_RECORDER:-$(dirname "$(readlink -f "$0")")/screenrec.sh}
qs=${SCREENREC_KEY_QS:-qs}

if "$rec" status >/dev/null 2>&1; then
	exec "$rec" stop
fi
# `qs ipc call` exits 0 but prints "Target not found." / "Function not found." when the shell runs without
# the target, and fails when no shell runs; the menu() call itself prints nothing
out=$(timeout 3 "$qs" ipc call record menu 2>&1) && [ -z "$out" ] && exit 0
exec "$rec" region
