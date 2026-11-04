"""Diacritics preferences written by Settings (the service only reads them, at every request).

    {"key": "...", "model": "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf", "idle_timeout_s": 600, "ignored_classes": [...],
     "show_text": true, "cmd": "diacritics run"}

The service uses model and idle_timeout_s (0 or negative = never unload). A missing file, unreadable JSON or a value
of the wrong type leaves that key at its default; nothing here raises.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass

DEFAULT_MODEL = "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"


@dataclass(frozen=True)
class Prefs:
    model: str = DEFAULT_MODEL
    idle_timeout_s: float = 600.0


def prefs_file() -> str:
    return os.environ.get("DIACRITICS_PREFS_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "diacritics.json")


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
    return Prefs(model=model, idle_timeout_s=float(idle))
