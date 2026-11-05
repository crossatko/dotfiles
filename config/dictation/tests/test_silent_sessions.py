"""A session without speech types nothing: silence, room noise, breath, a key tap, hallucinated junk ('.', 'Thank you.').

Generated audio only, plus (when present) a local recorded clip: DICTATION_TEST_CLIP=FILE.wav (16 kHz mono), never
committed. python3 -I -m unittest discover -s config/dictation/tests
"""
import array
import functools
import math
import os
import random
import unittest
import wave

from helpers import Recorder, Scripted, TranslateScripted

from dictation.cleanup import is_fragment
from dictation.engine import SAMPLE_RATE, Config, Dictation

CHUNK = int(0.1 * SAMPLE_RATE)
MODES = ("cs", "en", "translate")
JUNK = (".", "...", ",", "-", "♪", "Thank you.", "Thanks for watching.", "Děkuji.", "Děkuji za pozornost.",
        "Titulky vytvořil JohnyX", "Subtitles by the Amara.org community")


def pcm(values):
    return array.array("f", values).tobytes()


@functools.lru_cache(maxsize=None)
def white(seconds, rms, seed=1):
    rnd = random.Random(seed)
    return [rnd.gauss(0, rms) for _ in range(int(seconds * SAMPLE_RATE))]


@functools.lru_cache(maxsize=None)
def pink(seconds, rms, seed=2):
    """Roughly 1/f: white noise through a few leaky integrators of different time constants."""
    rnd = random.Random(seed)
    state, out = [0.0] * 4, []
    coef = (0.5, 0.9, 0.98, 0.995)
    for _ in range(int(seconds * SAMPLE_RATE)):
        w = rnd.gauss(0, 1)
        state = [c * s + (1 - c) * w for c, s in zip(coef, state)]
        out.append(sum(s / math.sqrt(1 - c * c) * (1 - c) for c, s in zip(coef, state)))
    scale = rms / math.sqrt(sum(x * x for x in out) / len(out))
    return [x * scale for x in out]


@functools.lru_cache(maxsize=None)
def breath(seconds, rms, seed=3):
    """One breath: noise under a slow raised-cosine envelope."""
    noise = white(seconds, 1.0, seed)
    n = len(noise)
    return [noise[i] * rms * 1.5 * math.sin(math.pi * i / n) ** 2 for i in range(n)]


def click(frames=2, level=0.08):
    return [level * (-1) ** i for i in range(frames * 512)]


@functools.lru_cache(maxsize=None)
def speech(seconds, rms, syllable=0.2):
    """Speech-like: a 150 Hz harmonic tone in syllables with short dips between them."""
    n, size = int(seconds * SAMPLE_RATE), int(syllable * SAMPLE_RATE)
    out = []
    for i in range(n):
        env = math.sin(math.pi * (i % size) / size) ** 2 * 0.9 + 0.1
        t = i / SAMPLE_RATE
        out.append(rms * 2.2 * env * (math.sin(2 * math.pi * 150 * t) + 0.5 * math.sin(2 * math.pi * 450 * t)) / 1.1)
    return out


def mix(*parts):
    return [x for p in parts for x in p]


def overlay(a, b):
    n = max(len(a), len(b))
    a, b = a + [0.0] * (n - len(a)), b + [0.0] * (n - len(b))
    return [x + y for x, y in zip(a, b)]


def run(recognizer, samples, mode="en", config=None, lead_noise=0.0):
    rec, events = Recorder(), []
    d = Dictation(recognizer, rec, emit=events.append, config=config or Config())
    d.begin(mode)
    data = pcm(samples)
    for i in range(0, len(data), CHUNK * 4):
        d.feed(data[i : i + CHUNK * 4])
        d.step()
    d.end()
    return d, rec, events


def recognizer_for(mode, text):
    return TranslateScripted([text], final=text) if mode == "translate" else Scripted([text], final=text)


def final_pass_ran(r):
    return any(c[0] == "final" for c in r.calls)


