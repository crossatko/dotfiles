"""Client side: talk to the service socket, start the user unit when it is not running."""
from __future__ import annotations

import json
import socket
import subprocess
import time

from .paths import socket_path

CONNECT_WAIT = 10.0
CONNECT_TIMEOUT = 1.0


def connect(path: str | None = None, start: bool = True, timeout: float | None = None) -> socket.socket:
    """A connected socket (I/O timeout `timeout`, None = blocking); starts diacritics.service first when nothing
    listens (not for a DIACRITICS_SOCK override, and not with start=False)."""
    import os
    path = path or socket_path()
    started = False
    deadline = time.monotonic() + CONNECT_WAIT
    while True:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(CONNECT_TIMEOUT)
        try:
            s.connect(path)
            s.settimeout(timeout)
            return s
        except OSError:
            s.close()
            if not start or os.environ.get("DIACRITICS_SOCK") or time.monotonic() > deadline:
                raise
            if not started:
                try:
                    subprocess.run(["systemctl", "--user", "start", "diacritics.service"], check=False, timeout=10,
                                   capture_output=True)
                except (OSError, subprocess.SubprocessError):
                    pass
                started = True
            time.sleep(0.1)


def request(req: dict, path: str | None = None, timeout: float | None = None, start: bool = True) -> dict:
    """One JSON line out, one back. Raises OSError (incl. timeouts) or ValueError on any trouble."""
    with connect(path, start, timeout) as s:
        s.sendall(json.dumps(req, ensure_ascii=False).encode() + b"\n")
        with s.makefile("rb") as f:
            return json.loads(f.readline())


def fix(text: str, path: str | None = None) -> dict:
    return request({"op": "fix", "text": text}, path)
