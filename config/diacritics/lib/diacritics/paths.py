"""The one place for the runtime/state locations and the environment names of the Python side.

    DIACRITICS_SOCK         the service socket (default $XDG_RUNTIME_DIR/diacritics.sock)
    DIACRITICS_PREFS_FILE   the Settings file (default ${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics.json)
    DIACRITICS_WORDS_FILE   the Corrections file (default ${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics-words.json)

The Quickshell side has its own names (QS_DIACRITICS_SOCKET, QS_DIACRITICS_FILE); a test of both sides sets both.
"""
from __future__ import annotations

import os


def runtime_dir() -> str:
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def state_home() -> str:
    return os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")


def socket_path() -> str:
    return os.environ.get("DIACRITICS_SOCK") or os.path.join(runtime_dir(), "diacritics.sock")


def prefs_file() -> str:
    return os.environ.get("DIACRITICS_PREFS_FILE") or os.path.join(state_home(), "quickshell", "diacritics.json")


def words_file() -> str:
    return os.environ.get("DIACRITICS_WORDS_FILE") or os.path.join(state_home(), "quickshell", "diacritics-words.json")
