"""End to end through the real whisper.cpp worker: recorded speech in, edit operations out (recorder injector).

Needs local, never committed fixtures: DICTATION_TEST_FIXTURES=DIR with NAME.wav files (16 kHz mono) and a NAME.txt
next to each holding "MODE<TAB>expected text" (MODE = cs, en or translate). Plus the built worker and the models
(DICTATION_WORKER, DICTATION_MODEL_DIR, see bin/dictation). Skips when any of them is missing.
"""
import array
import glob
import os
import unicodedata
import unittest
import wave

import helpers  # noqa: F401

from dictation import whisper
from dictation.engine import SAMPLE_RATE, Config, Dictation
from helpers import Recorder

FIXTURES = os.environ.get("DICTATION_TEST_FIXTURES", "")


def _words(text):
    text = "".join(c for c in unicodedata.normalize("NFKD", text.casefold()) if not unicodedata.combining(c))
    return "".join(c if c.isalnum() else " " for c in text).split()


def wer(ref, hyp):
    r, h = _words(ref), _words(hyp)
    d = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hw in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rw != hw))
    return d[len(h)] / max(1, len(r))


def load(path):
    with wave.open(path) as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (SAMPLE_RATE, 1, 2), path
        pcm = array.array("h")
        pcm.frombytes(w.readframes(w.getnframes()))
    return array.array("f", (x / 32768 for x in pcm)).tobytes()


@unittest.skipUnless(FIXTURES and glob.glob(os.path.join(FIXTURES, "*.wav")),
                     "set DICTATION_TEST_FIXTURES to a dir of local WAV fixtures to run the whisper.cpp end-to-end test")
class RealWhisper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        models = {"live": whisper.model_path(whisper.DEFAULT_LIVE), "final": whisper.model_path(whisper.DEFAULT_FINAL)}
        try:
            cls.recognizer = whisper.WhisperRecognizer(models)
        except (whisper.ModelMissing, whisper.WorkerFailed) as exc:
            raise unittest.SkipTest(str(exc))

    @classmethod
    def tearDownClass(cls):
        cls.recognizer.close()

    def test_fixtures(self):
        for wav in sorted(glob.glob(os.path.join(FIXTURES, "*.wav"))):
            side = wav[:-4] + ".txt"
            if not os.path.exists(side):
                continue
            with open(side, encoding="utf-8") as f:
                mode, expected = f.read().strip().split("\t", 1)
            with self.subTest(os.path.basename(wav), mode=mode):
                rec, events = Recorder(), []
                d = Dictation(self.recognizer, rec, emit=events.append, config=Config())
                d.begin(mode)
                audio, chunk = load(wav), int(0.1 * SAMPLE_RATE) * 4
                for i in range(0, len(audio), chunk):
                    d.feed(audio[i : i + chunk])
                    d.step()
                    if mode == "translate":
                        self.assertEqual(rec.ops, [], "translate types nothing before release")
                d.end()
                screen = rec.screen()
                for _, text in rec.ops:
                    self.assertNotRegex(text, r"[\n\r\t]")
                self.assertEqual(screen, screen.strip())
                self.assertLess(wer(expected, screen), 0.35, f"{screen!r} vs {expected!r}")
                if mode == "translate":
                    self.assertEqual(len(rec.ops), 1)


if __name__ == "__main__":
    unittest.main()
