"""Recognizer backed by the dictation-whisper worker (worker/dictation-whisper.c): both models stay loaded in one
child process; requests go over its stdin, replies come back as JSON lines."""
from __future__ import annotations

import json
import os
import re
import select
import subprocess
import threading
import weakref

from .engine import FINAL, LIVE, Recognition, RecognizerError, Segment

MODEL_NAMES = ("large-v3-turbo", "large-v3", "large-v3-q5_0", "medium", "small")
DEFAULT_LIVE = "large-v3-turbo"
DEFAULT_FINAL = "large-v3"


class ModelMissing(RuntimeError):
    code = "no-model"


class WorkerFailed(RecognizerError):
    code = "worker"


class GpuFailed(WorkerFailed):
    """The GPU (Vulkan) could not be initialised; reported, never replaced by a silent CPU run (prefs gpu=false opts in)."""
    code = "gpu-failed"


_WORKERS: "weakref.WeakSet" = weakref.WeakSet()


def kill_all() -> None:
    """Kill every worker still running (service shutdown that could not wait for a load)."""
    for proc in list(_WORKERS):
        if proc.poll() is None:
            proc.kill()  # our own child, by its Popen handle


def data_dir() -> str:
    return os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "dictation")


def model_dir() -> str:
    return os.environ.get("DICTATION_MODEL_DIR") or os.path.join(data_dir(), "models")


def model_path(name: str, directory: str | None = None) -> str:
    return os.path.join(directory or model_dir(), f"ggml-{name}.bin")


