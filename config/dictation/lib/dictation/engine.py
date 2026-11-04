"""Dictation engine: one push-to-talk session, from audio frames to edit operations for the focused field.

Interface (everything else is internal):
    d = Dictation(recognizer, injector, focus=..., emit=..., cleanup=..., config=Config())
    d.begin("cs" | "en" | "translate")   # pinned language per session, never auto-detect
    d.feed(pcm)                          # float32 little-endian, 16 kHz mono; thread-safe, publishes levels
    d.step()                             # runs one live pass when enough new audio arrived
    d.end()                              # final pass over the whole session, flushes the rest
    d.cancel()

Events passed to emit (dicts): state, level, pass, preview, edit, aborted, final. Edit operations go to the injector
as apply(backspace, text); text never contains a newline, tab or control character and the field never ends with
a space the engine typed.

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
import math
import os
import re
import threading
import unicodedata
from dataclasses import dataclass
from typing import Callable, NamedTuple, Protocol

SAMPLE_RATE = 16000
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


class Injector(Protocol):
    def apply(self, backspace: int, text: str) -> None: ...


@dataclass(frozen=True)
class Mode:
    name: str
    language: str
    translate: bool


MODES = {
    "cs": Mode("cs", "cs", False),
    "en": Mode("en", "en", False),
    "translate": Mode("translate", "cs", True),
}

LIVE, FINAL = "live", "final"


@dataclass
class Config:
    min_pass_audio: float = 3.0  # shorter prefixes come out as garbage on the live model
    pass_every: float = 0.5  # seconds of new audio between live passes
    max_window: float = 15.0  # slide the window once it is longer (longer windows decode more text per pass)
    tail_words: int = 4  # corrections never reach further back than this many typed words
    level_frame: int = 512  # samples per published level (32 ms)
    speech_rms: float = 0.005  # a window with no frame this loud is silence and is never recognised
    silence_pad: float = 0.5  # seconds of silence kept around speech when trimming it


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


def reconcile_live(committed: list, prev: list, cur: list, tail: int, hold: int = 0) -> list:
    """What the window's typed words become after a pass: the words after the typed text that this pass and the
    previous one agree on (never the newest pass's last word, nor its last `hold` words), with a tail correction only
    when both passes agree on it and on at least one replacement word."""
    keep, resume, _ = _plan(committed, cur, tail, exact=False)
    keep_prev, resume_prev, _ = _plan(committed, prev, tail, exact=False)
    if keep != keep_prev:
        return committed
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
        self.window_start = 0  # in samples
        self.last_pass_end = None  # samples recognised by the previous live pass
        self.prev: list | None = None  # previous pass words (window-relative)
        self.typed = ""  # everything typed this session
        self.frozen = 0  # typed words that lie before the window
        self.frozen_preview: list = []  # translate mode: preview words that lie before the window
        self.aborted = False
        self.text_language = "en" if mode.translate else mode.language  # the cleanup's rules
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

    def begin(self, mode: str) -> None:
        if mode not in MODES:
            raise ValueError(f"unknown mode {mode!r}, want one of {', '.join(MODES)}")
        if self._s is not None:
            raise RuntimeError("a session is already running")
        s = _Session(MODES[mode], self.focus())
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
        for rms in levels:
            s.levels.append(rms)
            value = 0.0 if rms <= 1e-6 else min(1.0, max(0.0, (20 * math.log10(rms) + 60) / 60))
            self.emit({"event": "level", "value": round(value, 3)})

    def step(self) -> bool:
        """Run one live pass if it is due. Returns whether a pass ran."""
        s = self._s
        if s is None or s.aborted:
            return False
        cfg = self.config
        with self._lock:
            total = len(s.pcm) // _BPS
        if total < cfg.min_pass_audio * SAMPLE_RATE:
            return False
        previous = s.last_pass_end
        if previous is not None and total - previous < cfg.pass_every * SAMPLE_RATE:
            return False
        s.last_pass_end = total
        # nothing new was said (a pause with the key held): the same audio would only invite hallucinations
        frame = cfg.level_frame
        if not self._has_speech(s, s.window_start if previous is None else -(-previous // frame) * frame, total):
            return False
        end = self._speech_end(s, total)
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
        if s.prev is not None:
            target = reconcile_live(words[s.frozen :], s.prev, cur, cfg.tail_words, hold)
            self._type(s, _join(words[: s.frozen] + target))
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
            if total == 0 or not self._has_speech(s, 0, total):
                return s.typed
            start, end = self._speech_start(s), self._speech_end(s, total)
            with self._lock:
                audio = bytes(s.pcm[start * _BPS : end * _BPS])
            result = self._transcribe(s, audio, FINAL)
            if self._s is not s:
                return s.typed  # cancelled meanwhile
            self.emit({"event": "pass", "slot": FINAL, "ms": round(result.ms), "audio": round((end - start) / SAMPLE_RATE, 2)})
            final = [w for _, ws in self._segment_words(s, result.segments)[0] for w in ws]
            if s.mode.translate:
                self.emit({"event": "preview", "text": _join(final)})
            target = reconcile_final(s.typed.split(), final, self.config.tail_words)
            self._type(s, _join(target))
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

    def _has_speech(self, s: _Session, start: int, end: int) -> bool:
        frame = self.config.level_frame
        return any(rms >= self.config.speech_rms for rms in s.levels[start // frame : -(-end // frame)])

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
        extra = {"prompt": s.prompt} if s.prompt else {}  # recognizers without hint support never see the keyword
        return self.recognizer.transcribe(audio, slot=slot, language=s.mode.language, translate=s.mode.translate,
                                          **extra)

    def _segment_words(self, s: _Session, segments) -> tuple:
        """([(segment, words)], hold) after the cleanup stage, which sees the whole pass (phrases may span
        segments)."""
        raw = [_sanitize(_ANNOTATION.sub(" ", unicodedata.normalize("NFC", seg.text))).split() for seg in segments]
        cleaned, hold = self.cleanup.apply(raw, s.text_language)
        return [(seg, _sanitize(" ".join(ws)).split()) for seg, ws in zip(segments, cleaned)], hold

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
