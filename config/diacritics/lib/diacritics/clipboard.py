"""Clipboard access through wl-clipboard: save, set and restore.

wl-copy offers one MIME type per run, so a restore can bring back one type only. The saved clipboard keeps every type
that fits MAX_SAVE_BYTES; the restore picks the most valuable one: an image if there is one (it cannot be rebuilt from
text), else plain text, else the first type. An empty clipboard is restored as empty (`wl-copy --clear`).
"""
from __future__ import annotations

import subprocess

TIMEOUT_S = 3.0
MAX_SAVE_BYTES = 32 * 1024 * 1024
TEXT_TYPES = ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT")


def list_types(run=subprocess.run) -> list:
    try:
        res = run(["wl-paste", "--list-types"], capture_output=True, timeout=TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return []
    if res.returncode != 0:
        return []
    return [t for t in res.stdout.decode("utf-8", "replace").splitlines() if t.strip()]


def read(mime: str | None = None, run=subprocess.run) -> bytes | None:
    """The clipboard bytes of one type (default: the best text type), None when empty or unreadable."""
    argv = ["wl-paste", "--no-newline"] + (["--type", mime] if mime else ["--type", "text"])
    try:
        res = run(argv, capture_output=True, timeout=TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return None
    return res.stdout if res.returncode == 0 else None


def read_text(run=subprocess.run) -> str | None:
    data = read(None, run)
    return None if data is None else data.decode("utf-8", "replace")


def write(data: bytes, mime: str | None = None, run=subprocess.run) -> bool:
    argv = ["wl-copy"] + (["--type", mime] if mime else [])
    try:
        # wl-copy forks a server that keeps inherited pipes open: never capture its output
        res = run(argv, input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return False
    return res.returncode == 0


def write_text(text: str, run=subprocess.run) -> bool:
    return write(text.encode("utf-8"), "text/plain;charset=utf-8", run)


def clear(run=subprocess.run) -> bool:
    try:
        return run(["wl-copy", "--clear"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=TIMEOUT_S).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def save(run=subprocess.run) -> dict:
    """{mime: bytes} for every readable type within the size budget ({} = empty clipboard); others are skipped."""
    saved, total = {}, 0
    for mime in list_types(run):
        data = read(mime, run)
        if data is None or total + len(data) > MAX_SAVE_BYTES:
            continue
        saved[mime] = data
        total += len(data)
    return saved


def _pick(saved: dict):
    mimes = list(saved)
    for m in mimes:
        if m.startswith("image/"):
            return m
    for want in TEXT_TYPES:
        if want in saved:
            return want
    return mimes[0] if mimes else None


def restore(saved: dict, run=subprocess.run) -> bool:
    mime = _pick(saved)
    if mime is None:
        return clear(run)
    return write(saved[mime], mime, run)
