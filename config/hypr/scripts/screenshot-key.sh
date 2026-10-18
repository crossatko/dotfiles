#!/usr/bin/env bash
# CTRL+Print (hyprland/binds.lua): open the Quickshell screenshot menu (ScreenshotMenu.qml,
# `qs ipc call screenshot menu`, toggles). If the shell can't take the call (not running, or the target is
# missing after a failed reload), fall back to a region screenshot so the key never does nothing.
# Test overrides: SHOT_KEY_SCRIPT (screenshot script), SHOT_KEY_QS (qs binary).
shot=${SHOT_KEY_SCRIPT:-$(dirname "$(readlink -f "$0")")/screenshot.sh}
qs=${SHOT_KEY_QS:-qs}
out=$(timeout 3 "$qs" ipc call screenshot menu 2>&1) && [ -z "$out" ] && exit 0
exec "$shot" region
