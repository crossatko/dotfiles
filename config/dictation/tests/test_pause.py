"""End of speech: a pause after a pass that heard the speech end types the words still waiting (the last word, a
phrase start the cleanup held back), without another pass or the release. Fake audio: a quiet bed (the noise
floor) and a loud tone (voiced speech); the scripted recognizer does not listen to it."""
import unittest

from helpers import Recorder, Scripted, TranslateScripted, tone

from dictation.engine import Config, Dictation

BED, VOICE = 0.001, 0.1  # -60 dB room noise, -20 dB speech
CFG = Config(min_pass_audio=1.5, pass_every=0.5, pause_silence=1.0, trailing_space=False)


def make(recognizer, *, config=CFG, **kwargs):
    rec, events = Recorder(), []
    d = Dictation(recognizer, rec, emit=events.append, config=config, **kwargs)
    return d, rec, events


def play(d, seconds, value, step=0.1):
    """Audio in 0.1 s chunks with a controller step after each, like the service."""
    for _ in range(round(seconds / step)):
        d.feed(tone(step, value))
        d.step()


def talk(d, seconds):
    play(d, seconds, VOICE)


def pause(d, seconds, value=BED):
    play(d, seconds, value)


def live_calls(r):
    return [c for c in r.calls if c[0] == "live"]


class PauseFlush(unittest.TestCase):
    def test_a_pause_types_the_last_word_without_another_pass_or_the_release(self):
        r = Scripted(["Hello there", "Hello there friend", "Hello there friend."], final="Hello there, friend.")
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5)
        talk(d, 2.0)
        self.assertEqual(rec.screen(), "Hello there")
        pause(d, 0.9)
        self.assertEqual(rec.screen(), "Hello there", "not before pause_silence")
        self.assertEqual(len(live_calls(r)), 3, "the closing pass ran at the start of the pause")
        pause(d, 0.2)
        self.assertEqual(rec.screen(), "Hello there friend", "its period waits for what follows")
        self.assertEqual(len(live_calls(r)), 3, "the flush needs no further pass")
        d.end()
        self.assertEqual(rec.screen(), "Hello there, friend.", "the final pass still fixes the tail")

    def test_the_closing_pass_runs_promptly_once_the_speech_stops(self):
        r = Scripted(["one two", "one two three", "one two three four"])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 1.9)  # a pass at 1.5 s of speech
        pause(d, 0.1)  # the next one 0.1 s after the speech end: it has not heard the end of the last word
        self.assertEqual(len(live_calls(r)), 2)
        pause(d, 0.3)  # no new speech: no scheduled pass
        self.assertEqual(len(live_calls(r)), 2)
        pause(d, 0.2)  # 0.5-0.6 s of silence: the closing pass
        self.assertEqual(len(live_calls(r)), 3)
        self.assertLess(r.calls[-1][3], 0.5 + 1.9 + 0.5 + 0.04, "speech plus the pad, no long silence")
        pause(d, 2.0)
        self.assertEqual(len(live_calls(r)), 3, "one closing pass per pause")
        self.assertEqual(rec.screen(), "one two three four")

    def test_continuous_speech_never_types_the_last_word(self):
        r = Scripted(["a b c", "a b c d", "a b c d e", "a b c d e f", "a b c d e f g"])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 4.0)
        self.assertFalse(rec.screen().endswith(" g"))
        self.assertNotIn("g", rec.screen().split())

    def test_a_short_pause_types_nothing_and_speech_resuming_erases_nothing(self):
        r = Scripted(["I need", "I need to", "I need to", "I need to restart", "I need to restart the",
                      "I need to restart the docker", "I need to restart the docker container"])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        typed = rec.screen()
        pause(d, 0.8)  # a breath between words: below pause_silence
        self.assertEqual(rec.screen(), typed)
        talk(d, 1.5)
        pause(d, 1.2)  # a thinking pause mid-sentence: flushed, then the sentence goes on
        flushed = rec.screen()
        self.assertTrue(flushed.endswith("docker") or flushed.endswith("container"), flushed)
        talk(d, 1.5)
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops), rec.ops)

    def test_the_floor_is_relative_noise_above_the_speech_gate_still_counts_as_a_pause(self):
        # a noisy room: the bed is louder than the absolute speech gate, speech 20 dB above it
        r = Scripted(["Turn it", "Turn it off", "Turn it off."])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5, 0.02)
        play(d, 2.0, 0.2)
        pause(d, 1.2, 0.02)
        self.assertEqual(rec.screen(), "Turn it off")

    def test_passes_in_a_noisy_pause_hear_only_the_speech_and_a_short_pad(self):
        # the room noise is above the absolute gate, so passes keep running in the pause; whisper would invent a
        # word in a long stretch of noise
        class Inventive(Scripted):
            def transcribe(self, audio, *, slot, language, translate):
                result = super().transcribe(audio, slot=slot, language=language, translate=translate)
                seconds = len(audio) / 4 / 16000
                if slot == "live" and seconds > 0.5 + 2.0 + 0.5 + 0.1:  # lead + speech + pad
                    return result._replace(segments=[result.segments[0]._replace(text="Turn it off. You")])
                return result

        r = Inventive(["Turn it", "Turn it off", "Turn it off."])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5, 0.02)
        play(d, 2.0, 0.2)
        pause(d, 3.0, 0.02)
        self.assertGreater(len(live_calls(r)), 5, "passes ran in the pause")
        self.assertTrue(all(c[3] <= 0.5 + 2.0 + 0.5 + 0.04 for c in live_calls(r)), r.calls)
        self.assertEqual(rec.screen(), "Turn it off")

    def test_soft_speech_going_on_in_a_noisy_room_does_not_arm_the_flush(self):
        # room noise above the absolute gate; the speaker goes on softly (a few dB above the noise): not a pause
        r = Scripted(["the quick", "the quick brown", "the quick brown fo"])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5, 0.0056)
        play(d, 2.5, 0.1)
        play(d, 2.5, 0.009)
        self.assertEqual(rec.screen(), "the quick brown", "no fragment of a word cut off by the trimmed window")

    def test_breath_noise_between_words_holds_the_flush_back(self):
        # breathing 20 dB above the floor is voiced: no flush while it goes on
        r = Scripted(["Turn it", "Turn it off", "Turn it off."])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5)
        talk(d, 2.0)
        for _ in range(3):
            pause(d, 0.6)
            pause(d, 0.2, 0.01)
        self.assertEqual(rec.screen(), "Turn it")
        pause(d, 1.1)
        self.assertEqual(rec.screen(), "Turn it off")


