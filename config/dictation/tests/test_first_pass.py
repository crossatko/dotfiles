"""When the first preview pass runs. Fake audio: a quiet bed (the noise floor) and a loud tone (voiced speech); the
scripted recognizer does not listen to it."""
import unittest

from helpers import Recorder, Scripted, tone

from dictation.engine import Config, Dictation

BED, VOICE = 0.001, 0.1  # -60 dB room noise, -20 dB speech


def play(d, seconds, value, step=0.1):
    """Audio in 0.1 s chunks with a controller step after each, like the service."""
    for _ in range(round(seconds / step)):
        d.feed(tone(step, value))
        d.step()


class FirstPass(unittest.TestCase):
    def test_the_first_pass_counts_from_the_speech_and_skips_the_leading_silence(self):
        r = Scripted(["Hello there"])
        d = Dictation(r, Recorder(), config=Config(trailing_space=False, min_pass_audio=1.5))
        d.begin("en")
        play(d, 1.0, BED)
        play(d, 1.4, VOICE)
        self.assertEqual(r.calls, [])
        play(d, 0.1, VOICE)
        self.assertEqual(len(r.calls), 1)
        self.assertAlmostEqual(r.calls[0][3], 1.5 + 0.5, delta=0.04, msg="the speech plus a 0.5 s lead")


if __name__ == "__main__":
    unittest.main()
