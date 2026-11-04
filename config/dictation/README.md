# dictation: local push-to-talk dictation service

Hold a key, speak, release: the text is typed into the focused field or terminal. Czech and English, plus Czech
spoken and typed as English. Everything runs locally on whisper.cpp (Vulkan backend). This directory is the
service core; the shell drives it: the three push-to-talk keys (Settings > Voice) and the pill are in
`config/quickshell` (`DictationController.qml` wires keys -> `DictationClient.qml` (this socket) -> `DictationPill.qml`).

## Layout

| Path | What |
|---|---|
| `bin/dictation` | CLI: `serve`, `begin MODE`, `end`, `cancel`, `status`, `listen`, `replay FILE.wav --mode MODE` |
| `lib/dictation/engine.py` | the deep module: one session from audio frames to edit operations (stability, tail corrections, final pass, translate, focus abort); cleanup seam `NoCleanup` |
| `lib/dictation/cleanup.py`, `lib/dictation/default-words.json` | cleanup stage: filler filter, replacement list, vocabulary hints; the built-in filler lists |
| `lib/dictation/service.py` | unix socket control interface, controller thread |
| `lib/dictation/whisper.py` | recognizer client for the worker; model and worker paths |
| `lib/dictation/audio.py` | `pw-record` capture (PipeWire default source), `FileCapture` stand-in |
| `lib/dictation/level.py` | noise-floor-aware level (the `level` events) and the voiced flag of the end-of-speech detector |
| `lib/dictation/hallucinations.json` | stock phrases whisper invents on noise, dropped when little voiced audio |
| `lib/dictation/inject.py` | `wtype` adapter, Hyprland focused-window probe |
| `worker/dictation-whisper.c`, `worker/build.sh` | small C program that keeps both models loaded and answers requests on stdin/stdout |
| `tests/` | unit tests (the seam: audio in, edit operations out, recorder injector) and an opt-in real-model test |
| `../systemd/user/dictation.service` | user unit (`dictation serve`) |

## Setup (per machine; the links are made by `install.sh`, the worker and models are not)

1. whisper.cpp with the Vulkan backend, installed or built from source (`cmake -B build -DGGML_VULKAN=1`).
2. Build the worker: `config/dictation/worker/build.sh` (system install), or
   `WHISPER_PREFIX=<src> WHISPER_BUILD=<src>/build config/dictation/worker/build.sh` for a source build. Output:
   `${XDG_DATA_HOME:-~/.local/share}/dictation/bin/dictation-whisper` (rpath to the whisper libraries).
3. Models in `${XDG_DATA_HOME:-~/.local/share}/dictation/models/ggml-<name>.bin` (Settings > Voice downloads them),
   never in the repo. Which ones: `serve --live/--final`, else the shell's choice in
   `${XDG_STATE_HOME:-~/.local/state}/quickshell/stt-models.json` (`{"live": NAME, "final": NAME}`, written by
   Settings > Voice; `DICTATION_MODELS_FILE` overrides), else `large-v3-turbo` (live) / `large-v3` (final and
   translation). A missing key or malformed name is that role's default, exactly as the settings page reads it. The
   file is re-read at every `begin`: a changed choice reloads the models first (about a second), and a chosen model
   that is not installed is an error with code `no-model` naming the file; another model is never used instead.
4. Links: `./install.sh --only links` (idempotent) links `bin/dictation` to `~/.local/bin/dictation` and
   `config/systemd/user/dictation.service` to `~/.config/systemd/user/`. Nothing enables the unit (no `[Install]`): the
   shell starts it on the first key press (`systemctl --user start dictation.service`), by then Hyprland has imported
   `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` into the user manager (`hypr/hyprland/autostart.lua`). The unit
   sets `PATH` to `~/.local/bin:/usr/local/bin:/usr/bin` (pw-record, wtype, python3); `serve` warns in the journal when
   `WAYLAND_DISPLAY` is missing. Logs: `journalctl --user -u dictation`.