class PausePunctuation(unittest.TestCase):
    def run_pause(self, after):
        r = Scripted(["It is too", "It is too hot", "It is too hot."] + after)
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        pause(d, 1.2)
        self.assertEqual(rec.screen(), "It is too hot")
        talk(d, 1.5)
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops), rec.ops)
        return rec.screen()

    def test_a_comma_both_passes_agree_on_is_added_without_a_backspace(self):
        screen = self.run_pause(["It is too hot, which", "It is too hot, which can", "It is too hot, which can"])
        self.assertEqual(screen, "It is too hot, which")

    def test_no_punctuation_when_the_sentence_goes_on_without_it(self):
        screen = self.run_pause(["It is too hot which", "It is too hot which can", "It is too hot which can"])
        self.assertEqual(screen, "It is too hot which")

    def test_a_sentence_end_gets_its_period_with_the_next_sentence(self):
        screen = self.run_pause(["It is too hot. Open", "It is too hot. Open the", "It is too hot. Open the"])
        self.assertEqual(screen, "It is too hot. Open")

    def test_passes_that_disagree_on_it_leave_the_word_bare(self):
        screen = self.run_pause(["It is too hot. Which", "It is too hot, which can", "It is too hot, which can"])
        self.assertEqual(screen, "It is too hot which")

    def test_the_final_pass_adds_it_when_the_session_ends_in_the_pause(self):
        r = Scripted(["It is too", "It is too hot", "It is too hot."], final="It is too hot.")
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        pause(d, 1.2)
        d.end()
        self.assertEqual(rec.ops[-1], (0, "."))


