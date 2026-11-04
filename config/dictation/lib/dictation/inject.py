"""Text injection into the focused window: a thin adapter around wtype (Wayland virtual keyboard, handles Czech
diacritics), plus the focused-window probe the engine uses to stop typing when focus moves.

The text goes to wtype on stdin (`wtype -k BackSpace ... -`), never on the command line, so it cannot be read as an
option. Newlines, tabs and control characters are refused here as a second line of defence: the adapter can never
send Enter.

Every wtype run starts with one Hyper_L press and release (a modifier key without a character; wtype sends no modifier
state for it, so nothing is held): while a key that a compositor bind consumed is held (the push-to-talk key),
Hyprland drops the first key event of a new virtual keyboard, which was the first typed character of a session
("Udělal" arrived as "dělal"; kitty and ghostty, Hyprland 0.57). The sacrificial key must be a real keysym: on
VoidSymbol ghostty falls back to the physical key, and wtype's first keycode is evdev 1 = Esc, so it typed ESC.

wtype gives every distinct keysym of a run its own keycode in order of first use (Hyper_L = evdev 1, then BackSpace,
then the characters). ghostty reads some keycodes as their physical key: on evdev 14 (BackSpace) a capital or
accented letter was dropped, from 29 (LeftCtrl) letters turned into Ctrl chords and F-key / keypad codes typed
escape sequences and digits (ghostty 1.4, a Czech sentence lost letters). So a run only uses evdev 1-13: text with
more distinct characters is typed in several runs, the backspaces in the first.

Safety for tests: DICTATION_FORBID_DISPLAY (comma-separated Wayland display names or absolute socket paths) makes the
adapter refuse to type into those displays, so a test harness aimed at a nested compositor can never reach the live
session by mistake.
"""
from __future__ import annotations

import json
import os
import subprocess
import unicodedata


class InjectRefused(RuntimeError):
    pass


def _forbidden(display: str, env=None) -> bool:
    """A bare name (wayland-1) refuses every display of that name; an absolute path refuses only that socket (the
    display resolved against XDG_RUNTIME_DIR), so a nested compositor whose socket has the same name stays usable.
    The list comes from the process environment and from the injector's own environment."""
    envs = [os.environ] + ([env] if env is not None else [])
    names = [d.strip() for e in envs for d in e.get("DICTATION_FORBID_DISPLAY", "").split(",") if d.strip()]
    if not names:
        return False
    base = os.path.basename(display)
    runtime = (env or {}).get("XDG_RUNTIME_DIR") or os.environ.get("XDG_RUNTIME_DIR", "")
    where = os.path.realpath(os.path.join(runtime, display))
    return any(os.path.realpath(n) == where if os.path.isabs(n) else base == n for n in names)


class WtypeInjector:
    LEAD_KEY = "Hyper_L"
    MAX_KEYS = 12  # keycodes per run after the lead key: evdev 2-13

    @classmethod
    def chunks(cls, backspace: int, text: str) -> list:
        """Split the text so that BackSpace (first run only) plus each run's distinct characters fit MAX_KEYS."""
        out, cur, seen = [], [], set()
        budget = cls.MAX_KEYS - (1 if backspace else 0)
        for c in text:
            if c not in seen and len(seen) == budget:
                out.append("".join(cur))
                cur, seen, budget = [], set(), cls.MAX_KEYS
            seen.add(c)
            cur.append(c)
        if cur or not out:
            out.append("".join(cur))
        return out

    def __init__(self, *, cmd: str = "wtype", delay_ms: int = 0, env: dict | None = None, run=subprocess.run):
        self.cmd = cmd
        self.delay_ms = delay_ms
        self.env = env
        self._run = run

    def argv(self, backspace: int, text: str) -> list:
        if backspace < 0:
            raise ValueError("negative backspace")
        if any(c in "\n\r\t" or unicodedata.category(c) in ("Cc", "Cf", "Zl", "Zp") for c in text):
            raise InjectRefused("refusing to type a newline, tab or control character")
        if text and (text.endswith("  ") or text.rstrip(" ") != text.rstrip() or text.strip() == ""
                     and len(text) > 1):
            raise InjectRefused("refusing to type trailing whitespace other than one space")
        if not backspace and not text:
            return [self.cmd]
        argv = [self.cmd]
        if self.delay_ms:
            argv += ["-d", str(self.delay_ms)]
        argv += ["-k", self.LEAD_KEY] + ["-k", "BackSpace"] * backspace
        if text:
            argv.append("-")
        return argv

    def apply(self, backspace: int, text: str) -> None:
        argv = self.argv(backspace, text)
        if len(argv) == 1:
            return
        env = self.env if self.env is not None else os.environ
        display = env.get("WAYLAND_DISPLAY", "")
        if not display:
            raise InjectRefused("WAYLAND_DISPLAY is not set")
        if _forbidden(display, self.env):
            raise InjectRefused(f"refusing to type into forbidden display {display}")
        more = self.argv(0, "x")  # a later run: lead key, text on stdin, no backspaces
        for i, part in enumerate(self.chunks(backspace, text)):
            self._run(argv if i == 0 else more, input=part.encode(), env=self.env, check=True, timeout=15,
                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def hyprland_focus(run=subprocess.run):
    """Address of the focused Hyprland window, or None when it cannot be told (then focus checks compare None)."""
    try:
        out = run(["hyprctl", "-j", "activewindow"], capture_output=True, timeout=2, check=True).stdout
        return json.loads(out or b"{}").get("address")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