5. Voice preferences, written by Settings > Voice to `${XDG_STATE_HOME:-~/.local/state}/quickshell/dictation-prefs.json`
   (`DICTATION_PREFS_FILE` overrides), re-read at every `begin`: `{"version":1,"mic":"","gpu":true,"idle_timeout_s":600,
   "prompt_hints":false,"gpu_device":0}` (plus `pause_silence_s` and `trailing_space`, no UI: see Behaviour; `pill_bottom` is the shell's). `mic` = PipeWire source name (`pactl list short sources`; "" = system default; a name that
   is not listed is a `mic` error), `gpu` false = the worker runs on the CPU only (`--no-gpu`; slow, an explicit
   choice), `idle_timeout_s` = unload after that long without a session (0 or negative = never). A missing or
   malformed file or key means the default; a changed `gpu` or `gpu_device` reloads the models at the next `begin`.
   `gpu_device` = which GPU the worker uses: the index printed by `dictation-whisper --list-devices` (one JSON line per
   GPU: `index`, `name`, `type` discrete|integrated, `free_mb`, `total_mb`; Settings > Voice reads it), default 0, passed
   as `--gpu-device N` (not at all for 0). An index that does not exist is a `gpu-failed` error, never another device
   or the CPU. A non-discrete GPU is for testing (several seconds per pass). The worker must be rebuilt
   (`worker/build.sh`) to know `--gpu-device` / `--list-devices`; an old worker with `gpu_device` > 0 is `gpu-failed`
   with a hint to rebuild, and the Settings page then shows "worker not built or too old".

Environment overrides: `DICTATION_MODEL_DIR`, `DICTATION_MODELS_FILE`, `DICTATION_PREFS_FILE`, `DICTATION_WORKER`, `DICTATION_WORDS_FILE`,
`DICTATION_PREFS_FILE`, `DICTATION_SOCKET` (default `$XDG_RUNTIME_DIR/dictation.sock`). `serve` options: `--live NAME`, `--final NAME`, `--final-beam N`,
`--no-gpu`, `--target SOURCE`, `--max-window S`, `--dry-run` (types nothing, edit events still published),
`--audio-file [MODE=]FILE` (repeatable: a recording replaces the mic, in every session or only in MODE sessions;
played at speaking speed, then silence until `end`; read at every `begin`; for tests without a mic, also with
`--dry-run`).

The shell starts the service on the first key press when the socket is missing (`systemctl --user start
dictation.service`; `QS_DICTATION_START` = another command line for development, e.g. `setsid -f
<dotfiles>/config/dictation/bin/dictation serve`), see `DictationClient.qml`.

## Control interface

Unix socket, newline-delimited both ways, mode 0600. A client gets a `status` event on connect and then every
event. Commands are plain words or JSON:

```
begin cs | begin en | begin translate      {"cmd": "begin", "mode": "cs"}
end                                        key released: final pass, flush, mic closed
cancel                                     drop the session, type nothing more
status                                     reply to this client only
```

Events (one JSON object per line):

| event | fields |
|---|---|
| `status` | `state` (`loading`, `idle`, `listening`, `finishing`, `error`), `mode`, `error`, `code`, `loaded` (the models are in memory) |
| `state` | `state`, `mode` |
| `level` | `value` 0..1 (meaning changed: was RMS dBFS mapped from -60..0), one per 32 ms of audio: 0 = at the session's noise floor (silence, hiss, hum), speech ~0.6-1.0, independent of the mic gain (`level.py`) |
| `preview` | `text` (whole current hypothesis; in translate mode the English preview), `typed` |
| `edit` | `backspace`, `text`: an operation already applied to the focused field |
| `pass` | `slot` (`live`/`final`), `ms`, `audio` seconds |
| `final` | `text` typed this session (with its trailing space; empty when nothing was typed), `ms` (0 when a session without speech ran no final pass); `retried: true` only when the final pass needed a retry |
| `retry` | `what` (`final`), `message`, `code`: informational, the final pass failed and is being run again (see Behaviour) |
| `aborted` | `reason` (`focus`: the focused window changed, typing stopped for the session; `inject`) |
| `error` | `message`, `code` |

Error codes (`error` events and `status.code`; a client must accept a missing one):

| code | when | recovery |
|---|---|---|
| `mic` | no such source, recorder cannot start, exits or sends no audio for 3 s mid-session | session ends; the next `begin` tries again |
| `no-model` | a chosen model is not installed | next `begin` reloads (a model installed later works) |
| `gpu-failed` | Vulkan/GPU init failed (never a silent CPU fallback; prefs `gpu` false opts into the CPU) | next `begin` retries |
| `worker` | worker missing, died, hung (no reply in 20 s on the GPU, 90 s on the CPU) or sent garbage | a dead worker is restarted once inside the session; a second failure cancels it, the next `begin` loads a fresh one |
| `mode` / `command` | bad command (sent only to that client) | none needed |
| `error` | anything else | |

