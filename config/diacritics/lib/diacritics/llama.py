"""llama-server process and the chat completions request.

Paths (environment): DIACRITICS_BIN_DIR (default ${XDG_DATA_HOME:-~/.local/share}/diacritics/bin, holds llama-server
and its libraries, put on LD_LIBRARY_PATH), DIACRITICS_MODEL_DIR (default .../diacritics/models), DIACRITICS_PROMPT
(default .../diacritics/prompt.txt, else the copy next to the module in the repo).
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request

FLAGS = ["-ngl", "99", "-c", "4096", "--no-webui", "--jinja", "--reasoning", "off", "-fa", "on"]
START_TIMEOUT = 180.0  # a cold 12B load from disk
REQUEST_TIMEOUT = 90.0


class ServerError(RuntimeError):
    """code: server | timeout | empty"""

    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code


def data_dir() -> str:
    return os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "diacritics")


def bin_dir() -> str:
    return os.environ.get("DIACRITICS_BIN_DIR") or os.path.join(data_dir(), "bin")


def model_dir() -> str:
    return os.environ.get("DIACRITICS_MODEL_DIR") or os.path.join(data_dir(), "models")


def prompt_file() -> str:
    path = os.environ.get("DIACRITICS_PROMPT") or os.path.join(data_dir(), "prompt.txt")
    if os.path.exists(path) or os.environ.get("DIACRITICS_PROMPT"):
        return path
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))), "prompt.txt")


def prompt_file_html() -> str:
    """The system prompt for HTML fragments: DIACRITICS_PROMPT_HTML, else prompt-html.txt in the data dir, else the repo copy."""
    path = os.environ.get("DIACRITICS_PROMPT_HTML") or os.path.join(data_dir(), "prompt-html.txt")
    if os.path.exists(path) or os.environ.get("DIACRITICS_PROMPT_HTML"):
        return path
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))), "prompt-html.txt")


def read_prompt(fmt: str = "text") -> str:
    try:
        with open(prompt_file_html() if fmt == "html" else prompt_file(), encoding="utf-8") as f:
            return f.read().rstrip("\n")
    except OSError as exc:
        raise ServerError("server", f"prompt: {exc}")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class LlamaServer:
    """One llama-server child: start() blocks until /health is ok, stop() ends it."""

    def __init__(self, model: str):
        self.model = model
        self.proc: subprocess.Popen | None = None
        self.port = 0

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def start(self, log_path: str | None = None) -> None:
        exe = os.path.join(bin_dir(), "llama-server")
        model = os.path.join(model_dir(), self.model)
        if not os.path.exists(exe):
            raise ServerError("server", f"llama-server not found: {exe}")
        if not os.path.exists(model):
            raise ServerError("server", f"model not found: {model}")
        env = dict(os.environ)
        env["LD_LIBRARY_PATH"] = bin_dir() + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
        self.port = free_port()
        log = open(log_path, "wb") if log_path else subprocess.DEVNULL
        try:
            self.proc = subprocess.Popen([exe, "-m", model, "--host", "127.0.0.1", "--port", str(self.port), *FLAGS],
                                         env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        finally:
            if log_path:
                log.close()
        deadline = time.monotonic() + START_TIMEOUT
        while True:
            if self.proc.poll() is not None:
                raise ServerError("server", f"llama-server exited with {self.proc.returncode} while loading")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=2) as r:
                    if r.status == 200:
                        return
            except (OSError, urllib.error.URLError):
                pass
            if time.monotonic() > deadline:
                self.stop()
                raise ServerError("timeout", "llama-server did not become healthy")
            time.sleep(0.2)

    def stop(self) -> None:
        p, self.proc = self.proc, None
        if p is None:
            return
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

    def complete(self, system: str, text: str, timeout: float = REQUEST_TIMEOUT) -> str:
        """The model's reply for `text`, verbatim."""
        body = json.dumps({
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": text}],
            "temperature": 0, "top_k": 1, "max_tokens": min(3000, max(512, 2 * len(text.encode()))),
        }).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}/v1/chat/completions", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                reply = json.load(r)
            return reply["choices"][0]["message"]["content"] or ""
        except (socket.timeout, TimeoutError):
            raise ServerError("timeout", "request timed out")
        except urllib.error.URLError as exc:
            if isinstance(exc.reason, (socket.timeout, TimeoutError)):
                raise ServerError("timeout", "request timed out")
            raise ServerError("server", str(exc))
        except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
            raise ServerError("server", f"bad reply: {exc}")