def models_file() -> str:
    """The shell's model choice (Settings > Voice, SttModels.qml writes it): {"live": NAME, "final": NAME}."""
    return os.environ.get("DICTATION_MODELS_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "stt-models.json")


_NAME = re.compile(r"[A-Za-z0-9._-]{1,64}")  # fullmatch: as SttModels.qml (no trailing newline accepted)


def chosen_models(path: str | None = None, *, live: str | None = None, final: str | None = None) -> dict:
    """{"live": name, "final": name}: explicit arguments first, then the shell's choice, then the defaults.

    Reads the file exactly as SttModels.qml does (a missing file, unreadable JSON, a missing key or a malformed name
    leave that role at its default), so the service and the settings page always agree on which model is meant.
    The file is never written here, and a chosen model that is not installed is never swapped for another one."""
    names = {"live": DEFAULT_LIVE, "final": DEFAULT_FINAL}
    try:
        with open(path or models_file(), encoding="utf-8") as f:
            saved = json.load(f)
    except (OSError, ValueError):
        saved = None
    if isinstance(saved, dict):
        for role in names:
            if isinstance(saved.get(role), str) and _NAME.fullmatch(saved[role]):
                names[role] = saved[role]
    for role, name in (("live", live), ("final", final)):
        if name:
            names[role] = name
    return names


def model_paths(names: dict, directory: str | None = None) -> dict:
    """{"live": path, "final": path}; ModelMissing (code no-model) names the first chosen model that is not there."""
    paths = {}
    for role, name in names.items():
        if not _NAME.fullmatch(name):
            raise ModelMissing(f"bad model name for {role}: {name!r}")
        paths[role] = model_path(name, directory)
        if not os.path.isfile(paths[role]):
            raise ModelMissing(f"speech model {name} ({role}) is not installed: expected {paths[role]}")
    return paths


def worker_path() -> str:
    return os.environ.get("DICTATION_WORKER") or os.path.join(data_dir(), "bin", "dictation-whisper")


class WhisperRecognizer:
    """transcribe(audio, slot=..., language=..., translate=...) for slots "live" (greedy) and "final" (beam search)."""

    def __init__(self, models: dict, *, worker: str | None = None, gpu: bool = True, gpu_device: int = 0, threads: int = 4,
                 final_beam: int = 5, verbose: bool = False, timeout: float = 60.0, load_timeout: float = 120.0):
        # timeout: seconds per request, plus one per second of audio
        for slot, path in models.items():
            if not os.path.isfile(path):
                raise ModelMissing(f"model missing for {slot}: expected {path}")
        worker = worker or worker_path()
        if not os.access(worker, os.X_OK):
            raise WorkerFailed(f"worker missing: expected {worker} (build it with config/dictation/worker/build.sh)")
        argv = [worker]
        for slot, path in models.items():
            argv += ["--model", f"{slot}={path}"]
        argv += ["--threads", str(threads)]
        if not gpu:
            argv.append("--no-gpu")
        elif gpu_device:
            argv += ["--gpu-device", str(int(gpu_device))]  # 0 is the worker's default (an old worker never sees the flag)
        if verbose:
            argv.append("--verbose")
        self.final_beam = final_beam
        self._lock = threading.Lock()
        self._seq = 0
        self._proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=None if verbose else subprocess.DEVNULL)
        _WORKERS.add(self._proc)
        self.timeout = timeout
        self._buf = b""
        try:
            ready = self._read(load_timeout)
        except Exception:
            self.close()
            raise
        if not ready.get("ready"):
            self.close()
            failure = GpuFailed if ready.get("code") == "gpu" else WorkerFailed
            message = ready.get("error", "worker did not start")
            if gpu_device and gpu and message == "unknown argument":  # a worker built before --gpu-device
                failure, message = GpuFailed, "this worker cannot choose a GPU: rebuild it with config/dictation/worker/build.sh"
            raise failure(message)
        self.load_ms = ready.get("load_ms")

    @property
    def pid(self) -> int:
        return self._proc.pid

    def transcribe(self, audio: bytes, *, slot: str, language: str, translate: bool, prompt: str = "") -> Recognition:
        if slot not in (LIVE, FINAL):
            raise ValueError(slot)
        beam = self.final_beam if slot == FINAL else 0
        with self._lock:
            self._seq += 1
            rid = str(self._seq)
            hint = prompt.encode()[:1024].decode(errors="ignore").encode()  # the worker's limit, whole characters
            fields = [rid, slot, language, int(translate), beam, len(audio) // 4] + ([len(hint)] if hint else [])
            header = (" ".join(map(str, fields)) + "\n").encode()
            try:
                self._proc.stdin.write(header)
                self._proc.stdin.write(audio[: len(audio) // 4 * 4])
                self._proc.stdin.write(hint)
                self._proc.stdin.flush()
            except (OSError, ValueError) as exc:  # ValueError: stdin already closed (close() ran)
                raise WorkerFailed(f"worker exited: {exc}") from exc
            # long sessions (or a CPU fallback) take longer: allow the audio's length on top of the base timeout
            reply = self._read(self.timeout + len(audio) / 4 / 16000)
        if "error" in reply and reply.get("id") == rid:
            raise ValueError(f"worker refused the request: {reply['error']}")
        if reply.get("id") != rid:
            raise WorkerFailed(f"worker reply out of step: {reply}")
        segments = [Segment(s["t0"] / 1000, s["t1"] / 1000, s["text"]) for s in reply["segments"]]
        return Recognition(segments, float(reply["ms"]))

    def detect(self, audio: bytes, *, slot: str) -> dict:
        """{language code: probability} for the audio (the worker's whisper_lang_auto_detect on the slot's model)."""
        if slot not in (LIVE, FINAL):
            raise ValueError(slot)
        with self._lock:
            self._seq += 1
            rid = str(self._seq)
            header = (" ".join(map(str, [rid, slot, "detect", 0, 0, len(audio) // 4])) + "\n").encode()
            try:
                self._proc.stdin.write(header)
                self._proc.stdin.write(audio[: len(audio) // 4 * 4])
                self._proc.stdin.flush()
            except (OSError, ValueError) as exc:
                raise WorkerFailed(f"worker exited: {exc}") from exc
            reply = self._read(self.timeout + len(audio) / 4 / 16000)
        if "error" in reply and reply.get("id") == rid:
            raise ValueError(f"worker refused the request: {reply['error']}")
        if reply.get("id") != rid:
            raise WorkerFailed(f"worker reply out of step: {reply}")
        probs = reply.get("probs")
        return {str(k): float(v) for k, v in probs.items()} if isinstance(probs, dict) else {}

    def _read(self, timeout: float) -> dict:
        """One reply line; a worker that hangs (a stuck GPU decode) is killed after `timeout` seconds."""
        fd = self._proc.stdout.fileno()
        while b"\n" not in self._buf:
            ready, _, _ = select.select([fd], [], [], timeout)
            if not ready:
                self._proc.kill()  # our own child, by its Popen handle
                raise WorkerFailed(f"worker did not answer within {timeout:.0f} s")
            chunk = os.read(fd, 65536)
            if not chunk:
                raise WorkerFailed(f"worker exited (code {self._proc.poll()})")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        try:
            return json.loads(line.decode("utf-8", errors="replace"))
        except ValueError as exc:
            raise WorkerFailed(f"worker sent garbage: {line[:200]!r}") from exc

    def abort(self) -> None:
        """Kill the worker from another thread; a request in flight then fails with WorkerFailed."""
        if self._proc.poll() is None:
            self._proc.kill()  # our own child, by its Popen handle

    def close(self) -> None:
        proc = self._proc
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()  # our own child, by its Popen handle (exact PID)
            proc.wait()
        proc.stdout.close()