Lifecycle: the service starts with nothing loaded. `begin` starts the recorder first, then loads the models if needed
(`status` `loading`, about 1.2 s with warm disk cache); audio recorded meanwhile is buffered and handed to the session
in order, and `end` or `cancel` during the load are applied after it. After `idle_timeout_s` without a session the
worker process is stopped (RAM and VRAM return to the system) and `status.loaded` is false. A second `begin` during a
session is ignored (that client only gets a `status`). The client whose `begin` started a session disconnecting
cancels it (`dictation begin` sends `"detached": true`, so a CLI session survives its short connection). SIGTERM
cancels a running session (no final pass, nothing more typed) and stops the recorder and worker.

From Quickshell (`import Quickshell.Io`):

```qml
Socket {
    id: dictation
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/dictation.sock"
    connected: true
    parser: SplitParser { onRead: line => handle(JSON.parse(line)) }
}
// key pressed: dictation.write("begin cs\n"); dictation.flush()
// key released: dictation.write("end\n"); dictation.flush()
```

Shell: `dictation begin cs`, `dictation end`, `dictation listen`.

## Behaviour

- Final-pass retry: when the final pass fails (worker crash, hang killed by the recognizer's timeout, GPU error) the
  session is kept (audio buffer, typed text), a `retry` event is broadcast, a fresh worker is loaded and the final pass
  runs once more over the whole audio in the same mode. Success: the normal final edit (tail fix, or the full English
  text in translate mode) and `final` with `retried: true`. Failure (or no worker could be started: `worker`,
  `gpu-failed`, `no-model`): an `error` event, nothing more is typed (transcribe modes keep what the live passes
  typed, no backspaces; translate mode typed nothing), then `idle`, and the next `begin` loads a fresh worker. The
  retry (reload plus pass) is abandoned after `retry_timeout` (default 30 s, the worker is killed); the first attempt
  has the recognizer's own timeout (20 s on the GPU, 90 s on the CPU, plus the audio length), so a session's final
  pass can take at most about that plus 30 s extra. `cancel`, the owner's disconnect and SIGTERM abandon the final pass or its retry at once (worker
  killed, nothing typed). Focus change still suppresses typing.

- Language is pinned per session by the mode (no auto-detect). `translate` = Czech speech, English text.
- Live passes (turbo, greedy) every 0.5 s of new audio (`PASS_EVERY`) once 1.5 s of speech are recorded
  (`MIN_PASS_AUDIO`, counted from the first frame at the speech gate, not from the key press), over a window of at
  most 15 s that starts 0.5 s before the speech and slides at segment boundaries behind the typed text (never after
  the window's last segment, whose end time whisper stretches over speech it has not transcribed yet, and never
  inside a segment). Trailing silence is trimmed to 0.5 s before every pass, and a pause with the key held runs no
  passes (where the room noise stays under the speech gate; above it passes go on, over the same trimmed audio). The tunables are `Config` / the constants at the top of `engine.py`, chosen on replays of recorded speech
  (first text ~2.1 s after the speech starts instead of ~3.0 s; shorter first windows or 0.3 s passes typed more
  words that were erased again).
- A word is typed when two consecutive passes agree on it (compared without case, diacritics and edge punctuation)
  and it is not the newest pass's last word. A correction replaces at most the last 4 typed words, and only when two
  passes agree on it.
- End of speech (`PAUSE_SILENCE`, 1.0 s; `pause_silence_s` in `dictation-prefs.json` overrides it, 0 = off, no UI):
  after that much silence the words still waiting are typed without another pass or the release: the newest pass's
  last word, and a phrase start the cleanup held back (the phrase cannot grow in a pause; if the speech goes on and
  completes the phrase, the usual two-pass tail correction replaces it). Conditions: a pass heard the end of the
  speech (its audio reaches 0.3 s past the last voiced frame; when none did, a closing pass runs 0.5 s into the
  silence, not at the next scheduled time), the pass before it agrees on every new word but the last, it lines up
  with the typed text, no edit happened since, and no voiced frame since. Silence is relative: a frame is voiced at
  the speech gate and 8 dB above the session's tracked noise floor (in a quiet room, floor 12 dB or more under the
  gate, every frame at the gate), so hiss, hum or a noisy room still count as a pause, while breathing loud enough to
  be voiced only delays it; the audio after the speech must also stay under the gate or within 3 dB of the floor
  measured during the speech (soft speech going on in a noisy room never arms it). The last word goes without its punctuation
  (`.,!?;:…`): when the speech goes on, the edit that types the next words adds the punctuation both passes agree on
  (never a backspace; a period typed in a thinking pause would otherwise stay mid-sentence), and on release the final
  pass adds it. One flush per pause; passes in a pause hear the speech plus 0.5 s only, also where the room noise is
  above the absolute gate (no words invented in the noise). Never in translate mode; one short utterance heard by a
  single pass waits for the release; the final pass fixes the tail on release as before. Measured on recorded speech
  with inserted thinking pauses: the word before a pause appears ~1.0 s after it starts instead of with the next
  words (~2 s) or on release; 1.5 s (`pause_silence_s`) gave the same text and corrections, only later.
