"""The languages whisper can transcribe (languages.json) and the session modes built from them.

A mode is a language code ("cs", "ja": dictate in it), "auto" (detect the language, then pin it) or "translate:<code>" (speak it, type English; whisper can only
translate into English; "translate:auto" detects it first). Plain "translate" is "translate:cs" (the first translate key). A code outside the list is
refused, so nothing unvalidated reaches the recognizer."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass

LANGUAGES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "languages.json")


def _load() -> dict:
    with open(LANGUAGES_FILE, encoding="utf-8") as f:
        return dict(json.load(f)["languages"])


NAMES = _load()  # code -> English name


AUTO = "auto"  # mode: the language is detected once per session (engine._detect), then pinned


def is_language(code) -> bool:
    return isinstance(code, str) and code in NAMES


@dataclass(frozen=True)
class Mode:
    name: str
    language: str
    translate: bool


def parse_mode(name) -> Mode | None:
    """The Mode for a mode string, None when it is not one."""
    if not isinstance(name, str):
        return None
    if name == AUTO:
        return Mode(name, AUTO, False)
    if name == "translate":
        return Mode(name, "cs", True)
    if name.startswith("translate:"):
        code = name[len("translate:"):]
        if code == AUTO:  # detect the language once, pin it, then translate
            return Mode(name, AUTO, True)
        return Mode(name, code, True) if is_language(code) and code != "en" else None
    return Mode(name, name, False) if is_language(name) else None


def clean_languages(value) -> tuple:
    """A list (or a comma separated string) of language codes -> the valid, distinct ones in order."""
    if isinstance(value, str):
        value = value.split(",")
    if not isinstance(value, (list, tuple)):
        return ()
    out = []
    for code in value:
        if is_language(code) and code not in out:
            out.append(code)
    return tuple(out)
