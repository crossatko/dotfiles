"""Client side: talk to the service socket, start the user unit when it is not running."""
from __future__ import annotations

import json
import socket
import subprocess
import time

from .service import default_socket

CONNECT_WAIT = 10.0


def connect(path: str | None = None, start: bool = True) -> socket.socket:
    """A connected socket; starts diacritics.service first when nothing listens (not for a DIACRITICS_SOCK override)."""
    import os
    path = path or default_socket()
    started = False
    deadline = time.monotonic() + CONNECT_WAIT
    while True:
        s = socket.socket(socket.AF_UNIX)
        try:
            s.connect(path)
            return s
        except OSError:
            s.close()
            if not start or os.environ.get("DIACRITICS_SOCK") or time.monotonic() > deadline:
                raise
            if not started:
                subprocess.run(["systemctl", "--user", "start", "diacritics.service"], check=False)
                started = True
            time.sleep(0.1)


def request(req: dict, path: str | None = None) -> dict:
    with connect(path) as s:
        s.sendall(json.dumps(req, ensure_ascii=False).encode() + b"\n")
        with s.makefile("rb") as f:
            return json.loads(f.readline())


def fix(text: str, path: str | None = None) -> dict:
    return request({"op": "fix", "text": text}, path)
