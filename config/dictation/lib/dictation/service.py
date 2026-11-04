"""The persistent dictation service: a unix socket control interface around the engine.

Protocol: newline-delimited, both directions. Every connected client receives every event as one JSON object per
line. Commands are either JSON ({"cmd": "begin", "mode": "cs"}) or plain words ("begin cs"):

    begin cs|en|translate    start a session (opens the mic); ignored while one is running
    end                      key released: final pass, flush the rest, close the mic
    cancel                   drop the session without typing anything more
    status                   reply (to this client only) with a status event

Final-pass retry: when the final pass fails (worker crash, hang, GPU error) the session is kept (audio, typed text), an
informational `retry {what: "final", message, code}` event is broadcast, a fresh worker is loaded and the final pass
runs again over the whole audio, once. On success the `final` event carries `retried: true`. If the retry fails too (or
exceeds `retry_timeout`, 30 s by default) an error event follows and nothing more is typed. Cancel, owner disconnect
and SIGTERM abandon the final pass or its retry at once.

Events: status {state: loading|idle|listening|finishing|error, mode, error, code}, state, level {value 0..1},
preview {text}, edit {backspace, text}, pass {slot, ms, audio}, final {text}, aborted {reason}, error {message, code}.
Error codes: no-model, worker, mic, mode, command, error (anything else). mode / command errors (a bad command) go only
to the client that sent it; every other event is broadcast.

Models: `models_key()` (optional) says which models are wanted now (e.g. the shell's choice). Every begin compares it
with the loaded one and reloads on a change; a begin while nothing is loaded (a missing model, a failed worker) tries
to load again first, so a model downloaded later works without restarting the service.
"""
from __future__ import annotations

import asyncio
import json
import os
import queue
import signal
import socket
import threading
import time

from .engine import MODES, Config, Dictation, RecognizerError, identity_cleanup
from .whisper import WorkerFailed


def error_code(exc: BaseException) -> str:
    code = getattr(exc, "code", None)
    if isinstance(code, str) and code:
        return code
    return "worker" if isinstance(exc, RecognizerError) else "error"


def default_socket() -> str:
    return os.environ.get("DICTATION_SOCKET") or os.path.join(
        os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "dictation.sock")


def parse_command(line: str) -> dict | None:
    line = line.strip()
    if not line:
        return None
    if line.startswith("{"):
        try:
            cmd = json.loads(line)
        except ValueError:
            return {"cmd": "invalid"}
        return cmd if isinstance(cmd, dict) else {"cmd": "invalid"}
    parts = line.split()
    cmd = {"cmd": parts[0]}
    if len(parts) > 1:
        cmd["mode"] = parts[1]
    return cmd


class CaptureFailed(RuntimeError):
    code = "mic"


class _Intake:
    """Where the recorder delivers audio. Until a session's engine is ready (models loading) the audio is buffered;
    attach() hands the backlog to the engine in order and everything after it directly, so no speech is lost while a
    model (re)loads."""

    LIMIT = 16000 * 4 * 120  # two minutes: a load that takes longer is broken anyway

    def __init__(self):
        self._lock = threading.Lock()
        self._sink = None
        self._buf = bytearray()

    def __call__(self, pcm: bytes) -> None:
        with self._lock:
            if self._sink is not None:
                self._sink(pcm)
            elif len(self._buf) < self.LIMIT:
                self._buf += pcm

    def attach(self, sink) -> None:
        with self._lock:
            if self._buf:
                sink(bytes(self._buf))
                self._buf.clear()
            self._sink = sink

    @property
    def buffered(self) -> int:
        return len(self._buf)


