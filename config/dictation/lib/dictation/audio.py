"""Microphone capture from the PipeWire default source with pw-record (raw float32, 16 kHz mono on stdout).

pw-record runs only during a session, so the microphone is open only while the key is held.
"""
from __future__ import annotations

import os
import subprocess
import threading
import time
import weakref

PW_RECORD = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "f32", "--raw", "--latency", "32ms"]


class CaptureError(RuntimeError):
    code = "mic"


_RECORDERS: "weakref.WeakSet" = weakref.WeakSet()


def kill_all() -> None:
    """Kill every recorder still running (service shutdown)."""
    for proc in list(_RECORDERS):
        if proc.poll() is None:
            proc.kill()  # our own child, by its Popen handle


def pipewire_sources() -> set | None:
    """Names of the PipeWire capture sources (monitors included), or None when they cannot be listed."""
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return {cols[1] for line in out.stdout.splitlines() if len(cols := line.split("\t")) > 1}


class PwRecord:
    """`failed` turns into a message when pw-record ends on its own during a session (no source, the device went
    away) or delivers no audio for `stall_s` seconds; the service then reports a `mic` error. A named `target` that
    PipeWire does not list is refused at start (pw-record would otherwise quietly record the default source)."""

    def __init__(self, on_pcm, *, target: str | None = None, cmd: list | None = None, stall_s: float = 3.0,
                 sources=pipewire_sources, clock=time.monotonic):
        self.on_pcm = on_pcm
        self.target = target
        self._sources, self._clock, self.stall_s = sources, clock, stall_s
        self._last = 0.0
        self.argv = list(cmd or PW_RECORD) + (["--target", target] if target else []) + ["-"]
        self._proc = None
        self._thread = None
        self._failed = None

    @property
    def failed(self):
        if self._failed:
            return self._failed
        if self._proc is not None and self.stall_s and self._clock() - self._last > self.stall_s:
            return f"microphone delivered no audio for {self.stall_s:g} s"
        return None

    def start(self) -> None:
        if self.target and not self.target.isdigit():
            known = self._sources()
            if known is not None and self.target not in known:
                raise CaptureError(f"microphone {self.target!r} not found (unplugged? choose another in Settings > Voice)")
        try:
            self._proc = subprocess.Popen(self.argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as exc:
            raise CaptureError(f"microphone capture could not start: {exc}") from exc
        _RECORDERS.add(self._proc)
        self._last = self._clock()
        self._thread = threading.Thread(target=self._pump, args=(self._proc,), daemon=True)
        self._thread.start()

    def _pump(self, proc) -> None:
        fd = proc.stdout.fileno()
        while True:
            chunk = os.read(fd, 4096)
            if not chunk:
                break
            self._last = self._clock()
            try:
                self.on_pcm(chunk)
            except Exception as exc:  # a feed failure must not silently end the reader: report it at once
                if self._proc is proc:
                    self._failed = f"microphone audio could not be processed: {exc}"
                return
        if self._proc is proc:  # not stop(): the recorder ended by itself
            self._failed = f"microphone capture stopped (pw-record exit code {proc.wait()})"

    def stop(self) -> None:
        """Stop recording and wait until every captured byte was delivered."""
        proc, self._proc = self._proc, None
        if proc is None:
            return
        if proc.poll() is None:
            proc.terminate()  # our own child, by its Popen handle
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        self._thread.join(timeout=2)
        proc.stdout.close()

    @property
    def running(self) -> bool:
        return self._proc is not None and self._proc.poll() is None


class FileCapture:
    """Stand-in for the microphone: plays float32 16 kHz mono bytes at speaking speed from the start of the session,
    then silence until stopped (`dictation serve --audio-file`, for driving the service and the pill without a mic)."""

    def __init__(self, on_pcm, pcm: bytes, *, chunk_s: float = 0.032):
        self.on_pcm = on_pcm
        self.pcm = pcm
        self.chunk = int(chunk_s * 16000) * 4
        self._stop = threading.Event()
        self._thread = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._pump, daemon=True)
        self._thread.start()

    def _pump(self) -> None:
        import time

        t0 = time.monotonic()
        silence = bytes(self.chunk)
        i = 0
        while not self._stop.is_set():
            self.on_pcm(self.pcm[i : i + self.chunk] if i < len(self.pcm) else silence)
            i += self.chunk
            delay = t0 + i / 4 / 16000 - time.monotonic()
            if delay > 0:
                self._stop.wait(delay)

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
