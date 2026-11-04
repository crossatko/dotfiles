"""The diacritics service: a unix socket around an on-demand llama-server.

Protocol: newline-delimited JSON, one request per connection except subscribe.

    {"op":"fix","text":"..."}        -> {"ok":true,"text":"..."} | {"ok":false,"error":"timeout|server|empty|busy|toolong|truncated"}
    {"op":"state","state":"unsupported"|"failed"}   set a transient state (the key flow, for terminals and failures)
    {"op":"subscribe"}               stream {"event":"state","state":"idle|loading|working|done|failed|unsupported",
                                     "text":"<the text being fixed: in the first working event and in what a late subscriber
                                     gets, not in the later partial events>",
                                     "fixed":"<while working: the part of the fixed text finished so far (whole words only,
                                     plain text, absent until the first word); on done: the fixed text>"}; the current state first
    {"op":"status"}                  -> {"ok":true,"state":"...","model_loaded":bool,"model":"file.gguf"}

llama-server starts on the first fix (state loading), is restarted when it died or the model preference changed, and
is stopped after idle_timeout_s without a fix (at most 1 s: right after the fix, prefs.unload_due). Fixes run one at a time: a second one waits up to QUEUE_WAIT seconds
for the first, then gets `busy`. After done, failed or unsupported the state returns to idle after IDLE_RETURN s.
The text is sent without its leading and trailing whitespace, which is put back unchanged; of the reply only one
trailing newline the model added is dropped. User Corrections (words.py): the entries relevant to the text are added to the system
prompt, the `always` ones are also applied to the reply.
"""
from __future__ import annotations

import json
import os
import queue
import re
import signal
import socket
import sys
import threading
import time

from . import htmlmode, paths, words
from . import prefs as prefs_mod
from .llama import LlamaServer, ServerError, check_fits, read_prompt

IDLE_RETURN = 1.2
QUEUE_WAIT = 30.0
PUSHABLE = ("unsupported", "failed")
PARTIAL_INTERVAL = 0.06  # s between partial `fixed` events while working
SEND_TIMEOUT = 2.0       # s one write to a subscriber may take before it is dropped
QUEUE_MAX = 256          # events a subscriber may be behind


default_socket = paths.socket_path


def log_file() -> str:
    return os.path.join(paths.runtime_dir(), "diacritics-llama.log")


def restore_whitespace(text: str, reply: str) -> str:
    """The fixed text: the original's outer whitespace around the model's reply (one trailing newline of it dropped)."""
    core = text.strip()
    lead = text[:text.index(core[0])] if core else ""
    trail = text[len(lead) + len(core):]
    if reply.endswith("\n"):
        reply = reply[:-1]
    return lead + reply + trail


def keep_spacing(text: str, result: str) -> str:
    """The model collapses double spaces and blank lines. When the result has the same words as the original, put the
    original whitespace between them back (the spec: spaces and newlines exactly as typed). Other results stay as they are."""
    words = result.split()
    pieces = re.split(r"(\s+)", text)
    if len(words) != len(text.split()):
        return result
    it = iter(words)
    return "".join(p if p == "" or p.isspace() else next(it) for p in pieces)


def finished_words(reply: str, html: bool = False) -> str:
    """The plain text of the reply so far without its last, possibly unfinished word (the whole reply when it ends in
    whitespace). HTML: an unfinished tag or character reference at the end is cut off first, then the plain text is derived."""
    if html:
        i = reply.rfind("<")
        if i >= 0 and ">" not in reply[i:]:
            reply = reply[:i]
        m = re.search(r"&#?[A-Za-z0-9]*$", reply)   # an unfinished character reference at the very end
        if m:
            reply = reply[:m.start()]
        reply = htmlmode.to_plain(reply)
    m = re.search(r"\s\S*$", reply)
    return reply[:m.start()] if m else ""


class Subscriber:
    """One subscribed connection with its own writer thread and a bounded queue: the fix never waits for a slow reader. A reader
    that stalls (SEND_TIMEOUT on one write) or falls QUEUE_MAX events behind is dropped."""

    def __init__(self, conn: socket.socket, on_dead):
        self.conn, self.on_dead = conn, on_dead
        self.q: queue.Queue = queue.Queue(maxsize=QUEUE_MAX)
        conn.settimeout(SEND_TIMEOUT)
        threading.Thread(target=self.run, daemon=True).start()

    def push(self, data: bytes) -> bool:
        """Never blocks; False = the reader is too far behind (the caller drops it)."""
        try:
            self.q.put_nowait(data)
            return True
        except queue.Full:
            return False

    def run(self) -> None:
        while True:
            data = self.q.get()
            if data is None:
                return
            try:
                self.conn.sendall(data)
            except OSError:
                self.on_dead(self)
                return

    def close(self) -> None:
        try:
            self.q.put_nowait(None)
        except queue.Full:
            pass
        try:
            self.conn.close()
        except OSError:
            pass


