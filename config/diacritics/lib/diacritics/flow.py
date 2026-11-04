"""`diacritics run`: one key press fixes the selected text, or the whole input field when nothing is selected.

Order:
 1. focused window address + class (hyprctl); an ignored class (terminals) -> the service shows "unsupported", NO key
    is sent, the clipboard is not touched;
 2. save the clipboard, put a unique sentinel on it;
 3. Ctrl+C to that window (Hyprland send_shortcut aimed at the address); a clipboard that still holds the sentinel
    means there was no selection, so Ctrl+A, Ctrl+C;
 3b. HTML mode: when the copy also offers text/html with real markup (htmlmode.has_real_markup), the HTML fragment
    goes to the service as {"op":"fix","text":html,"format":"html"} and the result is pasted as text/html plus a
    text/plain fallback in ONE selection (clipboard.write_html -> wlsel.py); plain text and HTML source typed in a
    plain field stay in the plain mode (the prompt keeps the tags);
 4. `fix` through the service socket; any failure leaves the text untouched;
 5. focus unchanged? then the result goes on the clipboard and Ctrl+V to the same window; the saved clipboard comes
    back after PASTE_SETTLE_S, in every outcome (try/finally).

Exit status of main(): 0 done / nothing to do, 1 failed, 2 unsupported window, 3 another run is in progress.

Caveats: after the select-all path a failed or unchanged run leaves the field fully selected (the text is untouched);
the clipboard comes back with all saved types (clipboard.py); keys are layout-independent keycodes (hypr.KEYCODES).
Test overrides: DIACRITICS_PREFS_FILE, DIACRITICS_SOCK (paths.py), DIACRITICS_NO_FALLBACK=1.
"""
from __future__ import annotations

import fcntl
import os
import sys
import time
import uuid

from . import clipboard, client, htmlmode, hypr, paths, prefs
from .llama import REQUEST_TIMEOUT, START_TIMEOUT
from .service import QUEUE_WAIT

# timings, seconds
COPY_WAIT_S = 0.6          # wait for the clipboard to change after Ctrl+C when something is selected
SELECT_ALL_COPY_WAIT_S = 1.5  # same after Ctrl+A, Ctrl+C (a big field takes longer)
POLL_S = 0.03
KEY_GAP_S = 0.06           # between Ctrl+A and Ctrl+C, and before Ctrl+V after setting the clipboard
PASTE_SETTLE_S = 0.5       # after Ctrl+V, before the saved clipboard comes back (the app reads it asynchronously)
# The flow waits longer than the service can take at worst (queue + cold model load + request), so the service always
# answers first and no "done" can arrive after the flow gave up and left the field alone.
FIX_TIMEOUT_S = QUEUE_WAIT + START_TIMEOUT + REQUEST_TIMEOUT + 15.0
STATE_TIMEOUT_S = 1.5

EXIT_OK, EXIT_FAILED, EXIT_UNSUPPORTED, EXIT_BUSY = 0, 1, 2, 3


def log(msg: str) -> None:
    """stderr plus a small state-dir log; never the user's text."""
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    print(line, file=sys.stderr)
    try:
        path = os.path.join(paths.state_home(), "quickshell", "diacritics-flow.log")
        if os.path.exists(path) and os.path.getsize(path) > 100_000:
            os.replace(path, path + ".1")
        with open(path, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def ignored_classes() -> set:
    """Lower-cased ignored window classes: the Settings file, else the default list (prefs.DEFAULT_IGNORED_CLASSES)."""
    return set(prefs.load().ignored_classes)


# --- service -------------------------------------------------------------------------------------------------------

def tell_state(state: str, start: bool = False) -> None:
    try:
        client.request({"op": "state", "state": state}, timeout=STATE_TIMEOUT_S, start=start)
    except (OSError, ValueError):
        log(f"could not tell the service state {state}")


def fix_text(text: str, fmt: str | None = None):
    """The fixed text, or None on any failure. fmt="html": the text is an HTML fragment, tags stay."""
    req = {"op": "fix", "text": text}
    if fmt:
        req["format"] = fmt
    try:
        resp = client.request(req, timeout=FIX_TIMEOUT_S)
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
    result = hypr.dispatch_shortcut(key, addr)
    if result == hypr.OK:
        return True
    if result == hypr.UNKNOWN:
        # a timeout or an unfamiliar answer: the key may have gone out, so it is never sent a second time
        log(f"send_shortcut for ctrl+{key}: unknown answer, assuming it ran, no fallback")
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
    """The selection, or the whole field (plain text); "" when there is nothing."""
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


def _copied_html():
    """The HTML fragment of the copy when it holds real markup, else None."""
    if "text/html" not in clipboard.list_types():
        return None
    data = clipboard.read("text/html")
    html = htmlmode.strip_wrapper(data.decode("utf-8", "replace")) if data else ""
    if html and htmlmode.has_real_markup(html):
        return html
    return None


def _run(addr: str, state: dict) -> int:
    sentinel = "diacritics-sentinel-" + uuid.uuid4().hex
    text = _grab_text(addr, sentinel)
    if not text.strip():
        log("nothing to fix")
        return EXIT_OK
    html = _copied_html()
    if html is not None:
        log("html mode")
        result = fix_text(html, "html")
        original = html
    else:
        result = fix_text(text)
        original = text
    if result is None:
        raise Abort("fix failed")
    if hypr.focused_address() != addr:
        raise Abort("focus changed during the fix")
    if result == original:
        log("unchanged, not pasting")
        return EXIT_OK
    if html is not None:
        ok = clipboard.write_html(htmlmode.wrap(result), htmlmode.to_plain(result))
    else:
        ok = clipboard.write_text(result)
    if not ok:
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
    saved = clipboard.save(log=log)
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
        if saved is None:
            log("clipboard was unreadable at the start, left as it is")
        elif not clipboard.restore(saved):
            log("could not restore the clipboard")


def main(argv=None) -> int:
    lock_path = os.path.join(paths.runtime_dir(), "diacritics-flow.lock")
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
    finally:  # the lock goes with the file; the clipboard helper (own session, no inherited fds) never holds it
        if lock:
            lock.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
