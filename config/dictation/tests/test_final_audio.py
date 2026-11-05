"""The audio the recognizer gets: the final pass hears the whole session (a soft ending below the speech gate is
never cut off), previews hear everything up to now, and a pause with the key held gets one closing preview pass."""
import array
import unittest

from helpers import SAMPLE_RATE, Recorder, Scripted, silence, tone

from dictation.engine import Config, Dictation

CFG = Config(trailing_space=False)


def make(recognizer, config=CFG):
    rec, events = Recorder(), []
    return Dictation(recognizer, rec, emit=events.append, config=config), rec, events


def play(d, pcm, step=0.1):
    size = int(step * SAMPLE_RATE) * 4
    for i in range(0, len(pcm), size):
        d.feed(pcm[i : i + size])
        d.step()


def soft(seconds, value):
    return array.array("f", [value]) * int(seconds * SAMPLE_RATE)


class FinalAudio(unittest.TestCase):
    def test_a_soft_ending_below_the_speech_gate_reaches_the_final_pass(self):
        r = Scripted(["Quiet words"], final="Quiet words and a soft ending.")
        d, rec, _ = make(r)
        d.begin("en")
        play(d, silence(0.7))
        play(d, tone(2.0, 0.02))
        play(d, soft(1.5, 0.003).tobytes())  # under the gate (0.005), over half of it
        play(d, silence(0.5))  # the release tail
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 0.2 + 2.0 + 1.5 + 0.5 + 0.0, delta=0.6, msg="speech start minus the pad, to the end")
        self.assertGreater(final[3], 4.0 - 0.1)
        self.assertEqual(rec.screen(), "Quiet words and a soft ending.")

    def test_the_final_pass_hears_the_release_tail(self):
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(2.0))
        play(d, silence(0.5))
        d.end()
        self.assertAlmostEqual([c for c in r.calls if c[0] == "final"][0][3], 2.5, delta=0.05)

    def test_a_very_long_silent_hold_is_cut_but_not_a_soft_ending(self):
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(2.0))
        play(d, soft(1.0, 0.003).tobytes())
        play(d, silence(20.0))
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 3.0 + Config().final_tail, delta=0.1)

    def test_a_lone_noise_peak_in_a_long_hold_does_not_move_the_end(self):
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(2.0))
        play(d, silence(6.0))
        play(d, soft(0.032, 0.003).tobytes())  # one frame over tail_rms
        play(d, silence(14.0))
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 2.0 + Config().final_tail, delta=0.1)

    def test_the_soft_ending_extension_is_kept_while_the_audio_fits_one_whisper_window(self):
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(20.0))
        play(d, soft(1.5, 0.003).tobytes())
        play(d, silence(10.0))
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 20.0 + 1.5 + Config().final_tail, delta=0.1, msg="one window before and after")

    def test_the_extension_is_dropped_when_the_audio_would_pass_one_whisper_window(self):
        # whisper decodes in 30 s windows: a last window of mostly non-speech makes it invent text
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(28.0))
        play(d, soft(1.5, 0.003).tobytes())
        play(d, silence(10.0))
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 28.0 + Config().silence_pad, delta=0.1, msg="what the gate-based rule sent")

    def test_the_30_s_are_counted_from_the_start_of_the_final_audio(self):
        # 40 s of leading room do not count: the audio starts 0.5 s before the speech
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, silence(40.0))
        play(d, tone(20.0))
        play(d, soft(1.5, 0.003).tobytes())
        play(d, silence(10.0))
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 0.5 + 20.0 + 1.5 + Config().final_tail, delta=0.1)

    def test_a_steady_room_above_the_soft_ending_level_does_not_stretch_the_final_audio(self):
        # a fan (0.003: over tail_rms, under the gate) after the speech: the soft ending never "ends", the hard cap does
        r = Scripted(["Hi there"], final="Hi there.")
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(2.0))
        play(d, soft(60.0, 0.003).tobytes())
        d.end()
        final = [c for c in r.calls if c[0] == "final"][0]
        self.assertAlmostEqual(final[3], 2.0 + Config().final_hard_cap, delta=0.1)

    def test_noise_under_the_gate_still_types_nothing(self):
        r = Scripted(["Thank you."], final="Thank you.")
        d, rec, _ = make(r)
        d.begin("en")
        play(d, soft(4.0, 0.003).tobytes())
        d.end()
        self.assertEqual((rec.ops, r.calls), ([], []))


class Previews(unittest.TestCase):
    def test_previews_hear_everything_up_to_now(self):
        r = Scripted(["one two"])
        d, _, _ = make(r)
        d.begin("en")
        play(d, tone(1.5))
        play(d, soft(0.3, 0.003).tobytes())  # a soft word after the loud part
        live = [c for c in r.calls if c[0] == "live"]
        self.assertGreaterEqual(live[-1][3], 1.5)

    def test_a_pause_with_the_key_held_runs_one_closing_pass_that_hears_the_last_words(self):
        class Growing(Scripted):
            def transcribe(self, audio, *, slot, language, translate):
                seconds = len(audio) / 4 / SAMPLE_RATE
                self.live = ["one two three"] if seconds < 3.2 else ["one two three four five"]
                return super().transcribe(audio, slot=slot, language=language, translate=translate)

        r = Growing([])
        d, _, events = make(r, Config(trailing_space=False, pass_every=0.5))
        d.begin("en")
        play(d, tone(2.9))
        before = len([c for c in r.calls if c[0] == "live"])
        play(d, silence(1.5))
        after = len([c for c in r.calls if c[0] == "live"])
        previews = [e["text"] for e in events if e["event"] == "preview"]
        self.assertIn(after - before, (1, 2), "at most the last scheduled pass and one closing pass in the pause")
        self.assertEqual(previews[-1], "one two three four five")

    def test_translate_mode_gets_the_closing_preview_too(self):
        from helpers import TranslateScripted

        class Growing(TranslateScripted):
            def transcribe(self, audio, *, slot, language, translate):
                self.live = ["one two"] if len(audio) / 4 / SAMPLE_RATE < 3.2 else ["one two three"]
                return super().transcribe(audio, slot=slot, language=language, translate=translate)

        r = Growing([])
        d, _, events = make(r, Config(trailing_space=False, pass_every=0.5))
        d.begin("translate:cs")
        play(d, tone(2.9))
        play(d, silence(1.5))
        previews = [e["text"] for e in events if e["event"] == "preview"]
        self.assertEqual(previews[-1], "one two three")


if __name__ == "__main__":
    unittest.main()
