"""Dictation engine: one push-to-talk session, from audio frames to edit operations for the focused field.

Interface (everything else is internal):
    d = Dictation(recognizer, injector, focus=..., emit=..., cleanup=..., config=Config())
    d.begin("<language code>" | "translate:<language code>" | "translate")   # pinned language per session, never auto-detect
    d.feed(pcm)                          # float32 little-endian, 16 kHz mono; thread-safe, publishes levels
    d.step()                             # runs one live pass when enough new audio arrived
    d.end()                              # final pass over the whole session, flushes the rest
    d.cancel()

Events passed to emit (dicts): state, level, pass, preview, edit, aborted, final. Edit operations go to the injector
as apply(backspace, text); text never contains a newline, tab or control character. A session that typed something
ends with one space after the final text (`Config.trailing_space`), so the next dictation starts a new word.

Streaming (transcribe modes): the live model re-recognises a sliding window of recent audio. A word is typed once two
consecutive passes agree on it (compared without case, diacritics and edge punctuation) and it is not the last word
of the newest pass (nor a word the cleanup holds back as the start of a possible phrase). A later disagreement may
replace only the last `tail_words` typed words. On release the final model recognises the whole session; it may
again fix only the tail, then everything after it is typed. Translate mode types nothing while speaking (preview
only) and types the English text once on release. If the focused window changes, typing stops for the rest of the
session.
"""
from __future__ import annotations

import array
import difflib
import json
import math
import os
import re
import threading
import unicodedata
from dataclasses import dataclass
from typing import Callable, NamedTuple, Protocol

from .cleanup import lowercase_segments
from .languages import AUTO, Mode, clean_languages, parse_mode
from .level import LevelMeter

SAMPLE_RATE = 16000
HALLUCINATIONS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hallucinations.json")
_BPS = 4  # bytes per float32 sample


class Segment(NamedTuple):
    t0: float  # seconds from the start of the audio passed in
    t1: float
    text: str


class Recognition(NamedTuple):
    segments: list
    ms: float


class RecognizerError(RuntimeError):
    """The recognizer is broken (worker died, hung or out of step); the service restarts it."""


class Recognizer(Protocol):
    def transcribe(self, audio: bytes, *, slot: str, language: str, translate: bool) -> Recognition: ...


class Detector(Protocol):
    """Optional on a recognizer: detect(audio, slot=...) -> {language code: probability} (auto mode)."""

    def detect(self, audio: bytes, *, slot: str) -> dict: ...


class Injector(Protocol):
    def apply(self, backspace: int, text: str) -> None: ...


LIVE, FINAL = "live", "final"

# Streaming defaults (README, Behaviour; measured on recorded speech with the real models, see Config).
MIN_PASS_AUDIO = 1.5
PASS_EVERY = 0.5
PAUSE_SILENCE = 1.0
TRAILING_SPACE = True
NOISE_SPREAD_DB = 3.0  # room noise frames stay this close to the tracked floor
QUIET_ROOM_DB = 12.0  # a noise floor this far under the speech gate: every frame at the gate counts as speech


@dataclass
class Config:
    # Timing of the live passes and of the end-of-speech flush: the tunables of the streaming behaviour, all here.
    min_pass_audio: float = MIN_PASS_AUDIO  # seconds from the first speech to the first live pass
    pass_every: float = PASS_EVERY  # seconds of new audio between live passes
    pause_silence: float = PAUSE_SILENCE  # this much silence after speech types the words still waiting (0 = never)
    close_after: float = 0.5  # silence after which a pass that has not heard the speech end runs at once
    heard_pad: float = 0.3  # a pass whose audio reaches this far past the last voiced frame heard the speech end
    trailing_space: bool = TRAILING_SPACE  # one space after the final text of a session that typed something
    max_window: float = 15.0  # slide the window once it is longer (longer windows decode more text per pass)
    lowercase_fragments: bool = True  # the final text of a fragment (one word, or <= 4 without a sentence end) starts lower-case
    strip_single_word_punct: bool = True  # a lone word loses its trailing . , ; : … (? and ! stay)
    tail_words: int = 4  # corrections never reach further back than this many typed words
    level_frame: int = 512  # samples per published level (32 ms)
    speech_rms: float = 0.005  # a window with no frame this loud is silence and is never recognised
    silence_pad: float = 0.5  # seconds of silence kept around speech when trimming it
    # Evidence of speech, counted in voiced frames (at the speech gate and above the noise floor, like the end-of-speech
    # detector): less than min_voiced seconds and the session had no speech (breath, a key click, room noise): no pass,
    # no final pass, nothing typed. With less than junk_voiced seconds the stock phrases whisper invents on noise
    # (hallucinations.json) are dropped as well; a clearly spoken "Thank you." has more.
    min_voiced: float = 0.25
    junk_voiced: float = 0.5


