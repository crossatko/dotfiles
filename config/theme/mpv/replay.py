"""Replay hot path (every workspace change): `python3 -I -S replay.py <connector>`.

Replays a held play-once clip on that monitor (the next baked burst; winddown.lua `winddown-restart`). A clip that is
still playing or winding down is left alone (the debounce: a burst of workspace switches cannot stack restarts), as are
loop players, dead players and monitors without one. `theme.py video replay <connector>` runs this file.

Kept tiny on purpose: it starts in ~5 ms where theme.py needs ~50 ms (compiling the 4k-line script, json/re/subprocess
imports). Only `_socket`, no json: the state file is theme.py's own json.dumps output (vp_start) and mpv's IPC replies
are compact one-line JSON, so substring checks are exact here.
"""
import os
import sys

import _socket

OK = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")   # theme.py CONN_RE


def replay(conn):
    if not 0 < len(conn) <= 40 or not OK.issuperset(conn):
        return False
    d = (os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/theme-{os.getuid()}") + "/theme-video/"
    try:
        with open(d + conn + ".json") as f:
            st = f.read()
        if '"mode": "once"' not in st:
            return False
        pid = st.partition('"pid": ')[2].partition(",")[0]
        if not pid.isdigit():
            return False
        with open(f"/proc/{pid}/comm") as f:
            if f.read().strip() != "mpvpaper":
                return False
    except OSError:
        return False
    s = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect(d + conn + ".sock")
        buf = b""

        def reply(rid):   # the reply line of request `rid` (events may be interleaved), None on EOF
            nonlocal buf
            tag = b'"request_id":%d' % rid
            while True:
                *lines, rest = buf.split(b"\n")
                for i, ln in enumerate(lines):
                    if tag in ln:
                        buf = b"\n".join(lines[i + 1:] + [rest])
                        return ln
                chunk = s.recv(4096)
                if not chunk:
                    return None
                buf += chunk

        s.sendall(b'{"command":["get_property","pause"],"request_id":7}\n')
        r = reply(7)
        if not r or b'"error":"success"' not in r or b'"data":true' not in r:   # playing, winding down, or unreachable
            return False
        s.sendall(b'{"command":["script-message","winddown-restart"],"request_id":8}\n')
        reply(8)
        return True
    except OSError:
        return False
    finally:
        s.close()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        replay(sys.argv[1])
