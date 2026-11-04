# diacritics: local Czech diacritics service

Fixes missing Czech diacritics in a text with a local Gemma model (llama.cpp `llama-server`, GPU via Vulkan). The key
flow (`diacritics run`), the pill and the Settings page live elsewhere and talk to this service over its socket.

## Layout

| Path | What |
|---|---|
| `bin/diacritics` | CLI: `serve`, `fix` (stdin to stdout), `run` (key flow, `lib/diacritics/flow.py`), `status`, `listen` |
| `lib/diacritics/service.py` | unix socket service: ops `fix`, `state`, `subscribe`, `status`; state machine; idle reaper |
| `lib/diacritics/llama.py` | `llama-server` child (free port, health wait, stop) and the chat completions request |
| `lib/diacritics/client.py` | socket client; starts `diacritics.service` when nothing listens |
| `lib/diacritics/prefs.py` | reads the Settings file |
| `prompt.txt` | system prompt, a plain file; `install.sh` links it to `~/.local/share/diacritics/prompt.txt` |
| `tests/` | unit tests without a model (`python3 -m unittest discover -s config/diacritics/tests`) |
| `../systemd/user/diacritics.service` | user unit (`diacritics serve`), no `[Install]`: started on demand |

## Behaviour

- Socket `$XDG_RUNTIME_DIR/diacritics.sock`, one JSON line per request (`fix`, `state`, `status`), `subscribe` streams
  `{"event":"state","state":"idle|loading|working|done|failed|unsupported","text":...}` (text only while working).
  After done, failed or unsupported the state returns to idle after 1.2 s.
- `llama-server` starts on the first fix (state loading), is restarted when it died or the model preference changed,
  and is stopped after `idle_timeout_s` without a fix (0 or negative = never). Flags: `-ngl 99 -c 4096 --no-webui
  --jinja --reasoning off -fa on`; request: temperature 0, top_k 1, max_tokens 2x input bytes (512..3000).
- Fixes run one at a time; a second waits up to 30 s, then gets `busy`. Errors: `server` (no binary, model, crash,
  bad reply), `timeout` (startup 180 s, request 90 s), `empty`, `busy`.
- The text goes to the model without its leading/trailing whitespace; that whitespace is put back unchanged, the rest
  is the model's reply with at most one trailing newline dropped.
- Prefs `~/.local/state/quickshell/diacritics.json` (written by Settings, read at every request): `model` (file name in
  the models dir, default `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf`), `idle_timeout_s` (default 600).

## Setup (per machine; `install.sh` links the CLI, the unit and the prompt, nothing enables the unit)

1. `llama-server` built with Vulkan into `~/.local/share/diacritics/bin` (with its `libggml*`/`libllama*` libraries; the
   service sets `LD_LIBRARY_PATH` to that directory).
2. GGUF models in `~/.local/share/diacritics/models/` (Gemma 4 E2B, E4B, 12B), never in the repo.
3. Environment overrides (tests): `DIACRITICS_SOCK`, `DIACRITICS_PREFS_FILE`, `DIACRITICS_BIN_DIR`,
   `DIACRITICS_MODEL_DIR`, `DIACRITICS_PROMPT`. With `DIACRITICS_SOCK` set the CLI never starts the user unit.

Try it: `echo 'Ahoj, prace je hotova' | diacritics fix`; watch states with `diacritics listen`; the llama-server log of
the last start is `$XDG_RUNTIME_DIR/diacritics-llama.log`.
