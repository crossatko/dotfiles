"""The diacritics service: a unix socket around an on-demand llama-server.

Protocol: newline-delimited JSON, one request per connection except subscribe.

    {"op":"fix","text":"..."}        -> {"ok":true,"text":"..."} | {"ok":false,"error":"timeout|server|empty|busy"}
    {"op":"state","state":"unsupported"|"failed"}   set a transient state (the key flow, for terminals and failures)
    {"op":"subscribe"}               stream {"event":"state","state":"idle|loading|working|done|failed|unsupported",
                                     "text":"<the text being fixed, only while working>",
                                     "fixed":"<the fixed text, only on done>"}; the current state first
    {"op":"status"}                  -> {"ok":true,"state":"...","model_loaded":bool,"model":"file.gguf"}

llama-server starts on the first fix (state loading), is restarted when it died or the model preference changed, and
is stopped after idle_timeout_s without a fix. Fixes run one at a time: a second one waits up to QUEUE_WAIT seconds
for the first, then gets `busy`. After done, failed or unsupported the state returns to idle after IDLE_RETURN s.
The text is sent without its leading and trailing whitespace, which is put back unchanged; of the reply only one
trailing newline the model added is dropped.
"""
from __future__ import annotations

import json
import os
import signal
import socket
import sys
import threading
import time

from . import htmlmode
from . import prefs as prefs_mod
from .llama import LlamaServer, ServerError, read_prompt

IDLE_RETURN = 1.2
QUEUE_WAIT = 30.0
PUSHABLE = ("unsupported", "failed")


def default_socket() -> str:
    return os.environ.get("DIACRITICS_SOCK") or os.path.join(
        os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "diacritics.sock")


def log_file() -> str:
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "diacritics-llama.log")


def restore_whitespace(text: str, reply: str) -> str:
    """The fixed text: the original's outer whitespace around the model's reply (one trailing newline of it dropped)."""
    core = text.strip()
    lead = text[:text.index(core[0])] if core else ""
    trail = text[len(lead) + len(core):]
    if reply.endswith("\n"):
        reply = reply[:-1]
    return lead + reply + trail


class Service:
    def __init__(self, path: str, load_prefs=prefs_mod.load, server_factory=LlamaServer):
        self.path = path
        self.load_prefs = load_prefs
        self.server_factory = server_factory
        self.server = None
        self.state, self.text, self.fixed = "idle", "", ""
        self.gen = 0
        self.subs: list[socket.socket] = []
        self.lock = threading.Lock()      # state, subscribers
        self.fix_lock = threading.Lock()  # one fix at a time; also guards the server process
        self.last_used = time.monotonic()
        self.stopping = threading.Event()

    # state ------------------------------------------------------------------------------------------------------

    def event(self) -> bytes:
        ev = {"event": "state", "state": self.state}
        if self.state == "working":
            ev["text"] = self.text
        elif self.state == "done":
            ev["fixed"] = self.fixed
        return json.dumps(ev, ensure_ascii=False).encode() + b"\n"

    def set_state(self, state: str, text: str = "", fixed: str = "") -> None:
        with self.lock:
            self.state, self.text, self.fixed = state, text, fixed
            self.gen += 1
            gen = self.gen
            data = self.event()
            for s in list(self.subs):
                try:
                    s.sendall(data)
                except OSError:
                    self.subs.remove(s)
                    s.close()
        if state in ("done", "failed", "unsupported"):
            t = threading.Timer(IDLE_RETURN, self.back_to_idle, (gen,))
            t.daemon = True
            t.start()

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
                self.ensure_server(self.load_prefs().model)
                self.set_state("working", htmlmode.to_plain(text) if html else text)
                reply = self.server.complete(read_prompt(fmt), text.strip())
                if not reply.strip():
                    raise ServerError("empty")
                result = restore_whitespace(text, reply)
                if html and not htmlmode.same_markup(text, result):
                    print("diacritics: markup changed by the model, result dropped", file=sys.stderr, flush=True)
                    self.set_state("failed")
                    return {"ok": False, "error": "markup"}
            except (ServerError, OSError) as exc:
                if not isinstance(exc, ServerError):
                    exc = ServerError("server", str(exc))
                print(f"diacritics: {exc.code}: {exc}", file=sys.stderr, flush=True)
                if exc.code != "empty" and self.server is not None and not self.server.alive():
                    self.server = None
                self.set_state("failed")
                return {"ok": False, "error": exc.code}
            self.set_state("done", fixed=htmlmode.to_plain(result) if html else result)
            return {"ok": True, "text": result}
        finally:
            self.last_used = time.monotonic()
            self.fix_lock.release()

    def reap_idle(self) -> None:
        while not self.stopping.wait(0.5):
            if self.server is None or not self.fix_lock.acquire(blocking=False):
                continue
            try:
                idle = self.load_prefs().idle_timeout_s
                if self.server is not None and (not self.server.alive() or
                                                (idle > 0 and time.monotonic() - self.last_used >= idle)):
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
                if self.state not in ("loading", "working"):
                    self.set_state(req["state"])
                reply = {"ok": True}
            elif op == "status":
                reply = self.status()
            elif op == "subscribe":
                with self.lock:
                    conn.settimeout(2)
                    conn.sendall(self.event())
                    self.subs.append(conn)
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
