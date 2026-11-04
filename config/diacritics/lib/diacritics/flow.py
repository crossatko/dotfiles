"""`diacritics run`: one key press fixes the selected text, or the whole input field when nothing is selected.

Order (the contract is scratchpad/diacritics-tickets/interface.md, "Key flow"):
 1. focused window address + class (hyprctl); an ignored class (terminals) -> the service shows "unsupported", NO key
    is sent, the clipboard is not touched;
 2. save the clipboard, put a unique sentinel on it;
 3. Ctrl+C to that window (Hyprland send_shortcut aimed at the address); a clipboard that still holds the sentinel
    means there was no selection, so Ctrl+A, Ctrl+C;
 4. `fix` through the service socket; any failure leaves the text untouched;
 5. focus unchanged? then the result goes on the clipboard and Ctrl+V to the same window; the saved clipboard comes
    back after PASTE_SETTLE_S, in every outcome (try/finally).

Exit status of main(): 0 done / nothing to do, 1 failed, 2 unsupported window, 3 another run is in progress.

Caveats: after the select-all path a failed or unchanged run leaves the field fully selected (the text is untouched);
only one clipboard type comes back (see clipboard.py); keys are layout-independent keycodes (hypr.KEYCODES).
Test overrides: DIACRITICS_PREFS (prefs file), DIACRITICS_SOCK (socket), DIACRITICS_NO_FALLBACK=1.
"""
from __future__ import annotations

import fcntl
import json
import os
import socket
import subprocess
import sys
import time
import uuid

from . import clipboard, hypr

# timings, seconds
COPY_WAIT_S = 0.6          # wait for the clipboard to change after Ctrl+C when something is selected
SELECT_ALL_COPY_WAIT_S = 1.5  # same after Ctrl+A, Ctrl+C (a big field takes longer)
POLL_S = 0.03
KEY_GAP_S = 0.06           # between Ctrl+A and Ctrl+C, and before Ctrl+V after setting the clipboard
PASTE_SETTLE_S = 0.5       # after Ctrl+V, before the saved clipboard comes back (the app reads it asynchronously)
SERVICE_START_WAIT_S = 6.0
SERVICE_CONNECT_TIMEOUT_S = 1.0
FIX_TIMEOUT_S = 120.0      # the service has its own, shorter timeout; this only stops a hung connection
STATE_TIMEOUT_S = 1.5

DEFAULT_IGNORED = ["kitty", "foot", "Alacritty", "ghostty", "org.wezfurlong.wezterm", "konsole", "xterm"]
SERVICE_UNIT = "diacritics.service"

EXIT_OK, EXIT_FAILED, EXIT_UNSUPPORTED, EXIT_BUSY = 0, 1, 2, 3


