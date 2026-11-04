# diacritics: local Czech diacritics

Fixes missing Czech diacritics with a local Gemma model (llama.cpp `llama-server`, GPU via Vulkan). Two parts live here:
the service (a unix socket around an on-demand `llama-server`) and the key flow (`diacritics run`: one key press fixes the
selection or the whole input field of the focused window). The pill (`DiacPill.qml`) and the Settings page (Settings >
Diacritics) are Quickshell code and talk to the service over its socket and the prefs file.

## Layout

| Path | What |
|---|---|
| `bin/diacritics` | CLI: `serve`, `fix` (stdin to stdout), `run` (key flow, exits with the flow's status), `status`, `listen` |
| `lib/diacritics/service.py` | unix socket service: ops `fix`, `state`, `subscribe`, `status`; state machine; idle reaper; whitespace handling (`restore_whitespace`, `keep_spacing`) |
| `lib/diacritics/llama.py` | `llama-server` child (free port, health wait, stop), the chat completions request, input size limit, `finish_reason` check |
| `lib/diacritics/htmlmode.py` | HTML fragments: strip the clipboard wrapper, detect real markup, same-tags check, plain text of a fragment |
| `lib/diacritics/client.py` | socket client (timeouts); starts `diacritics.service` when nothing listens |
| `lib/diacritics/paths.py` | runtime/state locations and the environment names of the Python side |
| `lib/diacritics/prefs.py` | reads the Settings file (model, idle timeout, ignored window classes and their default list) |
| `lib/diacritics/flow.py` | the key flow (`diacritics run`): focused window, copy, fix, paste, restore the clipboard |
| `lib/diacritics/hypr.py` | Hyprland: focused window, `send_shortcut` aimed at a window address, the wtype fallback |
| `lib/diacritics/clipboard.py` | wl-clipboard: save, set, restore (all types), HTML + plain in one selection |
| `lib/diacritics/wlsel.py` | helper process: several MIME types in one selection (data-control protocol, stdlib only) |
| `prompt.txt` | system prompt, a plain file; `install.sh` links it to `~/.local/share/diacritics/prompt.txt` |
| `prompt-html.txt` | system prompt for `"format":"html"` requests (an HTML fragment: only the text content is fixed); linked next to `prompt.txt` |
| `tests/` | unit tests without a model (`python3 -m unittest discover -s config/diacritics/tests`) |
| `../systemd/user/diacritics.service` | user unit (`diacritics serve`), no `[Install]`: started on demand |

The key itself is bound by `../hypr/hyprland/diacritics.lua` (it runs `diacritics run`); Settings writes the key and the
prefs (`../quickshell/DiacriticsPrefs.qml`).

## Service

- Socket `$XDG_RUNTIME_DIR/diacritics.sock`, one JSON line per request (`fix`, `state`, `status`), `subscribe` streams
  `{"event":"state","state":"idle|loading|working|done|failed|unsupported","text":...,"fixed":...}` (text only while working, fixed only on done).
  After done, failed or unsupported the state returns to idle after 1.2 s.
- `llama-server` starts on the first fix (state loading), is restarted when it died or the model preference changed,
  and is stopped after `idle_timeout_s` without a fix (0 or negative = never). Flags: `-ngl 99 -c 8192 --no-webui
  --jinja --reasoning off -fa on`; request: temperature 0, top_k 1.
- Fixes run one at a time; a second waits up to 30 s, then gets `busy`. Errors: `server` (no binary, model, crash,
  bad reply), `timeout` (startup 180 s, request 90 s), `empty`, `busy`, `toolong`, `truncated`.
- `toolong`: the input (with the prompt and a reply about as long) would not fit the context; estimated pessimistically
  at 2 bytes per token, roughly 5800 bytes of input. Nothing is sent to the model and the field stays as it is.
- `truncated`: the reply did not end by itself (`finish_reason` other than `stop`); it is never returned.
- The text goes to the model without its leading/trailing whitespace; that whitespace is put back unchanged, the rest
  is the model's reply with at most one trailing newline dropped. `keep_spacing`: when the reply has the same words as
  the input, the input's whitespace between them (the model collapses double spaces and blank lines) is put back.
- Prefs `~/.local/state/quickshell/diacritics.json` (written by Settings, read at every request): `model` (file name in
  the models dir, default `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf`), `idle_timeout_s` (default 600), `ignored_classes`.

## Key flow (`diacritics run`)

1. The focused window (`hyprctl`). A class in `ignored_classes` (terminals, matched case-insensitively) shows "unsupported"
   in the pill; no key is sent and the clipboard is not touched. Default list: `DEFAULT_IGNORED_CLASSES` in `prefs.py`,
   equal to the Settings page default (a unit test compares them); a missing file or list uses it.
2. The clipboard is saved (all types up to 32 MiB), a sentinel goes on it, Ctrl+C goes to that window; a clipboard that
   still holds the sentinel means no selection, so Ctrl+A, Ctrl+C. Keys are `send_shortcut` aimed at the window address
   with layout-independent keycodes.
3. A copy that also offers `text/html` with real markup goes to the service as an HTML fragment and comes back as
   `text/html` plus `text/plain` in one selection; anything else is plain text.
4. The service fixes the text. Any failure (error, timeout, `toolong`, `truncated`, focus changed, unchanged text)
   leaves the field alone. Otherwise the result goes on the clipboard and Ctrl+V to the same window.
5. The saved clipboard comes back in every outcome. A clipboard that could not be read at the start is left as it is
   (never cleared); skipped types are logged by type and size only.

- Exit status: 0 done or nothing to do, 1 failed, 2 unsupported window, 3 another run is in progress (lock
  `$XDG_RUNTIME_DIR/diacritics-flow.lock`). Log: `${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics-flow.log`.
- The flow waits for the service longer than the service can take at worst (queue + model start + request), so a late
  result cannot arrive after the flow gave up.
- wtype fallback: when `send_shortcut` demonstrably fails (hyprctl cannot run, a non-zero exit or an explicit error
  message) and the window is still focused, the key goes out through `wtype` into the focused window. This is the one
  exception to "no synthetic keystrokes"; it is logged. A timeout or any other answer counts as sent and is never retried.
  `DIACRITICS_NO_FALLBACK=1` switches it off.
- The helper for several clipboard types has a time limit and is killed when it does not answer; the clipboard then
  falls back to one type.
- Code editors copy the current line when nothing is selected, so the select-all path is not reached there.

## Setup (per machine; `install.sh` links the CLI, the unit and the prompts, nothing enables the unit)

1. `llama-server` built with Vulkan into `~/.local/share/diacritics/bin` (with its `libggml*`/`libllama*` libraries; the
   service sets `LD_LIBRARY_PATH` to that directory).
2. GGUF models in `~/.local/share/diacritics/models/` (Gemma 4 E2B, E4B, 12B), never in the repo.
3. Dependencies: `wl-clipboard` (`wl-copy`, `wl-paste`) and `wtype` (the fallback only) for the key flow.
4. Environment overrides (tests): `DIACRITICS_SOCK`, `DIACRITICS_PREFS_FILE` (the only names of the Python side, see
   `paths.py`), `DIACRITICS_BIN_DIR`, `DIACRITICS_MODEL_DIR`, `DIACRITICS_PROMPT`, `DIACRITICS_PROMPT_HTML`. With
   `DIACRITICS_SOCK` set the CLI never starts the user unit. The Quickshell side reads `QS_DIACRITICS_SOCKET` and
   `QS_DIACRITICS_FILE`; a test of both sides sets both.

Try it: `echo 'Ahoj, prace je hotova' | diacritics fix`; watch states with `diacritics listen`; the llama-server log of
the last start is `$XDG_RUNTIME_DIR/diacritics-llama.log`.
