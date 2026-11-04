"""Diacritics preferences written by Settings (the service only reads them, at every request).

    {"key": "...", "model": "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf", "idle_timeout_s": 600, "ignored_classes": [...],
     "show_text": true, "cmd": "diacritics run"}

The service uses model and idle_timeout_s (0 or negative = never unload), the key flow ignored_classes. A missing file, unreadable JSON or a value
of the wrong type leaves that key at its default; nothing here raises.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass

from . import paths

DEFAULT_MODEL = "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"

# Window classes where the key does nothing (terminals: Ctrl+C there is SIGINT). THE Python-side default, used when the
# file is missing or has no list. It must equal `defaults.ignored_classes` in config/quickshell/DiacriticsPrefs.qml (the
# Settings page default, also written to the file when it is missing); tests/test_ignored_classes.py compares the two.
DEFAULT_IGNORED_CLASSES = (
    "kitty", "foot", "footclient", "alacritty", "ghostty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm",
    "wezterm", "konsole", "org.kde.konsole", "xterm", "uxterm", "urxvt", "st", "terminator",
    "gnome-terminal-server", "org.gnome.ptyxis", "com.gexperts.tilix", "tilix",
    "com.herdr.terminal", "dotfiles.scratchpad",
)


@dataclass(frozen=True)
class Prefs:
    model: str = DEFAULT_MODEL
    idle_timeout_s: float = 600.0
    ignored_classes: tuple = DEFAULT_IGNORED_CLASSES  # lower-case, matched case-insensitively


prefs_file = paths.prefs_file


def load(path: str | None = None) -> Prefs:
    try:
        with open(path or prefs_file(), encoding="utf-8") as f:
            saved = json.load(f)
    except (OSError, ValueError):
        return Prefs()
    if not isinstance(saved, dict):
        return Prefs()
    d = Prefs()
    model = saved.get("model", d.model)
    # a bare file name only: the value ends up in a path
    if not isinstance(model, str) or not model or os.path.basename(model) != model:
        model = d.model
    idle = saved.get("idle_timeout_s", d.idle_timeout_s)
    if isinstance(idle, bool) or not isinstance(idle, (int, float)):
        idle = d.idle_timeout_s
    classes = saved.get("ignored_classes", d.ignored_classes)
    if not isinstance(classes, list) or not all(isinstance(c, str) for c in classes):
        classes = d.ignored_classes  # [] is valid: the user emptied the list
    classes = tuple(c.strip().lower() for c in classes if c.strip())
    return Prefs(model=model, idle_timeout_s=float(idle), ignored_classes=classes)
