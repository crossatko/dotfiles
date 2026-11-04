"""The noise-floor-aware level (level.py): silence is 0 whatever the noise level, speech spikes whatever the gain."""
import math
import random
import unittest

import helpers  # noqa: F401  (puts lib/ on the path)

from dictation.level import LevelMeter


def frames(meter, rms_values):
    return [meter.push(r) for r in rms_values]


def noisy(level, n, rnd, spread_db=2.0):
    """Frame RMS values of stationary noise around `level` (a couple of dB of frame-to-frame spread)."""
    return [level * 10 ** (rnd.uniform(-spread_db, spread_db) / 20) for _ in range(n)]


def syllables(level, n, rnd):
    """Speech-like frame RMS: 150-250 ms syllables up to `level`, with short dips between them."""
    out = []
    while len(out) < n:
        peak = level * 10 ** (rnd.uniform(-6, 0) / 20)
        size = rnd.randint(5, 8)
        out += [peak * math.sin(math.pi * (i + 0.5) / size) for i in range(size)]
    return out[:n]


class Levels(unittest.TestCase):
    def test_silence_is_exactly_zero_at_any_noise_level(self):
        for noise in (1e-4, 1e-3, 0.01, 0.05):
            rnd = random.Random(1)
            m = LevelMeter()
            values = [v for v, _ in frames(m, noisy(noise, 200, rnd))]
            self.assertEqual(values[30:], [0.0] * 170, noise)

    def test_speech_spikes_above_the_floor_independent_of_the_gain(self):
        peaks = []
        for gain in (0.05, 0.3, 1.0):
            rnd = random.Random(2)
            m = LevelMeter()
            frames(m, noisy(0.001 * gain, 60, rnd))
            values = [v for v, _ in frames(m, syllables(0.1 * gain, 120, rnd))]
            peaks.append(sorted(values)[int(0.9 * len(values))])
            self.assertGreater(peaks[-1], 0.6, gain)
        self.assertLess(max(peaks) - min(peaks), 0.05, "the same speech looks the same at any mic gain")

    def test_back_to_zero_soon_after_the_speech(self):
        rnd = random.Random(3)
        m = LevelMeter()
        frames(m, noisy(0.001, 60, rnd))
        frames(m, syllables(0.1, 60, rnd))
        after = [v for v, _ in frames(m, noisy(0.001, 40, rnd))]
        self.assertEqual(after[20:], [0.0] * 20, "within ~0.6 s (the release)")

    def test_a_noise_that_starts_mid_session_is_absorbed_into_the_floor(self):
        rnd = random.Random(4)
        m = LevelMeter()
        frames(m, noisy(0.001, 60, rnd))
        values = [v for v, _ in frames(m, noisy(0.003, 400, rnd))]  # a fan, 10 dB louder
        self.assertEqual(values[-100:], [0.0] * 100)

    def test_digital_zeros_do_not_drag_the_floor_down(self):
        rnd = random.Random(5)
        m = LevelMeter()
        frames(m, noisy(0.002, 60, rnd))
        frames(m, [0.0] * 100)  # a muted source / the end of a file
        values = [v for v, _ in frames(m, noisy(0.002, 60, rnd))]
        self.assertEqual(values, [0.0] * 60)

    def test_fluent_speech_stays_voiced_the_floor_does_not_creep_up_under_it(self):
        # -32 dB speech in a -50 dB room, 2-frame gaps between 384 ms words, 12 s without a pause
        rnd = random.Random(7)
        m = LevelMeter()
        frames(m, noisy(0.003, 30, rnd))
        speech = []
        while len(speech) < 375:
            speech += [0.025] * 10 + list(noisy(0.003, 2, rnd))
        voiced = [v for r, (_, v) in zip(speech, frames(m, speech)) if r > 0.01]
        self.assertTrue(all(voiced), voiced.index(False) if False in voiced else None)

    def test_voiced_marks_speech_not_noise(self):
        rnd = random.Random(6)
        m = LevelMeter()
        noise = [voiced for _, voiced in frames(m, noisy(0.002, 100, rnd))]
        speech = [voiced for _, voiced in frames(m, [0.05] * 10)]
        self.assertFalse(any(noise))
        self.assertTrue(all(speech))


if __name__ == "__main__":
    unittest.main()
