"""Voice preferences from the shell (Settings > Voice writes them): the service re-reads the file at every `begin`.

    {"version": 1, "mic": "", "gpu": true, "idle_timeout_s": 600, "prompt_hints": false, "pause_silence_s": 1.0,
     "trailing_space": true, "gpu_device": 0, "pill_edge": "bar", "lowercase_fragments": true,
     "strip_single_word_punct": true}

mic          PipeWire source name to record from, "" = the system default source
gpu          false = the whisper worker runs on the CPU only (slow); true = GPU or an error, never a silent fallback
idle_timeout_s  seconds without a session before both models are unloaded; 0 or negative = never
gpu_device   which GPU the worker uses when gpu is true: the index of `dictation-whisper --list-devices` (0 = the first,
             the default; a negative number is 0, anything that is not a whole number is 0); an index that does not
             exist is a `gpu-failed` error
pill_edge, pill_gap, pill_x, pill_screen  where the pill sits: read by the shell only, ignored here (pill_bottom = their
             legacy form, also the shell's)
prompt_hints read by the cleanup module, not here
pause_silence_s  seconds of silence after speech that type the words still waiting (the last word); 0 = only on
             release; no UI, the engine default (engine.PAUSE_SILENCE) when missing; clamped to 0.3..10
trailing_space  false = no space after a session's final text (default true: the next dictation starts a new word);
             no UI
lowercase_fragments  false = a single word or short fragment keeps Whisper's capital ("Yes", "Docker compose up");
             default true; no UI
strip_single_word_punct  false = a lone word keeps Whisper's trailing . , ; : … ("Yes." instead of "yes"); "?" and
             "!" always stay; default true; no UI

A missing file, unreadable JSON or a value of the wrong type leaves that key at its default; nothing here raises.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Prefs:
    mic: str = ""
    gpu: bool = True
    idle_timeout_s: float = 600.0
    prompt_hints: bool = False
    pause_silence_s: float | None = None  # None = the engine's default
    trailing_space: bool = True
    gpu_device: int = 0
    lowercase_fragments: bool = True
    strip_single_word_punct: bool = True


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
    pause = saved.get("pause_silence_s")
    if isinstance(pause, bool) or not isinstance(pause, (int, float)) or pause != pause:
        pause = None
    elif pause > 0:
        pause = min(10.0, max(0.3, float(pause)))
    else:
        pause = 0.0
    space = saved.get("trailing_space", d.trailing_space)
    device = saved.get("gpu_device", d.gpu_device)
    if isinstance(device, float) and device == device and abs(device) != float("inf") and device == int(device):
        device = int(device)  # 1.0 from a JSON writer that does not distinguish integers
    if isinstance(device, bool) or not isinstance(device, int):
        device = d.gpu_device
    device = min(1000, max(0, device))  # negative = the first GPU
    lower = saved.get("lowercase_fragments", d.lowercase_fragments)
    strip = saved.get("strip_single_word_punct", d.strip_single_word_punct)
    return Prefs(mic.strip(), gpu if isinstance(gpu, bool) else d.gpu, float(idle),
                 hints if isinstance(hints, bool) else d.prompt_hints, pause,
                 space if isinstance(space, bool) else d.trailing_space, device,
                 lower if isinstance(lower, bool) else d.lowercase_fragments,
                 strip if isinstance(strip, bool) else d.strip_single_word_punct)