def log(msg: str) -> None:
    """stderr plus a small state-dir log; never the user's text."""
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    print(line, file=sys.stderr)
    try:
        path = os.path.join(_state_home(), "quickshell", "diacritics-flow.log")
        if os.path.exists(path) and os.path.getsize(path) > 100_000:
            os.replace(path, path + ".1")
        with open(path, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def _state_home() -> str:
    return os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")


def prefs_path() -> str:
    return os.environ.get("DIACRITICS_PREFS") or os.path.join(_state_home(), "quickshell", "diacritics.json")


def ignored_classes() -> set:
    """Lower-cased ignored classes from the prefs file; defaults when missing or malformed."""
    classes = DEFAULT_IGNORED
    try:
        with open(prefs_path()) as f:
            got = json.load(f).get("ignored_classes")
        if isinstance(got, list) and all(isinstance(c, str) for c in got):
            classes = got
    except (OSError, ValueError, AttributeError):
        pass
    return {c.strip().lower() for c in classes if c.strip()}


# --- service -------------------------------------------------------------------------------------------------------

def socket_path() -> str:
    return os.environ.get("DIACRITICS_SOCK") or os.path.join(
        os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "diacritics.sock")


def _connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(SERVICE_CONNECT_TIMEOUT_S)
    try:
        s.connect(socket_path())
    except OSError:
        s.close()
        raise
    return s


def _connect_starting(start: bool):
    try:
        return _connect()
    except OSError:
        if not start:
            raise
    log("service socket missing, starting " + SERVICE_UNIT)
    try:
        subprocess.run(["systemctl", "--user", "start", SERVICE_UNIT], capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass
    deadline = time.monotonic() + SERVICE_START_WAIT_S
    while True:
        try:
            return _connect()
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.1)


def request(obj: dict, timeout: float, start: bool = True) -> dict:
    """One JSON line out, one back. Raises OSError/ValueError on any trouble."""
    s = _connect_starting(start)
    try:
        s.settimeout(timeout)
        s.sendall(json.dumps(obj).encode() + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        return json.loads(buf.split(b"\n", 1)[0])
    finally:
        s.close()


def tell_state(state: str, start: bool = False) -> None:
    try:
        request({"op": "state", "state": state}, STATE_TIMEOUT_S, start)
    except (OSError, ValueError):
        log(f"could not tell the service state {state}")


def fix_text(text: str):
    """The fixed text, or None on any failure."""
    try:
        resp = request({"op": "fix", "text": text}, FIX_TIMEOUT_S)
    except (OSError, ValueError) as e:
        log(f"fix request failed: {e}")
        return None
    if not resp.get("ok") or not isinstance(resp.get("text"), str) or not resp["text"].strip():
        log(f"service refused: {resp.get('error', 'empty')}")
        return None
    return resp["text"]


# --- keys ----------------------------------------------------------------------------------------------------------

def send_key(key: str, addr: str) -> bool:
    """Ctrl+<key> to the window `addr`. send_shortcut first; only if that fails, and the window is still the focused
    one, the synthetic wtype fallback (logged, switchable off: hypr.fallback_enabled)."""
    if hypr.send_shortcut(key, addr):
        return True
    log(f"send_shortcut failed for ctrl+{key}")
    if not hypr.fallback_enabled():
        return False
    if hypr.focused_address() != addr:
        return False
    log(f"FALLBACK: synthetic ctrl+{key} through wtype into the focused window")
    return hypr.send_synthetic(key)


def wait_for_change(sentinel: str, timeout: float):
    """The clipboard text once it differs from the sentinel, else None after `timeout`."""
    deadline = time.monotonic() + timeout
    while True:
        text = clipboard.read_text()
        if text is not None and text != sentinel:
            return text
        if time.monotonic() >= deadline:
            return None
        time.sleep(POLL_S)


# --- the flow ------------------------------------------------------------------------------------------------------

class Abort(Exception):
    """Stop without touching the field; the message is logged, the pill shows failed."""


def _grab_text(addr: str, sentinel: str) -> str:
    """The selection, or the whole field; "" when there is nothing."""
    if not clipboard.write_text(sentinel) or clipboard.read_text() != sentinel:
        raise Abort("could not set the sentinel on the clipboard")
    if not send_key("c", addr):
        raise Abort("could not send ctrl+c")
    text = wait_for_change(sentinel, COPY_WAIT_S)
    if text is not None:
        return text
    if hypr.focused_address() != addr:
        raise Abort("focus changed before select-all")
    log("no selection, selecting all")
    if not send_key("a", addr):
        raise Abort("could not send ctrl+a")
    time.sleep(KEY_GAP_S)
    if not send_key("c", addr):
        raise Abort("could not send ctrl+c after select-all")
    return wait_for_change(sentinel, SELECT_ALL_COPY_WAIT_S) or ""


def _run(addr: str, state: dict) -> int:
    sentinel = "diacritics-sentinel-" + uuid.uuid4().hex
    text = _grab_text(addr, sentinel)
    if not text.strip():
        log("nothing to fix")
        return EXIT_OK
    result = fix_text(text)
    if result is None:
        raise Abort("fix failed")
    if hypr.focused_address() != addr:
        raise Abort("focus changed during the fix")
    if result == text:
        log("unchanged, not pasting")
        return EXIT_OK
    if not clipboard.write_text(result):
        raise Abort("could not put the result on the clipboard")
    time.sleep(KEY_GAP_S)
    if hypr.focused_address() != addr:
        raise Abort("focus changed before the paste")
    state["pasted"] = True  # from here the app may read the clipboard: restore only after the settle delay
    if not send_key("v", addr):
        raise Abort("could not send ctrl+v")
    return EXIT_OK


def run() -> int:
    win = hypr.active_window()
    if win is None:
        log("no focused window")
        tell_state("failed", start=True)
        return EXIT_FAILED
    addr, cls = win
    if cls.lower() in ignored_classes():
        log(f"ignored window class {cls!r}, no keys sent")
        tell_state("unsupported", start=True)
        return EXIT_UNSUPPORTED
    saved = clipboard.save()
    state = {"pasted": False}
    try:
        return _run(addr, state)
    except Abort as e:
        log(f"aborted: {e}")
        tell_state("failed")
        return EXIT_FAILED
    except Exception as e:  # noqa: BLE001 - whatever happens, the clipboard comes back and the pill says failed
        log(f"error: {type(e).__name__}: {e}")
        tell_state("failed")
        return EXIT_FAILED
    finally:
        if state["pasted"]:
            time.sleep(PASTE_SETTLE_S)
        if not clipboard.restore(saved):
            log("could not restore the clipboard")


def main(argv=None) -> int:
    lock_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "diacritics-flow.lock")
    try:
        lock = open(lock_path, "w")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another run is in progress")
        return EXIT_BUSY
    except OSError:
        lock = None  # no lock file possible: run anyway
    try:
        return run()
    finally:
        if lock:
            lock.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