class NoSpeechTypesNothing(unittest.TestCase):
    def assert_nothing(self, rec, events, d):
        self.assertEqual(rec.ops, [])
        self.assertFalse([e for e in events if e["event"] == "edit"], "no edit event: the shell must not type")
        finals = [e for e in events if e["event"] == "final"]
        self.assertEqual([f["text"] for f in finals], [""], "a normal final event with empty text")
        self.assertEqual(events[-1], {"event": "state", "state": "idle"})
        self.assertFalse(d.active)

    def test_digital_silence_in_every_mode(self):
        for mode in MODES:
            r = recognizer_for(mode, ".")
            d, rec, events = run(r, [0.0] * (3 * SAMPLE_RATE), mode)
            self.assert_nothing(rec, events, d)
            self.assertEqual(r.calls, [])

    def test_room_noise_at_several_levels_never_reaches_the_final_pass_or_the_keyboard(self):
        for kind in (white, pink):
            for rms in (0.0005, 0.002, 0.006, 0.02, 0.05):
                for mode in MODES:
                    for text in (".", "Thank you."):
                        r = recognizer_for(mode, text)
                        d, rec, events = run(r, kind(3.0, rms), mode)
                        with self.subTest(kind=kind.__name__, rms=rms, mode=mode, text=text):
                            self.assert_nothing(rec, events, d)
                            self.assertFalse(final_pass_ran(r), "clearly no speech: no final pass")

    def test_noise_that_starts_after_a_quiet_lead(self):
        for rms in (0.006, 0.02):
            r = Scripted(["."], final=".")
            d, rec, events = run(r, mix(white(0.5, 0.0003), white(2.5, rms)), "cs")
            with self.subTest(rms=rms):
                self.assert_nothing(rec, events, d)

    def test_a_key_tap_with_clicks_only(self):
        for lead in (0.0, 0.1):
            for mode in MODES:
                r = recognizer_for(mode, "Thank you.")
                d, rec, events = run(r, mix(white(lead, 0.0005), click(2), white(0.15, 0.0005)), mode)
                with self.subTest(lead=lead, mode=mode):
                    self.assert_nothing(rec, events, d)
                    self.assertFalse(final_pass_ran(r))

    def test_a_tap_shorter_than_a_third_of_a_second(self):
        r = Scripted(["."], final=".")
        d, rec, events = run(r, white(0.2, 0.0008), "en")
        self.assert_nothing(rec, events, d)

    def test_breath_with_hallucinated_junk_types_nothing(self):
        for seconds in (0.4, 0.8):
            # a breath that is loud for half a second looks like speech to the level meter: stock phrases then get
            # through (the real model rarely invents one there); text without letters never does
            for text in (JUNK if seconds < 0.5 else JUNK[:5]):
                for mode in MODES:
                    r = recognizer_for(mode, text)
                    audio = mix(white(0.5, 0.0005, 5), overlay(breath(seconds, 0.01), white(seconds, 0.0005, 6)),
                                white(0.5, 0.0005, 7))
                    d, rec, events = run(r, audio, mode)
                    with self.subTest(seconds=seconds, text=text, mode=mode):
                        self.assert_nothing(rec, events, d)

    def test_silence_with_every_hallucination_types_nothing(self):
        for text in JUNK:
            for mode in MODES:
                r = recognizer_for(mode, text)
                d, rec, events = run(r, white(3.0, 0.0006), mode)
                with self.subTest(text=text, mode=mode):
                    self.assert_nothing(rec, events, d)


class ShortRealSpeechStillTyped(unittest.TestCase):
    def utterance(self, seconds, rms=0.05, noise=0.0005):
        return mix(white(0.5, noise, 8), overlay(speech(seconds, rms), white(seconds, noise, 9)), white(0.6, noise, 10))

    def test_a_half_second_word_is_typed_in_every_mode(self):
        for mode in MODES:
            for text, typed in (("Ano.", "ano "), ("Yes", "yes ")):
                r = recognizer_for(mode, text)
                d, rec, events = run(r, self.utterance(0.5), mode)
                with self.subTest(mode=mode, text=text):
                    self.assertEqual(rec.screen(), typed)
                    self.assertEqual([e["text"] for e in events if e["event"] == "final"], [typed])

    def test_a_clearly_spoken_thank_you_is_typed(self):
        for seconds in (0.7, 1.2):
            r = Scripted(["Thank you."], final="Thank you.")
            d, rec, events = run(r, self.utterance(seconds), "en")
            self.assertEqual(rec.screen(), "Thank you. ", seconds)

    def test_a_thank_you_from_a_burst_shorter_than_the_threshold_is_dropped(self):
        r = Scripted(["Thank you."], final="Thank you.")
        d, rec, events = run(r, self.utterance(0.32), "en")
        self.assertEqual(rec.ops, [])
        self.assertTrue(final_pass_ran(r), "enough voiced audio to try: the phrase list decides")

    def test_quiet_but_real_speech(self):
        for rms in (0.012, 0.02):
            r = Scripted(["Ano."], final="Ano.")
            d, rec, events = run(r, self.utterance(0.8, rms, noise=0.0004), "cs")
            self.assertEqual(rec.screen(), "ano ", rms)

    def test_speech_in_a_noisy_room(self):
        r = Scripted(["Ano."], final="Ano.")
        d, rec, events = run(r, self.utterance(0.8, 0.08, noise=0.01), "cs")
        self.assertEqual(rec.screen(), "ano ")

    def test_speech_that_starts_at_the_key_press(self):
        r = Scripted(["Ano."], final="Ano.")
        d, rec, events = run(r, mix(speech(0.6, 0.05), white(0.6, 0.0005)), "cs")
        self.assertEqual(rec.screen(), "ano ")

    def test_an_even_word_from_the_key_press_on_is_typed(self):
        # shallow dips (a vowel-nasal word like "Ano"): the floor starts on the word itself and only the room noise
        # after it shows the word was 8 dB over it
        for room in (0.0005, 0.003):
            word = [0.07 * (0.7 + 0.3 * math.sin(math.pi * i / 2400) ** 2) * math.sin(2 * math.pi * 150 * i / SAMPLE_RATE)
                    for i in range(int(0.4 * SAMPLE_RATE))]
            r = Scripted(["Ano."], final="Ano.")
            d, rec, events = run(r, mix(overlay(word, white(0.4, room)), white(0.4, room, 4)), "cs")
            self.assertEqual(rec.screen(), "ano ", room)

    def test_a_longer_session_types_the_final_text(self):
        r = Scripted(["a b c", "a b c d"], final="a b c d.")
        d, rec, events = run(r, mix(white(0.5, 0.0005), speech(4.0, 0.05), white(0.5, 0.0005)), "en")
        self.assertEqual(rec.screen(), "a b c d. ")