class NoCleanup:
    """Seam for the cleanup stage (cleanup.Cleanup: filler filter, replacement list, vocabulary hints). The default
    changes nothing.

    begin(language, translate) -> prompt: at every session start (language = the text's language, "en" when
    translating); the returned prompt ("" = none) goes to every recognizer call of the session.
    apply(segments, language) -> (segments, hold): every pass's words per segment, before the stability check; a
    live pass never types the last `hold` words (a phrase that may still complete). The final pass ignores hold."""

    def begin(self, language: str, translate: bool) -> str:
        return ""

    def apply(self, segments: list, language: str) -> tuple:
        return segments, 0


identity_cleanup = NoCleanup()


# --- text helpers -----------------------------------------------------------------------------------------------

_PAUSE_PUNCT = ".,!?;:…"  # left off the last word a pause types, added when the speech goes on (or by the final pass)
_ANNOTATION = re.compile(r"\[[^\]]*\]|^\s*\([^)]*\)\s*$")  # [BLANK_AUDIO], a whole-segment "(music)"


def _sanitize(text: str) -> str:
    """NFC (one code point per Czech letter, so one BackSpace per character), every whitespace or control
    character becomes a single space, no leading or trailing space."""
    text = unicodedata.normalize("NFC", text)
    text = "".join(" " if c.isspace() or c == "\ufffd" or unicodedata.category(c) in ("Cc", "Cf", "Zl", "Zp") else c
                   for c in text)
    return " ".join(text.split())


def _norm(word: str) -> str:
    """Comparison key: no case, no diacritics, no punctuation at the edges."""
    base = "".join(c for c in unicodedata.normalize("NFKD", word) if not unicodedata.combining(c)).casefold()
    stripped = base.strip("".join(chr(c) for c in range(0x21, 0x80) if not chr(c).isalnum()) + "…–—„“”‚‘’«»¿¡")
    return stripped or base


def _plain(text: str) -> str:
    """Words only: no case, diacritics or punctuation, single spaces."""
    base = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)).casefold()
    return " ".join("".join(c if c.isalnum() else " " for c in base).split())


