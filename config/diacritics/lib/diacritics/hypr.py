"""Hyprland helpers for the key flow: the focused window and key sending to a given window.

Keys go through the compositor's `send_shortcut` dispatcher aimed at a window address, so they reach exactly the window
that was focused at key press. Only when that dispatcher demonstrably fails (hyprctl error, a non-"ok" answer) the flow
may fall back to the synthetic-key tool (wtype), which types into whatever is focused at that moment; that is the one
documented exception to "no synthetic keystrokes". The fallback is logged and disabled by DIACRITICS_NO_FALLBACK=1 or
FALLBACK_ENABLED = False.
"""
from __future__ import annotations

import json
import os
import subprocess

HYPRCTL_TIMEOUT_S = 2.0
WTYPE_TIMEOUT_S = 3.0
FALLBACK_ENABLED = True

# evdev keycode + 8 (the XKB keycode), so the shortcut does not depend on the keyboard layout
KEYCODES = {"a": 38, "c": 54, "v": 55}


def fallback_enabled() -> bool:
    return FALLBACK_ENABLED and os.environ.get("DIACRITICS_NO_FALLBACK", "") != "1"


def active_window(run=subprocess.run):
    """(address, class) of the focused window, or None when there is none or hyprctl fails."""
    try:
        out = run(["hyprctl", "-j", "activewindow"], capture_output=True, timeout=HYPRCTL_TIMEOUT_S, check=True).stdout
        data = json.loads(out or b"{}")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    addr = data.get("address") if isinstance(data, dict) else None
    if not addr:
        return None
    return addr, str(data.get("class") or "")


def focused_address(run=subprocess.run):
    win = active_window(run)
    return win[0] if win else None


def send_shortcut(key: str, address: str, mods: str = "CTRL", run=subprocess.run) -> bool:
    """Ctrl+<key> to the window at `address` through Hyprland. True only on an explicit "ok"."""
    code = KEYCODES[key]
    lua = f"hl.dsp.send_shortcut({{mods='{mods}', key='code:{code}', window='address:{address}'}})"
    try:
        res = run(["hyprctl", "dispatch", lua], capture_output=True, timeout=HYPRCTL_TIMEOUT_S, text=True)
    except (OSError, subprocess.SubprocessError):
        return False
    return res.returncode == 0 and res.stdout.strip() == "ok"


def send_synthetic(key: str, run=subprocess.run) -> bool:
    """Fallback: Ctrl+<key> through wtype into the focused window (the caller checks the focus first)."""
    try:
        res = run(["wtype", "-M", "ctrl", "-k", key, "-m", "ctrl"], capture_output=True, timeout=WTYPE_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return False
    return res.returncode == 0