class Service:
    def __init__(self, path: str, load_prefs=prefs_mod.load, server_factory=LlamaServer, load_words=words.load):
        self.path = path
        self.load_words = load_words
        self.load_prefs = load_prefs
        self.server_factory = server_factory
        self.server = None
        self.state, self.text, self.fixed = "idle", "", ""
        self.gen = 0
        self.subs: list[Subscriber] = []
        self.lock = threading.Lock()      # state, subscribers (held only to queue events, never for a socket write)
        self.dead_lock = threading.Lock()  # subs list edits from writer threads
        self.fix_lock = threading.Lock()  # one fix at a time; also guards the server process
        self.last_used = time.monotonic()
        self.stopping = threading.Event()

    # state ------------------------------------------------------------------------------------------------------

    def event(self, partial: bool = False) -> bytes:
        """The current state as one event line. While working the original `text` is in every full event (the first one and what a
        late subscriber gets); a `partial` event carries only `fixed`."""
        ev = {"event": "state", "state": self.state}
        if self.state == "working":
            if not partial:
                ev["text"] = self.text
            if self.fixed:
                ev["fixed"] = self.fixed
        elif self.state == "done":
            ev["fixed"] = self.fixed
        return json.dumps(ev, ensure_ascii=False).encode() + b"\n"

    def set_state(self, state: str, text: str = "", fixed: str = "") -> None:
        with self.lock:
            self.state, self.text, self.fixed = state, text, fixed
            self.gen += 1
            gen = self.gen
            data = self.event()
            self.broadcast(data)
        if state in ("done", "failed", "unsupported"):
            t = threading.Timer(IDLE_RETURN, self.back_to_idle, (gen,))
            t.daemon = True
            t.start()

    def broadcast(self, data: bytes) -> None:
        """Queue `data` for every subscriber (self.lock held); one that is too far behind is dropped."""
        for sub in list(self.subs):
            if not sub.push(data):
                self.drop(sub)

    def drop(self, sub: Subscriber) -> None:
        with self.dead_lock:
            if sub in self.subs:
                self.subs.remove(sub)
        sub.close()

    def set_partial(self, fixed: str) -> None:
        """While working: the fixed text finished so far, sent to the subscribers (late ones get it with the state)."""
        with self.lock:
            if self.state != "working":
                return
            self.fixed = fixed
            data = self.event(partial=True)
            self.broadcast(data)

    def partial_sink(self, html: bool):
        """The on_delta callback of a request: sends the whole words finished so far, at most every PARTIAL_INTERVAL and only
        when at least one more word is complete."""
        last = [0.0, 0]  # time of the last event, words in it

        def sink(reply: str) -> None:
            now = time.monotonic()
            if now - last[0] < PARTIAL_INTERVAL:
                return
            part = finished_words(reply, html)
            n = len(part.split())
            if n <= last[1]:
                return
            last[0], last[1] = now, n
            self.set_partial(part)
        return sink

    def back_to_idle(self, gen: int) -> None:
        if self.gen == gen:  # nothing newer happened meanwhile
            self.set_state("idle")

    # fix --------------------------------------------------------------------------------------------------------

    def ensure_server(self, model: str) -> None:
        if self.server is not None and self.server.alive() and self.server.model == model:
            return
        if self.server is not None:
            self.server.stop()
        self.set_state("loading")
        self.server = self.server_factory(model)
        self.server.start(log_file())

    def fix(self, text: str, fmt: str = "text") -> dict:
        html = fmt == "html"
        if not text.strip():
            return {"ok": True, "text": text}
        if not self.fix_lock.acquire(timeout=QUEUE_WAIT):
            return {"ok": False, "error": "busy"}
        try:
            try:
                entries = self.load_words()
                known = words.relevant(entries, htmlmode.to_plain(text) if html else text)
                system = read_prompt(fmt) + words.prompt_block(known, html)
                check_fits(system, text.strip())  # before the model loads: too long means nothing is sent
                self.ensure_server(self.load_prefs().model)
                self.set_state("working", htmlmode.to_plain(text) if html else text)
                reply = self.server.complete(system, text.strip(), on_delta=self.partial_sink(html))
                if not reply.strip():
                    raise ServerError("empty")
                result = restore_whitespace(text, reply)
                if not html:
                    result = keep_spacing(text, result)
                result = words.apply_always(result, known, html)
                if html and not htmlmode.same_markup(text, result):
                    print("diacritics: markup changed by the model, result dropped", file=sys.stderr, flush=True)
                    self.set_state("failed")
                    return {"ok": False, "error": "markup"}
            except Exception as exc:    # whatever goes wrong, the state must end in failed
                if not isinstance(exc, ServerError):
                    exc = ServerError("server", f"{type(exc).__name__}: {exc}")
                print(f"diacritics: {exc.code}: {exc}", file=sys.stderr, flush=True)
                if exc.code != "empty" and self.server is not None and not self.server.alive():
                    self.server = None
                self.set_state("failed")
                return {"ok": False, "error": exc.code}
            self.set_state("done", fixed=htmlmode.to_plain(result) if html else result)
            return {"ok": True, "text": result}
        finally:
            if self.state in ("loading", "working"):    # left by something that is not an Exception: never stay stuck
                self.set_state("failed")
            self.last_used = time.monotonic()
            self.fix_lock.release()

    def reap_idle(self) -> None:
        while not self.stopping.wait(0.5):
            self.reap_once()

    def reap_once(self, now: float | None = None) -> None:
        """Stop llama-server when it died or was idle long enough (prefs.unload_due; never during a fix)."""
        if self.server is None or not self.fix_lock.acquire(blocking=False):
            return
        try:
            idle = self.load_prefs().idle_timeout_s
            idle_for = (time.monotonic() if now is None else now) - self.last_used
            if self.server is not None and (not self.server.alive() or prefs_mod.unload_due(idle, idle_for)):
                self.server.stop()
                self.server = None
        finally:
            self.fix_lock.release()

    # socket -----------------------------------------------------------------------------------------------------

    def status(self) -> dict:
        loaded = self.server is not None and self.server.alive()
        return {"ok": True, "state": self.state, "model_loaded": loaded,
                "model": self.server.model if loaded else self.load_prefs().model}

    def handle(self, conn: socket.socket) -> None:
        keep = False
        try:
            with conn.makefile("rb") as f:
                line = f.readline()
            try:
                req = json.loads(line)
                op = req.get("op") if isinstance(req, dict) else None
            except ValueError:
                req, op = {}, None
            if op == "fix" and isinstance(req.get("text"), str):
                reply = self.fix(req["text"], "html" if req.get("format") == "html" else "text")
            elif op == "state" and req.get("state") in PUSHABLE:
                if self.state not in ("loading", "working") or not self.fix_lock.locked():   # (a state stuck without a fix is replaced)
                    self.set_state(req["state"])
                reply = {"ok": True}
            elif op == "status":
                reply = self.status()
            elif op == "subscribe":
                sub = Subscriber(conn, self.drop)
                with self.lock:
                    sub.push(self.event())
                    with self.dead_lock:
                        self.subs.append(sub)
                keep = True
                return
            else:
                reply = {"ok": False, "error": "request"}
            conn.sendall(json.dumps(reply, ensure_ascii=False).encode() + b"\n")
        except OSError:
            pass
        finally:
            if not keep:
                conn.close()

    def serve(self) -> None:
        probe = socket.socket(socket.AF_UNIX)
        try:
            probe.connect(self.path)
            sys.exit(f"diacritics: already running ({self.path})")
        except OSError:
            pass
        finally:
            probe.close()
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
        srv = socket.socket(socket.AF_UNIX)
        old = os.umask(0o077)
        try:
            srv.bind(self.path)
        finally:
            os.umask(old)
        srv.listen(16)

        def stop(*_):
            self.stopping.set()
            srv.close()

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        threading.Thread(target=self.reap_idle, daemon=True).start()
        try:
            while not self.stopping.is_set():
                try:
                    conn, _ = srv.accept()
                except OSError:
                    break
                threading.Thread(target=self.handle, args=(conn,), daemon=True).start()
        finally:
            self.stopping.set()
            if self.server is not None:
                self.server.stop()
            try:
                os.unlink(self.path)
            except OSError:
                pass