class Service:
    def __init__(self, socket_path, make_recognizer, injector, focus, make_capture, *,
                 cleanup=identity_cleanup, config: Config | None = None, max_session: float = 300.0,
                 models_key=None, prefs=None, clock=time.monotonic, retry_timeout: float = 30.0):
        # make_capture(on_pcm, mode) -> object with start(), stop() and optionally `failed` (a message once the
        # capture died on its own, e.g. the mic went away). The capture starts before the models are loaded.
        # prefs() -> prefs.Prefs, read at every begin (and now and then while idle, for the idle timeout); None = defaults.
        # The models load on the first begin and unload after prefs.idle_timeout_s without a session; `clock` is the
        # idle timer's time source (monotonic seconds). retry_timeout: seconds the retry of a failed final pass (worker
        # reload + the pass) may take before it is abandoned with a worker error.
        self.socket_path = socket_path
        self.make_recognizer = make_recognizer
        self.make_capture = make_capture
        self.models_key = models_key
        self._prefs_source = prefs
        self._clock = clock
        self.retry_timeout = retry_timeout
        self._retry_lock = threading.Lock()
        self._abandoned = threading.Event()
        self._loaded_key = None
        self.max_session = max_session
        self._loop: asyncio.AbstractEventLoop | None = None
        self._clients: set = set()
        self._commands: queue.Queue = queue.Queue()
        self._stop = threading.Event()
        self._state = "idle"
        self._error = None
        self._code = None
        self._recognizer = None
        self._capture = None
        self._intake = None
        self._owner = None  # the client whose begin started the session; its disconnect cancels it
        self._restarted = False  # the worker was restarted once during this session
        self._idle_timeout = 0.0
        self._last_activity = 0.0
        self._prefs_read = 0.0
        self._started = 0.0
        self._injector, self._focus, self._cleanup, self._config = injector, focus, cleanup, config
        self.engine: Dictation | None = None
        self._stop_async: asyncio.Event | None = None

    # --- events (any thread) ---

    def emit(self, event: dict) -> None:
        if event.get("event") == "state":
            self._state = event["state"]
        loop = self._loop
        if loop is not None and not loop.is_closed():
            loop.call_soon_threadsafe(self._broadcast, event)

    def status(self) -> dict:
        engine = self.engine  # read once: the controller thread may swap it during a reload
        return {"event": "status", "state": self._state, "mode": engine.mode if engine else None,
                "error": self._error, "code": self._code, "loaded": engine is not None}

    def _set_state(self, state: str) -> None:
        self._state = state
        self.emit(self.status())

    def _broadcast(self, event: dict) -> None:
        line = (json.dumps(event, ensure_ascii=False) + "\n").encode()
        for writer in list(self._clients):
            if writer.transport.get_write_buffer_size() > 1 << 20:  # a client that stopped reading
                self._clients.discard(writer)
                writer.close()
                continue
            writer.write(line)

    # --- controller thread: owns the engine, the recognizer and the capture ---

    def _wanted(self):
        if self.models_key is None:
            return None
        try:
            return self.models_key()
        except Exception as exc:  # an unreadable choice is the loader's error to report
            return ("unreadable", str(exc))

    def _read_prefs(self):
        try:
            prefs = self._prefs_source() if self._prefs_source else None
        except Exception:
            prefs = None
        self._prefs_read = self._clock()
        self._idle_timeout = float(prefs.idle_timeout_s) if prefs else 0.0
        return prefs

    def _close_recognizer(self) -> None:
        recognizer, self._recognizer = self._recognizer, None
        if recognizer is not None and hasattr(recognizer, "close"):
            try:
                recognizer.close()
            except Exception:
                pass

    def _unload(self) -> None:
        """Stop the worker: its memory (RAM and GPU) goes back to the system. The next begin loads again."""
        self._close_recognizer()
        self.engine, self._loaded_key = None, None
        self._error = self._code = None
        self._set_state("idle")

    def _load(self) -> None:
        self._loaded_key = self._wanted()
        self._close_recognizer()
        self.engine = None
        self._set_state("loading")
        try:
            self._recognizer = self.make_recognizer()
            self.engine = Dictation(self._recognizer, self._injector, focus=self._focus, emit=self.emit,
                                    cleanup=self._cleanup, config=self._config)
            self._error = self._code = None
            self._last_activity = self._clock()
            self._set_state("idle")
        except Exception as exc:  # no model, no worker, no GPU: report it on every begin
            self._loaded_key = None
            self._error, self._code = str(exc), error_code(exc)
            self._set_state("error")

    def _restart_worker(self) -> bool:
        """A worker that died or hung mid-session: a fresh one for the same session (its audio is kept by the engine)."""
        engine = self.engine
        self._close_recognizer()
        self._set_state("loading")
        try:
            self._recognizer = self.make_recognizer()
        except Exception as exc:
            self._fail(exc)
            if self.engine is not None:  # still bound to the closed recognizer: the next begin must load a fresh one
                self._unload()
            return False
        engine.recognizer = self._recognizer
        self.emit({"event": "state", "state": "listening", "mode": engine.mode})
        return True

    def _controller(self) -> None:
        while not self._stop.is_set():
            try:
                cmd = self._commands.get(timeout=0.03)
            except queue.Empty:
                cmd = None
            try:
                if cmd:
                    self._handle(cmd)
                self._tick()
            except Exception as exc:  # a bug must not kill the controller: the service would hang with no reply
                self._fail(exc)
        self._handle({"cmd": "cancel"})
        self._close_recognizer()

    def _tick(self) -> None:
        engine = self.engine
        if engine and engine.active and self._state == "listening":
            if time.monotonic() - self._started > self.max_session:
                self._handle({"cmd": "end"})
                return
            failed = getattr(self._capture, "failed", None)
            if failed:
                self._fail(CaptureFailed(failed))
                return
            try:
                engine.step()
            except RecognizerError as exc:
                if self._restarted:
                    self._fail(exc)
                else:
                    self._restarted = True
                    self._restart_worker()
            except Exception as exc:
                self._fail(exc)
        elif engine and not engine.active and self._state == "idle" and self._recognizer is not None:
            if self._clock() - self._prefs_read >= 2.0:
                self._read_prefs()
            if self._idle_timeout > 0 and self._clock() - self._last_activity >= self._idle_timeout:
                self._unload()

    def _begin(self, cmd: dict) -> None:
        mode = cmd.get("mode")
        if not isinstance(mode, str) or mode not in MODES:  # JSON may carry any type here (a list is unhashable)
            self._reply(cmd, {"event": "error", "message": f"unknown mode {mode!r}", "code": "mode"})
            return
        engine = self.engine
        if engine is not None and engine.active:  # the running session is not disturbed
            self._reply(cmd, self.status())
            return
        self._read_prefs()
        self._restarted = False
        # the microphone first: what is said while the models load is buffered, not lost
        intake = _Intake()
        try:
            capture = self.make_capture(intake, mode)
            capture.start()
        except Exception as exc:
            self.emit({"event": "error", "message": str(exc), "code": error_code(exc)})
            return
        self._capture, self._intake = capture, intake
        self._owner = None if cmd.get("detached") else cmd.get("_client")
        if engine is None or self._wanted() != self._loaded_key:  # nothing loaded yet, or another model chosen
            self._load()
            engine = self.engine
        if engine is None:
            self._stop_capture()
            self.emit({"event": "error", "message": self._error or "models not loaded", "code": self._code or "error"})
            return
        engine.begin(mode)
        self._started = time.monotonic()
        intake.attach(engine.feed)

    def _stop_capture(self) -> None:
        capture, self._capture, self._intake, self._owner = self._capture, None, None, None
        if capture is not None:
            try:
                capture.stop()
            except Exception:
                pass

    def _handle(self, cmd: dict) -> None:
        name = cmd.get("cmd")
        engine = self.engine
        if name == "begin":
            self._begin(cmd)
        elif name == "_disconnect":  # a client went away: its session must not keep typing
            if cmd.get("_client") is not None and cmd["_client"] is self._owner:
                self._handle({"cmd": "cancel"})
        elif name in ("end", "cancel"):
            owner = self._owner
            self._stop_capture()
            if engine is None or not engine.active:
                return
            self._last_activity = self._clock()
            if name == "cancel":
                engine.cancel()
                return
            self._state = "finishing"
            self.emit({"event": "state", "state": "finishing"})
            self._owner = owner  # its disconnect still abandons the final pass (and a retry of it)
            try:
                self._finish(engine)
            finally:
                self._owner = None
        elif name != "status":
            self._reply(cmd, {"event": "error", "message": f"unknown command {name!r}", "code": "command"})

    def _finish(self, engine: Dictation) -> None:
        """The final pass. A recognizer failure keeps the session (audio and typed text) and retries once with a fresh
        worker over the whole audio; cancel, a client disconnect and shutdown abandon it at any point."""
        outcome, exc = self._supervise(lambda abandoned: engine.end(keep_on_failure=True), None)
        if outcome == "cancelled":
            return
        if exc is None:
            return
        if not (isinstance(exc, RecognizerError) and engine.active):
            self._fail(exc)
            return
        # the session is intact: reload the worker and run the final pass again (at most once)
        self.emit({"event": "retry", "what": "final", "message": str(exc), "code": error_code(exc)})
        deadline = self._clock_mono() + self.retry_timeout
        outcome, exc = self._supervise(lambda abandoned: self._retry_final(engine, abandoned), deadline)
        if outcome == "cancelled":
            return
        if exc is not None:
            self._fail(exc)
            self._unload()  # the recognizer is gone or untrusted: the next begin starts a fresh worker

    @staticmethod
    def _clock_mono() -> float:
        return time.monotonic()

    def _retry_final(self, engine: Dictation, abandoned: threading.Event) -> None:
        self._close_recognizer()
        recognizer = self.make_recognizer()
        with self._retry_lock:
            gone = abandoned.is_set()
            if not gone:
                self._recognizer = engine.recognizer = recognizer
        if gone:
            if hasattr(recognizer, "close"):
                recognizer.close()
            return
        engine.end(retry=True)

    def _supervise(self, work, deadline):
        """Run work() in a thread while the controller keeps reading commands. Returns ("done", None) or ("done", exc)
        when it finished, ("cancelled", None) when a cancel, the owner's disconnect or shutdown came first (the pass
        is aborted by killing the worker, the engine cancelled, the recognizer dropped), or ("done", WorkerFailed) when
        the deadline passed."""
        box = []
        abandoned = self._abandoned = threading.Event()  # per attempt: a late loader of an earlier one stays abandoned

        def run():
            try:
                work(abandoned)
                box.append(None)
            except BaseException as exc:
                box.append(exc)

        worker = threading.Thread(target=run, name="dictation-final", daemon=True)
        worker.start()
        deferred = []
        try:
            while worker.is_alive():
                worker.join(0.03)
                if self._stop.is_set():
                    return self._abandon(worker), None
                try:
                    cmd = self._commands.get_nowait()
                except queue.Empty:
                    cmd = None
                if cmd is not None:
                    name = cmd.get("cmd")
                    if name == "cancel" or (name == "_disconnect" and cmd.get("_client") is not None
                                            and cmd["_client"] is self._owner):
                        return self._abandon(worker), None
                    if name != "end":  # a repeated end is moot; anything else waits its turn
                        deferred.append(cmd)
                if deadline is not None and worker.is_alive() and self._clock_mono() > deadline:
                    with self._retry_lock:
                        abandoned.set()
                        self._abort_recognizer()
                    worker.join(5)
                    return "done", WorkerFailed(f"final pass retry did not finish within {self.retry_timeout:.0f} s")
        finally:
            for cmd in deferred:
                self._commands.put(cmd)
        return "done", box[0] if box else None

    def _abort_recognizer(self) -> None:
        recognizer = self._recognizer
        if recognizer is not None and hasattr(recognizer, "abort"):
            try:
                recognizer.abort()
            except Exception:
                pass

    def _abandon(self, worker: threading.Thread) -> str:
        with self._retry_lock:
            self._abandoned.set()
            self._abort_recognizer()
        if self.engine is not None:
            self.engine.cancel()
        worker.join(5)  # a worker still loading closes its recognizer itself (see _retry_final)
        self._unload()
        return "cancelled"

    def _reply(self, cmd: dict, event: dict) -> None:
        """A bad command is the sender's problem: answer only that client (a typo in a script must not fail the
        session another client, the shell, is running)."""
        writer = cmd.get("_client")
        loop = self._loop
        if writer is None or loop is None or loop.is_closed():
            self.emit(event)
            return
        line = (json.dumps(event, ensure_ascii=False) + "\n").encode()
        loop.call_soon_threadsafe(lambda: writer in self._clients and writer.write(line))

    def _fail(self, exc: Exception) -> None:
        self.emit({"event": "error", "message": str(exc), "code": error_code(exc)})
        self._stop_capture()
        self._last_activity = self._clock()
        if self.engine is not None and self.engine.active:
            self.engine.cancel()
        elif self._state in ("listening", "finishing", "loading"):  # end() failed: the session is gone, say so after the error
            self.emit({"event": "state", "state": "idle"})
        if isinstance(exc, RecognizerError):
            self._unload()  # a dead worker: the next begin starts a fresh one (its audio is buffered while it loads)

    # --- socket side (asyncio) ---

    async def _client(self, reader, writer) -> None:
        self._clients.add(writer)
        writer.write((json.dumps(self.status()) + "\n").encode())
        try:
            while line := await reader.readline():
                cmd = parse_command(line.decode("utf-8", errors="replace"))
                if cmd is None:
                    continue
                if cmd.get("cmd") == "status":
                    writer.write((json.dumps(self.status()) + "\n").encode())
                else:
                    cmd["_client"] = writer
                    self._commands.put(cmd)
        except (ConnectionError, asyncio.IncompleteReadError, ValueError):  # ValueError: line over the limit
            pass
        finally:
            self._clients.discard(writer)
            writer.close()
            self._commands.put({"cmd": "_disconnect", "_client": writer})

    def _claim_socket(self) -> None:
        if os.path.exists(self.socket_path):
            probe = socket.socket(socket.AF_UNIX)
            try:
                probe.connect(self.socket_path)
            except OSError:
                os.unlink(self.socket_path)  # stale
            else:
                raise RuntimeError(f"another dictation service is listening on {self.socket_path}")
            finally:
                probe.close()

    async def serve(self, ready: threading.Event | None = None) -> None:
        self._loop = asyncio.get_running_loop()
        self._claim_socket()
        old = os.umask(0o177)
        try:
            server = await asyncio.start_unix_server(self._client, path=self.socket_path)
        finally:
            os.umask(old)
        controller = threading.Thread(target=self._controller, name="dictation-controller", daemon=True)
        controller.start()
        stop = self._stop_async = asyncio.Event()
        for sig in (signal.SIGTERM, signal.SIGINT):
            try:
                self._loop.add_signal_handler(sig, stop.set)
            except (RuntimeError, ValueError):  # not the main thread (tests)
                pass
        if self._stop.is_set():  # shutdown() came before serve() was ready
            stop.set()
        if ready:
            ready.set()
        try:
            await stop.wait()
        finally:
            self._stop.set()
            server.close()
            for writer in list(self._clients):  # wait_closed() waits for every open connection
                writer.close()
            await server.wait_closed()
        await asyncio.to_thread(controller.join, 3)
        if controller.is_alive():  # still loading or in a pass: its children must not outlive the service
            from . import audio, whisper
            whisper.kill_all()
            audio.kill_all()
            await asyncio.to_thread(controller.join, 7)
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass

    def shutdown(self) -> None:
        """Stop serve() from another thread."""
        self._stop.set()
        if self._loop is not None and self._stop_async is not None and not self._loop.is_closed():
            try:
                self._loop.call_soon_threadsafe(self._stop_async.set)
            except RuntimeError:  # the loop closed meanwhile: serve() is already done
                pass
