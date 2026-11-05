"""Voice preferences from the shell (Settings > Voice writes them): the service re-reads the file at every `begin`.

    {"version": 1, "mic": "", "gpu": true, "idle_timeout_s": 600, "prompt_hints": false,
     "trailing_space": true, "gpu_device": 0, "pill_edge": "bar", "lowercase_fragments": true,
     "strip_single_word_punct": true, "release_tail_s": 0.5}

mic          PipeWire source name to record from, "" = the system default source
gpu          false = the whisper worker runs on the CPU only (slow); true = GPU or an error, never a silent fallback
idle_timeout_s  seconds without a session before both models are unloaded; 0 or negative = never; 0 < x <= UNLOAD_AT_ONCE
             = right after each session (Settings "Immediately" writes 1; an older reader unloads 1 s later, the same in practice)
gpu_device   which GPU the worker uses when gpu is true: the index of `dictation-whisper --list-devices` (0 = the first,
             the default; a negative number is 0, anything that is not a whole number is 0); an index that does not
             exist is a `gpu-failed` error
pill_edge, pill_gap, pill_x, pill_screen  where the pill sits: read by the shell only, ignored here (pill_bottom = their
             legacy form, also the shell's)
prompt_hints read by the cleanup module, not here
trailing_space  false = no space after a session's final text (default true: the next dictation starts a new word);
             no UI
lowercase_fragments  false = a single word or short fragment keeps Whisper's capital ("Yes", "Docker compose up");
             default true; no UI
strip_single_word_punct  false = a lone word keeps Whisper's trailing . , ; : … ("Yes." instead of "yes"); "?" and
             "!" always stay; default true; no UI
release_tail_s  seconds the microphone keeps recording after the key is released, before the final pass runs, so the last
             word is not cut off (it often ends after the key comes up); 0 = stop at once; default RELEASE_TAIL (0.5);
             clamped to 0..2; no UI

A missing file, unreadable JSON or a value of the wrong type leaves that key at its default; nothing here raises.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass


# idle_timeout_s at or below this (and above 0) = unload as soon as a session is over (see idle_timeout_s above)
UNLOAD_AT_ONCE = 1.0
# seconds of audio recorded after the key release (release_tail_s above)
RELEASE_TAIL = 0.5


def unload_due(idle_timeout_s: float, idle_for: float) -> bool:
    """True when the models should go now: idle_for = seconds since the last session ended."""
    if idle_timeout_s <= 0:
        return False
    return idle_timeout_s <= UNLOAD_AT_ONCE or idle_for >= idle_timeout_s


@dataclass(frozen=True)
class Prefs:
    mic: str = ""
    gpu: bool = True
    idle_timeout_s: float = 600.0
    prompt_hints: bool = False
    trailing_space: bool = True
    gpu_device: int = 0
    lowercase_fragments: bool = True
    strip_single_word_punct: bool = True
    release_tail_s: float = RELEASE_TAIL


def prefs_file() -> str:
    return os.environ.get("DICTATION_PREFS_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "dictation-prefs.json")


def load(path: str | None = None) -> Prefs:
    try:
        with open(path or prefs_file(), encoding="utf-8") as f:
            saved = json.load(f)
    except (OSError, ValueError):
        return Prefs()
    if not isinstance(saved, dict):
        return Prefs()
    d = Prefs()
    mic = saved.get("mic", d.mic)
    if not isinstance(mic, str) or any(ord(c) < 32 for c in mic) or len(mic) > 256:
        mic = d.mic
    gpu = saved.get("gpu", d.gpu)
    idle = saved.get("idle_timeout_s", d.idle_timeout_s)
    if isinstance(idle, bool) or not isinstance(idle, (int, float)) or idle != idle:  # bool, text, NaN
        idle = d.idle_timeout_s
    hints = saved.get("prompt_hints", d.prompt_hints)
    space = saved.get("trailing_space", d.trailing_space)
    device = saved.get("gpu_device", d.gpu_device)
    if isinstance(device, float) and device == device and abs(device) != float("inf") and device == int(device):
        device = int(device)  # 1.0 from a JSON writer that does not distinguish integers
    if isinstance(device, bool) or not isinstance(device, int):
        device = d.gpu_device
    device = min(1000, max(0, device))  # negative = the first GPU
    lower = saved.get("lowercase_fragments", d.lowercase_fragments)
    strip = saved.get("strip_single_word_punct", d.strip_single_word_punct)
    tail = saved.get("release_tail_s", d.release_tail_s)
    if isinstance(tail, bool) or not isinstance(tail, (int, float)) or tail != tail:
        tail = d.release_tail_s
    tail = min(2.0, max(0.0, float(tail)))
    return Prefs(mic.strip(), gpu if isinstance(gpu, bool) else d.gpu, float(idle),
                 hints if isinstance(hints, bool) else d.prompt_hints,
                 space if isinstance(space, bool) else d.trailing_space, device,
                 lower if isinstance(lower, bool) else d.lowercase_fragments,
                 strip if isinstance(strip, bool) else d.strip_single_word_punct, tail)
