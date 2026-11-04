"""Shared fakes for the dictation tests: scripted recognizers, a recording injector, synthetic audio."""
import array
import os
import sys

LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
if LIB not in sys.path:
    sys.path.insert(0, LIB)

from dictation.engine import SAMPLE_RATE, Recognition, Segment  # noqa: E402


def tone(seconds, value=0.1):
    """Loud enough to pass the speech gate; the content does not matter to the scripted recognizers."""
    return array.array("f", [value]).tobytes() * int(seconds * SAMPLE_RATE)


def silence(seconds):
    return tone(seconds, 0.0)


def counting(start_s, seconds):
    """Samples whose value is their absolute index, so a fake recognizer can tell where a window starts."""
    first = int(start_s * SAMPLE_RATE)
    return array.array("f", range(first, first + int(seconds * SAMPLE_RATE))).tobytes()


class Recorder:
    """The injector replacement: records every edit operation instead of typing it."""

    def __init__(self):
        self.ops = []

    def apply(self, backspace, text):
        self.ops.append((backspace, text))

    def screen(self):
        """What the focused field would contain after all operations."""
        out = ""
        for bs, text in self.ops:
            out = (out[:-bs] if bs else out) + text
        return out


class Scripted:
    """Returns one scripted hypothesis per live pass (the last repeats) and a fixed final text."""

    def __init__(self, live, final=""):
        self.live = list(live)
        self.final = final
        self.calls = []

    def transcribe(self, audio, *, slot, language, translate):
        self.calls.append((slot, language, translate, len(audio) / 4 / SAMPLE_RATE))
        if slot == "final":
            text = self.final
        else:
            idx = min(sum(1 for c in self.calls if c[0] == slot) - 1, len(self.live) - 1)
            text = self.live[idx] if self.live else ""
        return Recognition([Segment(0.0, len(audio) / 4 / SAMPLE_RATE, text)], 10.0)


class TranslateScripted(Scripted):
    """In translate mode the preview passes also use the final model; the test sets `ending` before end()."""

    def __init__(self, live, final=""):
        super().__init__(live, final)
        self.ending = False

    def transcribe(self, audio, *, slot, language, translate):
        self.calls.append((slot, language, translate, len(audio) / 4 / SAMPLE_RATE))
        if self.ending:
            text = self.final
        else:
            idx = min(len(self.calls) - 1, len(self.live) - 1)
            text = self.live[idx]
        return Recognition([Segment(0.0, 1.0, text)], 10.0)


class Timeline:
    """Simulated speech: words with absolute end times. A window hears every word that ended inside it; the word
    still being spoken (ending up to `lag` after the window end) comes out garbled, differently in every pass, like
    whisper's unreliable last word. Segments follow sentence ends. Window position comes from `counting` audio."""

    def __init__(self, words, lag=0.6):
        self.words = words  # [(end_s, word)]
        self.lag = lag
        self.windows = []

    def transcribe(self, audio, *, slot, language, translate):
        samples = array.array("f")
        samples.frombytes(audio)
        start = samples[0] / SAMPLE_RATE
        end = start + len(samples) / SAMPLE_RATE
        self.windows.append((round(start, 2), round(end, 2)))
        heard = []
        for t, w in self.words:
            if t <= start + 1e-6:
                continue
            if t > end + (0 if slot == "final" else self.lag):
                break
            heard.append((min(t, end) - start, w if t <= end else f"{w[:2]}#{round(end * 10)}"))
        segs, cur, t0 = [], [], 0.0
        for rt, w in heard:
            cur.append(w)
            if w.endswith("."):
                segs.append(Segment(t0, rt, " ".join(cur)))
                t0, cur = rt, []
        if cur:
            segs.append(Segment(t0, heard[-1][0], " ".join(cur)))
        return Recognition(segs, 5.0)