- Release: the final model (large-v3, beam 5) recognises the whole session; it may fix the last 4 words exactly
  (diacritics, punctuation), then types the rest. It never only erases (a truncated decode keeps the typed text).
- Translate: nothing is typed while speaking; the preview streams from the final model; the English text is typed
  once on release.
- Typing stops for the rest of the session when the focused Hyprland window changes. Text goes to `wtype` on stdin;
  newlines, tabs, control characters and trailing whitespace other than one space are refused, so Enter is never
  sent.
- Trailing space: a session that typed something ends with one space after its final text (in the final edit,
  after the tail fix; translate: after the English text), so the next dictation starts a new word. Never after an
  empty session, a cancel, a focus abort or a failed final pass (only after a successful retry).
  `trailing_space` false in `dictation-prefs.json` turns it off (no UI).
- Fragments: a dictation of one word, or of at most 4 words with no sentence end (`. ? ! …`), is typed without
  whisper's capital ("docker compose up", "yes"); sentences are untouched. A lone word also loses a trailing
  `. , ; : …` ("Yes." -> "yes"; `?` and `!` stay). Decided on the final text: the live passes type the capitalised
  words, the final edit (the tail fix reaches 4 words, so a fragment's first word is always in reach) corrects them.
  Only plain title-case first words change (not `I`, `I'm`, `API`, `GitHub`, words with digits), and replacement text
  is never touched, so a name whisper capitalised ("Praha") is restored by a replacement `praha` -> `Praha`.
  `lowercase_fragments` and `strip_single_word_punct` false in `dictation-prefs.json` turn the two parts off (no UI).
- Every `wtype` run starts with one `Hyper_L` press and release: while the push-to-talk key (consumed by a Hyprland
  bind) is held, Hyprland drops the first key event of a new virtual keyboard (the session's first character was
  lost, in kitty and ghostty). A `VoidSymbol` lead is not usable: ghostty then falls back to the physical key, which
  for wtype's first keycode is Esc.
- One `wtype` run uses at most 13 keycodes (the lead key, BackSpace, then each distinct character in order); longer
  text is typed in several runs. wtype numbers keycodes from evdev 1 and ghostty reads some as their physical key:
  past 13 a capital or accented letter was dropped (14 = BackSpace), letters became Ctrl chords (29) and F-key or
  keypad codes typed escape sequences.
- Silence (no 32 ms frame above RMS 0.005 in the window) is never sent to the recognizer (whisper hallucinates on
  silence). Nor is a session without clear speech: fewer than `min_voiced` (0.25 s) of voiced frames (at the speech
  gate and 8 dB above the noise floor, the lowest one at or after the frame, so a word from the key press on is
  judged by the room noise after it: breath, a key click or tap, room noise) runs no live and no final pass, types
  nothing (no trailing space either) and ends with a normal `final` event with empty text. Whisper returns junk on such
  audio every time (measured: `.`, `Thank you.`, `Titulky vytvořil JohnyX.` on 3 s of silence or noise, 30 of 30
  tries). A pass whose text has no letter or digit (`.`, `...`, `♪`) is empty, and with less than `junk_voiced`
  (0.5 s) of voiced audio the stock phrases of `hallucinations.json` (cs and en, `...` at the end = any rest) are
  empty too; a clearly spoken `Thank you.` has more voiced audio and is typed. Limit: a breath loud and long enough
  (over half a second above the room noise) counts as speech, so the phrase list no longer applies to it.
- Levels (`level.py`): noise floor = a running minimum of the lightly smoothed frame level that follows drops at
  once and rises 1.5 dB/s, 0.3 dB/s while voiced (fluent speech never lifts it; digital zeros never move it); up to 6 dB above it is silence, exactly 0; above that the
  level is scaled against a slowly decaying running peak (at least 14 dB of range), eased with a smoothstep and
  smoothed (fast attack, ~0.1 s release). Measured on recorded speech with white, pink and hum noise added: silence
  ~0 at 30, 20 and 10 dB SNR (the old dB mapping showed 0.06, 0.21 and 0.37 there), speech median 0.90 clean, about
  0.75 at 20 dB SNR, low at 10 dB SNR. The pill draws level 0 as a gently waving ribbon (`DotSwoosh.idleAmp`).
- Cleanup (`cleanup.py`, `Dictation(cleanup=Cleanup())` in `serve` and `replay`; tests use `NoCleanup`) runs on every
  pass before the stability check, so a removed or replaced word is never typed and erased. Rules per text language
  (translate = English). Word lists: `${XDG_STATE_HOME:-~/.local/state}/quickshell/dictation-words.json` (Settings >
  Voice; `{"version":1,"fillers":{"cs":[..],"en":[..]},"replacements":[{"heard","typed","lang":"any|cs|en"}],
  "hints":false}`), re-read at a `begin` when its mtime changed; missing, malformed or partial = the built-in fillers
  (`default-words.json`; a language present in the file replaces its default list) and no replacements.
- Fillers: whole words, without case or diacritics, drawn-out forms too (`hmmm`, `eeee`; a doubled letter alone is
  not: `err` stays). Their trailing comma goes with them, a sentence end moves to the previous word, a capitalized
  filler capitalizes the next word, no dangling comma at the end. Real words (Czech `no`, `tak`, `jako`) are never
  defaults.
- Replacements: heard words or phrases -> typed, whole words, case-insensitive, never across punctuation, longest
  phrase first, replaced text never re-matched; the typed form takes the original's ALL CAPS or capital first letter,
  else stays as entered. A live pass holds back trailing words that may still start a longer phrase until the next
  word decides; the final pass flushes everything.
- Vocabulary hints (switch `prompt_hints` in `dictation-prefs.json` next to the word file, `DICTATION_PREFS_FILE`;
  the word file's `hints` counts only when the prefs have none; default off): the replacement targets (at most 12,
  160 characters) as whisper's initial prompt, live and final passes, never in translate mode. Off by default: on the
  benchmark they were not a clear win (own clips: turbo English WER 8.3 -> 4.2 %, large-v3 Czech 4.4 -> 6.7 %;
  unrelated hints raised turbo FLEURS English 3.3 -> 5.6 %). Worker protocol: optional 7th header field PROMPTBYTES.

## Tests

```
python3 -I -m unittest discover -s config/dictation/tests
```

The real-model test runs only with local fixtures (never commit audio): `DICTATION_TEST_FIXTURES=DIR` with
`NAME.wav` (16 kHz mono) plus `NAME.txt` = `MODE<TAB>expected text`, and the worker and models present; otherwise it
skips with a message. `dictation replay FILE.wav --mode cs --realtime` prints the edit operations and timings for a
recording without typing anything.

Testing the `wtype` adapter against a real compositor: only in a private nested session, with
`DICTATION_FORBID_DISPLAY` set so the adapter refuses the live display: a bare name refuses every display of that
name, an absolute socket path only that socket (a nested compositor's socket is often named `wayland-1` too).

## Caveats

- Speech the live passes keep disagreeing on can be skipped while later speech is agreed and typed; the final pass
  cannot insert in the middle (corrections are tail-only). Seen only with English sentences inside a Czech session.
- The final pass time grows with the session (about 0.3 s for 3 s of speech, 1.1-1.3 s for 14-20 s, 1.7 s for 45 s
  on a recent discrete AMD GPU); `--final-beam 0` is faster but truncated a 20 s decode once.
- Both models together take about 5.3 GB VRAM and 130 MB RSS (measured); they load on the first `begin` and unload
  after the idle timeout. A failed final pass is retried once (see
  Behaviour, Final-pass retry). The recorder is PipeWire, which has no exclusive access, so "mic busy" does not exist;
  an unplugged device shows as a missing source or as silence (`mic` error after 3 s without audio).
- A window without a usable cut (one long segment) keeps growing; whisper handles more than 30 s, passes get slower.