class FinalTextWithoutLetters(unittest.TestCase):
    def test_punctuation_only_final_text_after_real_speech_is_nothing(self):
        for text in (".", "...", "…", ",", "-", "♪", " . ", "- -", "♪ ♪"):
            for mode in MODES:
                r = recognizer_for(mode, text)
                audio = mix(white(0.5, 0.0005), speech(2.0, 0.05), white(0.5, 0.0005))
                d, rec, events = run(r, audio, mode)
                with self.subTest(text=text, mode=mode):
                    self.assertEqual(rec.ops, [])
                    self.assertEqual([e["text"] for e in events if e["event"] == "final"], [""])

    def test_digits_count_as_text(self):
        r = Scripted(["42"], final="42.")
        d, rec, events = run(r, mix(white(0.5, 0.0005), speech(1.0, 0.05), white(0.5, 0.0005)), "en")
        self.assertEqual(rec.screen(), "42 ")  # a lone word loses its period

    def test_a_punctuation_only_final_types_nothing_whatever_the_preview_said(self):
        r = Scripted(["a b c", "a b c d"], final=".")
        d, rec, events = run(r, mix(white(0.5, 0.0005), speech(4.0, 0.05), white(0.5, 0.0005)), "en")
        self.assertEqual(rec.screen(), "")


class HallucinationList(unittest.TestCase):
    def test_phrases_only_with_little_voiced_audio(self):
        quiet = mix(white(0.5, 0.0005), overlay(speech(0.3, 0.05), white(0.3, 0.0005)), white(0.5, 0.0005))
        loud = mix(white(0.5, 0.0005), overlay(speech(1.5, 0.05), white(1.5, 0.0005)), white(0.5, 0.0005))
        for text in ("Thank you.", "thank you", "Thanks for watching!", "Děkuji.", "Dekuji za pozornost",
                     "Titulky vytvořil Jan Novák", "Subtitles by the Amara.org community"):
            r = Scripted([text], final=text)
            _, rec, _ = run(r, quiet, "cs")
            self.assertEqual(rec.ops, [], text)
            r = Scripted([text], final=text)
            _, rec, _ = run(r, loud, "cs")
            expected = text[0].lower() + text[1:] if is_fragment(text.split()) else text  # fragments start lower-case
            if len(text.split()) == 1:
                expected = expected.rstrip(".")  # a lone word has no period
            self.assertEqual(rec.screen(), expected + " ", text)

    def test_a_phrase_inside_a_real_sentence_is_never_dropped(self):
        quiet = mix(white(0.5, 0.0005), overlay(speech(0.3, 0.05), white(0.3, 0.0005)), white(0.5, 0.0005))
        r = Scripted(["Thank you all"], final="Thank you all.")
        _, rec, _ = run(r, quiet, "en")
        self.assertEqual(rec.screen(), "Thank you all. ")


class TrailingSpaceNeedsText(unittest.TestCase):
    def test_no_space_when_nothing_else_was_typed(self):
        for text in (".", "", "Thank you."):
            r = Scripted([text], final=text)
            _, rec, _ = run(r, mix(white(0.5, 0.0005), speech(0.3, 0.05), white(0.5, 0.0005)), "en")
            self.assertEqual(rec.ops, [], text)


CLIP = os.environ.get("DICTATION_TEST_CLIP", "")


@unittest.skipUnless(CLIP and os.path.exists(CLIP), "set DICTATION_TEST_CLIP to a local 16 kHz mono WAV with speech")
class RecordedClip(unittest.TestCase):
    def clip(self):
        with wave.open(CLIP) as w:
            assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (SAMPLE_RATE, 1, 2)
            raw = array.array("h")
            raw.frombytes(w.readframes(w.getnframes()))
        return [x / 32768 for x in raw]

    def loudest(self, samples, seconds):
        n = int(seconds * SAMPLE_RATE)
        best = max(range(0, max(1, len(samples) - n), 1600), key=lambda i: sum(x * x for x in samples[i : i + n]))
        return samples[best : best + n]

    def test_the_clip_whole_a_short_cut_of_it_and_quiet(self):
        samples = self.clip()
        room = lambda s: white(s, 0.0005, 11)
        for name, part, gain in (("whole", samples, 1.0), ("0.5 s", self.loudest(samples, 0.5), 1.0),
                                 ("quiet", samples, 0.15)):
            r = Scripted(["Ano."], final="Ano.")
            d, rec, _ = run(r, mix(room(0.5), [x * gain for x in part], room(0.6)), "cs")
            with self.subTest(name):
                self.assertEqual(rec.screen(), "ano ")


if __name__ == "__main__":
    unittest.main()