def _load_hallucinations() -> tuple:
    """(exact phrases, prefixes) from hallucinations.json; an entry ending in ... is a prefix."""
    try:
        with open(HALLUCINATIONS_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return frozenset(), ()
    exact, prefixes = set(), []
    for key, entries in data.items():
        for entry in entries if key != "note" and isinstance(entries, list) else ():
            if entry.rstrip().endswith(("...", "…")):
                prefixes.append(_plain(entry))
            else:
                exact.add(_plain(entry))
    return frozenset(exact), tuple(p for p in prefixes if p)


_HALLUCINATIONS = _load_hallucinations()


def _is_hallucination(text: str) -> bool:
    plain = _plain(text)
    exact, prefixes = _HALLUCINATIONS
    return plain in exact or any(plain == p or plain.startswith(p + " ") for p in prefixes)


def _lcp(a: list, b: list) -> int:
    n = 0
    for x, y in zip(a, b):
        if _norm(x) != _norm(y):
            break
        n += 1
    return n


def _join(words: list) -> str:
    return " ".join(words)


def _plan(committed: list, hyp: list, tail: int, exact: bool) -> tuple:
    """Line the typed words up with a hypothesis. Returns (keep, resume, mapping): keep the first `keep` typed words
    (at most `tail` of them may go), continue with hyp[resume:]. The tail is kept only where it lines up word after
    word with the hypothesis (`exact`: spelled the same too, so diacritics and punctuation get fixed)."""
    if not committed:
        return 0, 0, {}
    nc, nh = [_norm(w) for w in committed], [_norm(w) for w in hyp]
    mapping = {}
    for a, b, size in difflib.SequenceMatcher(None, nc, nh, autojunk=False).get_matching_blocks():
        for i in range(size):
            mapping[a + i] = b + i
    keep = len(committed)
    for i in range(max(0, len(committed) - tail), len(committed)):
        lined_up = i in mapping and (i - 1 not in mapping or mapping[i] == mapping[i - 1] + 1)
        if not lined_up or (exact and committed[i] != hyp[mapping[i]]):
            keep = i
            break
    anchor = max((i for i in mapping if i < keep), default=None)
    if keep == 0:
        resume = 0
    elif anchor is None:
        resume = min(keep, len(hyp))  # nothing lines up: assume word-for-word
    else:
        resume = min(len(hyp), mapping[anchor] + 1 + (keep - 1 - anchor))
    return keep, resume, mapping


def reconcile_live(committed: list, prev: list, cur: list, tail: int, hold: int = 0, last: bool = False) -> list:
    """What the window's typed words become after a pass: the words after the typed text that this pass and the
    previous one agree on (never the newest pass's last word, nor its last `hold` words), with a tail correction only
    when both passes agree on it and on at least one replacement word.

    last: the speech has ended (a pause after a pass that heard its end): when the two passes agree on every new
    word but the newest pass's last one, that last word is taken too (hold is then 0: the phrase cannot grow)."""
    keep, resume, _ = _plan(committed, cur, tail, exact=False)
    keep_prev, resume_prev, _ = _plan(committed, prev, tail, exact=False)
    if keep != keep_prev:
        return committed
    if last:
        new, new_prev = cur[resume:], prev[resume_prev:]
        n = _lcp(new_prev, new)
        agreed = new if n >= len(new) - 1 else new[:n]
    else:
        new, new_prev = cur[resume : len(cur) - max(1, hold)], prev[resume_prev:]
        agreed = new[: _lcp(new_prev, new)]
    if keep < len(committed) and not agreed:
        return committed
    return committed[:keep] + agreed


def reconcile_final(committed: list, final: list, tail: int) -> list:
    """Keep the typed words except a tail the final pass disagrees with (exactly, so diacritics and punctuation are
    fixed there), then continue with the final words after the kept part."""
    keep, resume, _ = _plan(committed, final, tail, exact=True)
    if keep < len(committed) and resume >= len(final):
        # the final pass has nothing where the typed tail is (a truncated decode): fixing it would only erase
        keep, resume, _ = _plan(committed, final, 0, exact=True)
    return committed[:keep] + final[resume:]


def _cut(pairs: list, max_words: int) -> tuple:
    """Where the next window starts, as (words before the cut, seconds): after the last whole segment that lies
    within the first `max_words` words, leaving at least one of those words in the window (the anchor that lines the
    next pass up with the typed text). Never after the last segment: whisper stretches its end over speech it has
    not transcribed yet, and never inside a segment (word times are not known; a guess duplicates or drops words).
    (0, None) when there is nothing to cut: the window then grows (whisper itself handles more than 30 s)."""
    count, cut_words, cut_t = 0, 0, None
    for idx, (seg, ws) in enumerate(pairs[:-1]):
        if count + len(ws) >= max_words:
            break
        count += len(ws)
        if ws and seg.t1 > 0:
            nxt = pairs[idx + 1][0]
            cut_words, cut_t = count, min(seg.t1, nxt.t0) if nxt.t0 > 0 else seg.t1
    return cut_words, cut_t


# --- the engine ---------------------------------------------------------------------------------------------------


class _Session:
    def __init__(self, mode: Mode, focus_at_begin):
        self.mode = mode
        self.focus = focus_at_begin
        self.pcm = bytearray()
        self.carry = b""  # bytes of an incomplete sample
        self.levels: list[float] = []  # RMS per level frame, for the speech gate
        self.level_acc = array.array("f")
        self.meter = LevelMeter()  # noise-floor-aware level for the pill and the voiced flag
        self.first_loud: int | None = None  # first frame at the speech gate
        self.voiced_frames = 0  # frames that counted as speech (see Config.min_voiced)
        self.floors: list = []  # the noise floor (dB, None before the first) after each level frame, for _has_voice
        self.recount = (0, 0)  # (frames, voiced) of the last look back with the later floor (see _has_voice)
        self.last_voiced: int | None = None  # last frame well above the noise floor (end-of-speech detector)
        self.pending_flush: tuple | None = None  # (typed, target, last_voiced, bare): what a pause would type
        self.bare: int | None = None  # index (in typed words) of the word a pause typed without its punctuation
        self.closed_for: int | None = None  # last_voiced the closing pass already ran for
        self.floor_at_voiced: float | None = None  # the noise floor (dB) when the last voiced frame came
        self.flushed_for: int | None = None  # last_voiced a pause already typed the waiting words for
        self.window_start = 0  # in samples
        self.last_pass_end = None  # samples recognised by the previous live pass
        self.prev: list | None = None  # previous pass words (window-relative)
        self.typed = ""  # everything typed this session
        self.frozen = 0  # typed words that lie before the window
        self.frozen_preview: list = []  # translate mode: preview words that lie before the window
        self.aborted = False
        self.language = None if mode.language == AUTO else mode.language  # auto: None until detected, then pinned
        self.allowed: tuple = ()  # auto: the languages the detection may pick (empty = any)
        self.text_language = "en" if mode.translate else (mode.language if self.language else "")  # the cleanup's rules
        self.prompt = ""  # the cleanup's vocabulary hints for the recognizer


class Dictation:
    def __init__(
        self,
        recognizer: Recognizer,
        injector: Injector,
        *,
        focus: Callable[[], object] = lambda: None,
        emit: Callable[[dict], None] = lambda event: None,
        cleanup: NoCleanup = identity_cleanup,
        config: Config | None = None,
    ):
        self.recognizer = recognizer
        self.injector = injector
        self.focus = focus
        self.emit = emit
        self.cleanup = cleanup
        self.config = config or Config()
        self._s: _Session | None = None
        self._lock = threading.Lock()
        self._type_lock = threading.Lock()  # cancel() waits for an edit in flight, so nothing is typed after it

    @property
    def active(self) -> bool:
        return self._s is not None

    @property
    def mode(self) -> str | None:
        s = self._s  # read once: the controller thread may end the session meanwhile (status() runs on the loop)
        return s.mode.name if s else None

    def begin(self, mode: str, languages=()) -> None:
        parsed = parse_mode(mode)
        if parsed is None:
            raise ValueError(f"unknown mode {mode!r}, want a language code, translate:<code> or translate")
        if self._s is not None:
            raise RuntimeError("a session is already running")
        s = _Session(parsed, self.focus())
        s.allowed = clean_languages(languages)
        s.prompt = self.cleanup.begin(s.text_language, s.mode.translate)
        with self._lock:
            self._s = s
        self.emit({"event": "state", "state": "listening", "mode": mode})

    def feed(self, pcm: bytes) -> None:
        with self._lock:
            s = self._s
            if s is None:
                return
            data = s.carry + pcm
            usable = len(data) - len(data) % _BPS
            s.carry = data[usable:]
            s.pcm += data[:usable]
            samples = array.array("f")
            samples.frombytes(data[:usable])
        frame = self.config.level_frame
        levels = []
        acc = s.level_acc
        for x in samples:
            acc.append(x)
            if len(acc) == frame:
                rms = math.sqrt(sum(v * v for v in acc) / frame)
                levels.append(rms)
                del acc[:]
        gate_db = 20 * math.log10(self.config.speech_rms)
        for rms in levels:
            value, voiced = s.meter.push(rms)
            loud = rms >= self.config.speech_rms
            index = len(s.levels)
            s.levels.append(rms)
            s.floors.append(s.meter.floor)
            if loud and s.first_loud is None:
                s.first_loud = index
            # speech for the end-of-speech detector: at the absolute gate, and well above the noise floor where the
            # room is noisy (a quiet room's floor lies far under the gate: soft speech still counts there)
            if loud and (voiced or s.meter.floor is not None and s.meter.floor <= gate_db - QUIET_ROOM_DB):
                s.last_voiced, s.floor_at_voiced = index, s.meter.floor
                s.voiced_frames += 1
            self.emit({"event": "level", "value": round(value, 3)})

    def step(self) -> bool:
        """Run one live pass if it is due (or type what a pause made final). Returns whether a pass ran."""
        s = self._s
        if s is None or s.aborted:
            return False
        cfg = self.config
        frame = cfg.level_frame
        with self._lock:
            total = len(s.pcm) // _BPS
        if s.first_loud is None or not self._has_voice(s, cfg.min_voiced):
            return False
        last_voiced = s.last_voiced  # read once: the capture thread moves it
        closing = self._closing_due(s, last_voiced)
        if not closing and total - s.first_loud * frame < cfg.min_pass_audio * SAMPLE_RATE:
            return False
        previous = s.last_pass_end
        if not closing and previous is not None and total - previous < cfg.pass_every * SAMPLE_RATE:
            self._flush_if_paused(s)
            return False
        if previous is None and s.prev is None:
            # the first pass: the window starts shortly before the speech (leading silence invites hallucinations)
            s.window_start = max(s.window_start, self._speech_start(s))
        s.last_pass_end = total
        if closing:
            s.closed_for = last_voiced
        # nothing new was said (a pause with the key held): the same audio would only invite hallucinations
        start = s.window_start if previous is None or closing else -(-previous // frame) * frame
        if not self._has_speech(s, start, total):
            self._flush_if_paused(s)
            return False
        end = self._speech_end(s, total)
        voiced_end = None if last_voiced is None else (last_voiced + 1) * frame
        if (cfg.pause_silence and not s.mode.translate and voiced_end is not None
                and total - voiced_end >= cfg.close_after * SAMPLE_RATE):
            # in a pause the window ends shortly after the voiced speech even where the room noise is above the
            # absolute gate: passes in the pause hear the same audio (no words invented in the noise)
            end = min(end, voiced_end + int(cfg.silence_pad * SAMPLE_RATE))
            if end <= s.window_start + frame:
                self._flush_if_paused(s)
                return False  # the window slid past the speech: nothing left to recognise
        with self._lock:
            audio = bytes(s.pcm[s.window_start * _BPS : end * _BPS])
        slot = FINAL if s.mode.translate else LIVE
        result = self._transcribe(s, audio, slot)
        self.emit({"event": "pass", "slot": slot, "ms": round(result.ms), "audio": round(len(audio) / _BPS / SAMPLE_RATE, 2)})
        if self._s is not s:
            return True  # cancelled meanwhile
        pairs, hold = self._segment_words(s, result.segments)
        cur = [w for _, ws in pairs for w in ws]
        window_len = (end - s.window_start) / SAMPLE_RATE

        if s.mode.translate:
            self.emit({"event": "preview", "text": _join(s.frozen_preview + cur)})
            s.prev = cur
            if window_len > cfg.max_window and len(pairs) > 1:
                # keep the preview of complete sentences, re-recognise only the last one
                cut_words, cut_t = _cut(pairs, len(cur) - len(pairs[-1][1]) + 1)
                if cut_t:
                    s.frozen_preview += cur[:cut_words]
                    s.window_start += round(cut_t * SAMPLE_RATE)
            return True

        words = s.typed.split()
        s.pending_flush = None
        if s.prev is not None:
            committed = words[s.frozen :]
            target = reconcile_live(committed, s.prev, cur, cfg.tail_words, hold)
            target = self._repunctuate(s, committed, target, cur)
            self._type(s, _join(words[: s.frozen] + target))
            if (voiced_end is not None and end - voiced_end >= cfg.heard_pad * SAMPLE_RATE
                    and self._quiet_after(s, voiced_end, end)):
                # this pass heard the end of the speech: if a pause follows, its last words are final (the phrase
                # cannot grow, so the cleanup's hold no longer applies)
                words = s.typed.split()
                flush = reconcile_live(words[s.frozen :], s.prev, cur, cfg.tail_words, 0, last=True)
                if len(flush) > len(words) - s.frozen and flush[: len(words) - s.frozen] == words[s.frozen :]:
                    # its punctuation waits for what follows: a period typed in a thinking pause would stay mid-sentence
                    bare = flush[-1].rstrip(_PAUSE_PUNCT) or flush[-1]
                    s.pending_flush = (s.typed, _join(words[: s.frozen] + flush[:-1] + [bare]), last_voiced,
                                       s.frozen + len(flush) - 1 if bare != flush[-1] else None)
        s.prev = cur
        words = s.typed.split()
        self.emit({"event": "preview", "text": _join(words[: s.frozen] + cur), "typed": s.typed})
        if window_len > cfg.max_window and not s.aborted:
            # slide past whole segments whose words are all typed
            committed = words[s.frozen :]
            keep, settled, mapping = _plan(committed, cur, cfg.tail_words, exact=False)
            cut_words, cut_t = _cut(pairs, settled)
            if cut_t:
                typed_before = [i for i, b in mapping.items() if b < cut_words and i < keep]
                s.frozen += max(typed_before) + 1 if typed_before else 0
                s.window_start += round(cut_t * SAMPLE_RATE)
                s.prev = cur[cut_words:]
        return True

    def end(self, *, keep_on_failure: bool = False, retry: bool = False) -> str:
        """Final pass over the whole session and flush. Returns the text the session typed.

        keep_on_failure: when the recognizer fails (RecognizerError) the session stays open, with its audio and what it
        typed, so the caller can swap the recognizer and call end() again (retry=True marks that call: the final event
        then says `retried`). Without it any failure closes the session. A cancel() meanwhile (another thread) makes
        this return without typing anything more."""
        s = self._s
        if s is None:
            return ""
        retained = False
        try:
            if s.aborted:
                return s.typed
            with self._lock:
                total = len(s.pcm) // _BPS
            if total == 0 or not self._has_speech(s, 0, total) or not self._has_voice(s, self.config.min_voiced):
                # nothing was said (silence, breath, a key click): no final pass, nothing typed, a normal final event
                self.emit({"event": "final", "text": s.typed, "ms": 0})
                return s.typed
            start, end = self._speech_start(s), self._speech_end(s, total)
            with self._lock:
                audio = bytes(s.pcm[start * _BPS : end * _BPS])
            result = self._transcribe(s, audio, FINAL)
            if self._s is not s:
                return s.typed  # cancelled meanwhile
            self.emit({"event": "pass", "slot": FINAL, "ms": round(result.ms), "audio": round((end - start) / SAMPLE_RATE, 2)})
            final = [w for _, ws in self._segment_words(s, result.segments, final=True)[0] for w in ws]
            if s.mode.translate:
                self.emit({"event": "preview", "text": _join(final)})
            target = _join(reconcile_final(s.typed.split(), final, self.config.tail_words))
            if target and self.config.trailing_space:
                target += " "  # after the corrected text, in the same edit (and the same focus guard)
            self._type(s, target)
            if self._s is not s:
                return s.typed
            event = {"event": "final", "text": s.typed, "ms": round(result.ms)}
            if retry:
                event["retried"] = True
            self.emit(event)
            return s.typed
        except RecognizerError:
            if keep_on_failure and self._s is s:
                retained = True
                raise
            with self._lock:
                self._s = None
            raise
        except BaseException:
            # the caller reports the failure first: idle only after its error event, else a client closes on idle
            # and never sees why (Service._fail emits error, then idle)
            with self._lock:
                self._s = None
            raise
        finally:
            if self._s is s and not retained:
                self._close()

    def cancel(self) -> None:
        s = self._s
        if s is not None:
            with self._type_lock:
                s.aborted = True  # a pass still running in another thread must not type its result
            self._close()

    # --- internals ---

    def _close(self):
        with self._lock:
            self._s = None
        self.emit({"event": "state", "state": "idle"})

    def _quiet_after(self, s: _Session, start: int, end: int) -> bool:
        """The audio after the voiced speech is really quiet: under the speech gate, or (a room noisier than the
        gate) within NOISE_SPREAD_DB of the noise floor as it was during the speech (the floor would follow a soft
        sound that goes on). Soft speech that goes on there must not arm the flush."""
        floor = s.floor_at_voiced
        frame = self.config.level_frame
        for rms in s.levels[start // frame : -(-end // frame)]:
            if rms >= self.config.speech_rms and (floor is None or 20 * math.log10(rms) > floor + NOISE_SPREAD_DB):
                return False
        return True

    def _closing_due(self, s: _Session, last_voiced) -> bool:
        """The speech stopped (`close_after` of silence after the last voiced frame) and no pass has heard its end
        yet: run one now instead of at the next scheduled time (there is none in a pause), so a pause can type it."""
        cfg = self.config
        if s.mode.translate or not cfg.pause_silence or last_voiced is None or s.closed_for == last_voiced:
            return False
        if s.pending_flush is not None and s.pending_flush[2] == last_voiced:
            return False  # the latest pass already heard it
        silent = (len(s.levels) - last_voiced - 1) * cfg.level_frame
        return silent >= min(cfg.close_after, cfg.pause_silence) * SAMPLE_RATE

    def _flush_if_paused(self, s: _Session) -> None:
        """End of speech: `pause_silence` without a voiced frame after a pass that heard the speech end types the
        words that pass left waiting (its last word, a phrase start the cleanup held back). Not while the speech goes
        on (a new voiced frame), not after another edit, never in translate mode (pending_flush stays None)."""
        cfg, pending = self.config, s.pending_flush
        if pending is None or not cfg.pause_silence:
            return
        typed, target, last_voiced, bare = pending
        if s.last_voiced != last_voiced or s.typed != typed or s.flushed_for == last_voiced:
            return  # speech again, another edit, or this pause already typed its words (later passes in a noisy
            # pause wait for the usual two-pass rule: whisper may invent a word in the noise)
        if (len(s.levels) - last_voiced - 1) * cfg.level_frame < cfg.pause_silence * SAMPLE_RATE:
            return
        s.pending_flush, s.closed_for, s.flushed_for = None, last_voiced, last_voiced
        self._type(s, target)
        if s.typed == target:
            s.bare = bare

    def _repunctuate(self, s: _Session, committed: list, target: list, cur: list) -> list:
        """A word a pause typed without its punctuation (s.bare) gets it when the speech goes on: in the edit that
        types the next words, only as an addition (never a backspace), and only the spelling both passes agree on."""
        if s.bare is None:
            return target
        i = s.bare - s.frozen
        if i < 0 or i >= len(committed) or i >= len(target) or target[i] != committed[i]:
            s.bare = None  # slid out of the window or corrected: nothing to add
            return target
        if len(target) == i + 1:
            return target  # nothing after it yet: wait
        s.bare = None
        spelled = set()
        for hyp in (cur, s.prev):
            _, _, mapping = _plan(committed, hyp, len(committed), exact=False)
            spelled.add(hyp[mapping[i]] if i in mapping else None)
        if len(spelled) == 1:
            word = spelled.pop()
            if word and word != committed[i] and word.startswith(committed[i]) \
                    and not word[len(committed[i]):].strip(_PAUSE_PUNCT):
                target = target[:i] + [word] + target[i + 1 :]
        return target

    def _has_speech(self, s: _Session, start: int, end: int) -> bool:
        frame = self.config.level_frame
        return any(rms >= self.config.speech_rms for rms in s.levels[start // frame : -(-end // frame)])

    def _has_voice(self, s: _Session, seconds: float) -> bool:
        need = seconds * SAMPLE_RATE / self.config.level_frame
        if s.voiced_frames >= need:
            return True
        return self._voiced_by_later_floor(s) >= need

    def _voiced_by_later_floor(self, s: _Session) -> int:
        """Voiced frames judged against the lowest floor at or after each frame. Speech from the key press on (no room
        noise first) sets the floor at the speech itself, so at the time nothing was 8 dB above it; the pause after
        the word shows the room. Only a lower floor counts back: one that rises later (a fan turned on) never
        lowers the evidence the frames already gave."""
        n = min(len(s.levels), len(s.floors))  # the capture thread appends to both
        if n == s.recount[0]:
            return s.recount[1]
        gate_db, voice = 20 * math.log10(self.config.speech_rms), s.meter.voice
        floor, count = None, 0
        for i in range(n - 1, -1, -1):
            f = s.floors[i]
            if f is not None and (floor is None or f < floor):
                floor = f
            rms = s.levels[i]
            if floor is None or rms < self.config.speech_rms:
                continue
            if 20 * math.log10(rms) - floor >= voice or floor <= gate_db - QUIET_ROOM_DB:
                count += 1
        s.recount = (n, count)
        return count

    def _speech_end(self, s: _Session, total: int) -> int:
        """Sample after the last loud frame plus a short pad: trailing silence is where whisper hallucinates."""
        frame, pad = self.config.level_frame, int(self.config.silence_pad * SAMPLE_RATE)
        last = next((i for i in range(len(s.levels) - 1, -1, -1) if s.levels[i] >= self.config.speech_rms), None)
        return total if last is None else min(total, (last + 1) * frame + pad)

    def _speech_start(self, s: _Session) -> int:
        frame, pad = self.config.level_frame, int(self.config.silence_pad * SAMPLE_RATE)
        first = next((i for i, rms in enumerate(s.levels) if rms >= self.config.speech_rms), 0)
        return max(0, first * frame - pad)

    def _transcribe(self, s: _Session, audio: bytes, slot: str):
        if s.language is None:
            self._detect(s, audio, slot)
        extra = {"prompt": s.prompt} if s.prompt else {}  # recognizers without hint support never see the keyword
        return self.recognizer.transcribe(audio, slot=slot, language=s.language, translate=s.mode.translate, **extra)

    def _detect(self, s: _Session, audio: bytes, slot: str) -> None:
        """Auto mode: the language of the session, decided once on the first pass that has speech (the first live
        pass, or the final pass of a session too short for one) and pinned for the rest of it, so it cannot flip
        between passes and the text typed so far never changes language. With a language selection the most probable
        selected language wins (a language outside it is never picked); a recognizer or worker that cannot detect
        gets the first selected language, else English."""
        probs = {}
        detect = getattr(self.recognizer, "detect", None)
        if detect is not None:
            try:
                probs = detect(audio, slot=slot) or {}
            except ValueError:  # a worker that predates detection refuses the request
                probs = {}
        pool = s.allowed or tuple(probs)
        best = max((c for c in pool if c in probs), key=lambda c: probs[c], default=None)
        s.language = best or (s.allowed[0] if s.allowed else "en")
        s.text_language = s.language
        s.prompt = self.cleanup.begin(s.language, False)
        self.emit({"event": "language", "language": s.language, "detected": best is not None})

    def _segment_words(self, s: _Session, segments, final: bool = False) -> tuple:
        """([(segment, words)], hold) after the cleanup stage, which sees the whole pass (phrases may span
        segments). The final pass also lower-cases a fragment's first word (Config.lowercase_fragments) and strips a
        lone word's trailing . , ; : … (strip_single_word_punct); live passes cannot know yet whether the dictation
        will be one, the final edit fixes the already typed text (a
        fragment has at most tail_words words, so its first word is always inside the correctable tail)."""
        raw = [_sanitize(_ANNOTATION.sub(" ", unicodedata.normalize("NFC", seg.text))).split() for seg in segments]
        if self._junk(s, raw):
            raw = [[] for _ in raw]
        style = (self.config.lowercase_fragments, self.config.strip_single_word_punct)
        if final and any(style):
            apply_final = getattr(self.cleanup, "apply_final", None)
            if apply_final:  # the cleanup knows which words are replacement text and leaves them alone
                cleaned, hold = apply_final(raw, s.text_language, *style)
            else:
                cleaned, hold = self.cleanup.apply(raw, s.text_language)
                cleaned = lowercase_segments(cleaned, *style)
        else:
            cleaned, hold = self.cleanup.apply(raw, s.text_language)
        return [(seg, _sanitize(" ".join(ws)).split()) for seg, ws in zip(segments, cleaned)], hold

    def _junk(self, s: _Session, raw: list) -> bool:
        """A pass that is no text (only punctuation or symbols: '.', '...', '♪') or, with little voiced audio, only
        a stock phrase whisper invents on noise ('Thank you.', 'Titulky vytvořil ...')."""
        text = " ".join(w for ws in raw for w in ws)
        if not any(c.isalnum() for c in text):
            return True
        return not self._has_voice(s, self.config.junk_voiced) and _is_hallucination(text)

    def _type(self, s: _Session, target: str) -> None:
        with self._type_lock:
            self._type_locked(s, target)

    def _type_locked(self, s: _Session, target: str) -> None:
        if s.aborted or target == s.typed:
            return
        if self.focus() != s.focus:
            s.aborted = True
            self.emit({"event": "aborted", "reason": "focus"})
            return
        keep = len(os.path.commonprefix([s.typed, target]))
        backspace, text = len(s.typed) - keep, target[keep:]
        try:
            self.injector.apply(backspace, text)
        except Exception as exc:  # the field state is unknown now: never type into it again this session
            s.aborted = True
            self.emit({"event": "aborted", "reason": "inject", "message": str(exc)})
            return
        s.typed = target
        self.emit({"event": "edit", "backspace": backspace, "text": text})