class PauseAndCleanup(unittest.TestCase):
    def test_a_held_phrase_start_is_released_at_a_pause(self):
        class HoldPull:
            """A replacement table with "pull request": a trailing "pull" may still grow (hold 1)."""

            def begin(self, language, translate):
                return ""

            def apply(self, segments, language):
                words = [w for ws in segments for w in ws]
                return segments, 1 if words and words[-1].lower().strip(".,") == "pull" else 0

        r = Scripted(["Open the", "Open the pull", "Open the pull", "Open the pull"], final="Open the pull.")
        d, rec, _ = make(r, cleanup=HoldPull())
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.5)
        self.assertEqual(rec.screen(), "Open the")
        pause(d, 1.2)
        self.assertEqual(rec.screen(), "Open the pull", "the phrase cannot grow in a pause")
        d.end()
        self.assertEqual(rec.screen(), "Open the pull.")

    def test_a_held_word_waits_while_the_speech_goes_on(self):
        class HoldPull:
            def begin(self, language, translate):
                return ""

            def apply(self, segments, language):
                words = [w for ws in segments for w in ws]
                return segments, 1 if words and words[-1].lower() == "pull" else 0

        r = Scripted(["Open the", "Open the pull", "Open the pull", "Open the pull"])
        d, rec, _ = make(r, cleanup=HoldPull())
        d.begin("en")
        pause(d, 0.3)
        talk(d, 3.5)
        self.assertEqual(rec.screen(), "Open the")


class PauseGuards(unittest.TestCase):
    def test_translate_types_nothing_in_a_pause_and_runs_no_closing_pass(self):
        r = TranslateScripted(["I made", "I made a commit"], final="I made a commit.")
        d, rec, _ = make(r)
        d.begin("translate")
        pause(d, 0.3)
        talk(d, 2.0)
        calls = len(r.calls)
        pause(d, 1.5)
        self.assertEqual(rec.ops, [])
        self.assertEqual(len(r.calls), calls)
        r.ending = True
        d.end()
        self.assertEqual(rec.ops, [(0, "I made a commit.")])

    def test_a_focus_change_before_the_pause_types_nothing(self):
        focus = ["0xa"]
        r = Scripted(["Hello there", "Hello there friend", "Hello there friend"])
        d, rec, events = make(r, focus=lambda: focus[0])
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        self.assertEqual(rec.screen(), "Hello there")
        focus[0] = "0xb"
        pause(d, 1.5)
        self.assertEqual(rec.screen(), "Hello there")
        self.assertIn({"event": "aborted", "reason": "focus"}, events)

    def test_cancel_in_a_pause_types_nothing_more(self):
        r = Scripted(["Hello there", "Hello there friend", "Hello there friend"])
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        pause(d, 0.7)
        d.cancel()
        pause(d, 1.0)
        self.assertEqual(rec.screen(), "Hello there")

    def test_pause_silence_zero_turns_the_flush_off(self):
        r = Scripted(["Hello there", "Hello there friend", "Hello there friend"])
        d, rec, _ = make(r, config=Config(min_pass_audio=1.5, pause_silence=0, trailing_space=False))
        d.begin("en")
        pause(d, 0.3)
        talk(d, 2.0)
        pause(d, 2.0)
        self.assertEqual(rec.screen(), "Hello there")
        self.assertEqual(len(live_calls(r)), 2)

    def test_a_single_pass_is_never_flushed(self):
        # one short utterance heard by one pass only: two passes must still agree, the release types it
        r = Scripted(["Yes."], final="Yes.")
        d, rec, _ = make(r)
        d.begin("en")
        pause(d, 0.5)
        talk(d, 0.4)
        pause(d, 1.5)
        self.assertEqual(rec.ops, [])
        d.end()
        self.assertEqual(rec.screen(), "Yes.")


class FirstPass(unittest.TestCase):
    def test_the_first_pass_counts_from_the_speech_and_skips_the_leading_silence(self):
        r = Scripted(["Hello there"])
        d, _, _ = make(r)
        d.begin("en")
        pause(d, 1.0)
        talk(d, 1.4)
        self.assertEqual(r.calls, [])
        talk(d, 0.1)
        self.assertEqual(len(r.calls), 1)
        self.assertAlmostEqual(r.calls[0][3], 1.5 + 0.5, delta=0.04, msg="the speech plus a 0.5 s lead")


if __name__ == "__main__":
    unittest.main()
