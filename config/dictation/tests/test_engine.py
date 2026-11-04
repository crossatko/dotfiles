"""The test seam: audio in, edit operations out, with the injector replaced by a recorder.

python3 -I -m unittest discover -s config/dictation/tests
"""
import unittest

from helpers import Recorder, Scripted, Timeline, TranslateScripted, counting, silence, tone

from dictation.engine import Config, Dictation


def make(recognizer, *, focus=None, cleanup=None, config=None):
    rec, events = Recorder(), []
    kwargs = {"focus": focus} if focus else {}
    if cleanup:
        kwargs["cleanup"] = cleanup
    d = Dictation(recognizer, rec, emit=events.append, config=config or Config(), **kwargs)
    return d, rec, events


def speak(d, passes, chunk=tone):
    """3 s of audio (the first pass), then 0.5 s per further pass, stepping after each chunk."""
    d.feed(chunk(3.0))
    d.step()
    for _ in range(passes - 1):
        d.feed(chunk(0.5))
        d.step()


class Stability(unittest.TestCase):
    def test_types_only_words_two_passes_agree_on_and_never_the_last_word(self):
        r = Scripted(["Udělal jsem", "Udělal jsem commit", "Udělal jsem commit a pak"],
                     final="Udělal jsem commit a pak otevřel pull request.")
        d, rec, _ = make(r)
        d.begin("cs")
        speak(d, 3)
        self.assertEqual(rec.ops, [(0, "Udělal jsem"), (0, " commit")])
        d.end()
        self.assertEqual(rec.ops[-1], (0, " a pak otevřel pull request."))
        self.assertEqual(rec.screen(), "Udělal jsem commit a pak otevřel pull request.")

    def test_the_last_word_waits_even_when_two_passes_agree_on_it(self):
        d, rec, _ = make(Scripted(["Hello there", "Hello there"]))
        d.begin("en")
        speak(d, 2)
        self.assertEqual(rec.ops, [(0, "Hello")])

    def test_a_single_pass_types_nothing(self):
        d, rec, _ = make(Scripted(["Hello there friend"]))
        d.begin("en")
        speak(d, 1)
        self.assertEqual(rec.ops, [])

    def test_case_and_diacritics_are_ignored_when_comparing_but_the_newest_spelling_is_typed(self):
        d, rec, _ = make(Scripted(["spust docker", "Spusť Docker compose"]))
        d.begin("cs")
        speak(d, 2)
        self.assertEqual(rec.ops, [(0, "Spusť Docker")])

    def test_no_pass_before_three_seconds_of_audio(self):
        r = Scripted(["garbage"], final="Ahoj.")
        d, rec, _ = make(r)
        d.begin("cs")
        d.feed(tone(2.5))
        d.step()
        self.assertEqual(r.calls, [])
        d.end()
        self.assertEqual([c[0] for c in r.calls], ["final"])
        self.assertEqual(rec.ops, [(0, "Ahoj.")])

    def test_pinned_language_and_models(self):
        r = Scripted(["Hello world", "Hello world again"], final="Hello world again.")
        d, _, _ = make(r)
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual([c[:3] for c in r.calls], [("live", "en", False), ("live", "en", False), ("final", "en", False)])


class TailCorrections(unittest.TestCase):
    def test_a_correction_backspaces_only_the_tail(self):
        r = Scripted(["one two three four", "one two three four five",
                      "one two tree for five six", "one two tree for five six seven"])
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 4)
        self.assertEqual(rec.ops, [(0, "one two three four"), (9, "ree for five six")])
        self.assertEqual(rec.screen(), "one two tree for five six")

    def test_a_disagreement_deeper_than_the_tail_is_left_alone_and_typing_goes_on(self):
        r = Scripted(["a b c d e f g h", "a b c d e f g h i",
                      "x b c d e f g h i j", "x b c d e f g h i j k"])
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 4)
        self.assertEqual(rec.ops, [(0, "a b c d e f g h"), (0, " i"), (0, " j")])

    def test_a_reworded_window_start_does_not_stall_typing(self):
        # the first words of the window come out differently in every pass from some point on
        r = Scripted(["one two three four five", "one two three four five six",
                      "won two three four five six seven", "un two three four five six seven eight",
                      "uno two three four five six seven eight nine"])
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 5)
        self.assertEqual(rec.screen(), "one two three four five six seven eight")

    def test_a_correction_needs_both_passes_to_agree_on_it(self):
        r = Scripted(["one two three four", "one two three four five",
                      "one two tree for five six", "one two three four five six seven",
                      "one two three four five six seven eight"])
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 4)
        self.assertEqual(rec.screen(), "one two three four")
        speak(d, 1)
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops))
        self.assertEqual(rec.screen(), "one two three four five six seven")

    def test_the_final_pass_fixes_only_the_tail_and_flushes_the_rest(self):
        r = Scripted(["a b c d e f g", "a b c d e f g h"], final="A x c d e f g h i.")
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 2)
        self.assertEqual(rec.screen(), "a b c d e f g")
        d.end()
        self.assertEqual(rec.ops[-1], (0, " h i."))
        self.assertEqual(rec.screen(), "a b c d e f g h i.")

    def test_the_final_pass_fixes_diacritics_and_punctuation_in_the_tail(self):
        r = Scripted(["Spust docker compose", "Spust docker compose up"], final="Spusť docker compose up.")
        d, rec, _ = make(r)
        d.begin("cs")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.ops, [(0, "Spust docker compose"), (16, "ť docker compose up.")])

    def test_a_truncated_final_pass_never_erases_typed_words(self):
        r = Scripted(["Můžeš mi poslat ten soubor než", "Můžeš mi poslat ten soubor než odejdeš"],
                     final="Můžeš mi poslat")
        d, rec, _ = make(r)
        d.begin("cs")
        speak(d, 2)
        d.end()
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops))
        self.assertEqual(rec.screen(), "Můžeš mi poslat ten soubor než")

    def test_words_the_final_pass_drops_from_the_tail_are_erased(self):
        r = Scripted(["Ahoj tak jak se", "Ahoj tak jak se máš"], final="Ahoj, jak se máš?")
        d, rec, _ = make(r)
        d.begin("cs")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.screen(), "Ahoj, jak se máš?")
        self.assertTrue(all(bs <= len("Ahoj tak jak se") for bs, _ in rec.ops))


class Translate(unittest.TestCase):
    def test_translate_types_nothing_until_release_then_the_whole_english_text(self):
        r = TranslateScripted(["I made", "I made a commit", "I made a commit and"],
                              final="I made a commit and opened a pull request.")
        d, rec, events = make(r)
        d.begin("translate")
        speak(d, 3)
        self.assertEqual(rec.ops, [])
        previews = [e["text"] for e in events if e["event"] == "preview"]
        self.assertEqual(previews, ["I made", "I made a commit", "I made a commit and"])
        r.ending = True
        d.end()
        self.assertEqual(rec.ops, [(0, "I made a commit and opened a pull request.")])
        self.assertTrue(all(c[1:3] == ("cs", True) and c[0] == "final" for c in r.calls))


class Focus(unittest.TestCase):
    def test_typing_stops_when_the_focused_window_changes(self):
        windows = iter(["0xa", "0xa", "0xb", "0xa", "0xa", "0xa"])
        r = Scripted(["one two three", "one two three four", "one two three four five six"],
                     final="one two three four five six seven.")
        d, rec, events = make(r, focus=lambda: next(windows, "0xa"))
        d.begin("en")
        speak(d, 2)
        self.assertEqual(rec.ops, [(0, "one two three")])
        speak(d, 2)
        d.end()
        self.assertEqual(rec.ops, [(0, "one two three")])
        self.assertIn({"event": "aborted", "reason": "focus"}, events)
        self.assertEqual(sum(1 for e in events if e["event"] == "aborted"), 1)

    def test_translate_is_not_typed_into_a_different_window(self):
        windows = iter(["0xa", "0xb"])
        r = TranslateScripted(["Hello"], final="Hello.")
        d, rec, _ = make(r, focus=lambda: next(windows, "0xb"))
        d.begin("translate")
        speak(d, 1)
        r.ending = True
        d.end()
        self.assertEqual(rec.ops, [])


class NeverSends(unittest.TestCase):
    def test_no_enter_no_tab_and_no_trailing_space(self):
        r = Scripted([" hello\nworld \r\n", "hello\nworld\tagain  \n", "hello world again and \n"],
                     final=" hello world\nagain and more.\n ")
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 3)
        d.end()
        self.assertTrue(rec.ops)
        for _, text in rec.ops:
            self.assertNotRegex(text, r"[\n\r\t]")
        self.assertEqual(rec.screen(), "hello world again and more.")
        self.assertFalse(rec.screen().endswith(" "))

    def test_whole_segment_annotations_are_not_typed(self):
        r = Scripted(["[BLANK_AUDIO]", "[BLANK_AUDIO]"], final="[BLANK_AUDIO]")
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.ops, [])


class Silence(unittest.TestCase):
    def test_silence_is_never_sent_to_the_recognizer(self):
        r = Scripted(["Titulky vytvořil JohnyX"], final="Titulky vytvořil JohnyX")
        d, rec, _ = make(r)
        d.begin("cs")
        speak(d, 3, chunk=silence)
        d.end()
        self.assertEqual(r.calls, [])
        self.assertEqual(rec.ops, [])


class TrailingSilence(unittest.TestCase):
    def test_a_pause_is_not_recognised_again_and_silence_is_trimmed(self):
        r = Scripted(["Hello there", "Hello there friend"], final="Hello there friend.")
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 2)
        for _ in range(4):  # two seconds of pause with the key held
            d.feed(silence(0.5))
            d.step()
        self.assertEqual(len(r.calls), 2)
        d.end()
        self.assertLess(r.calls[-1][3], 3.5 + 0.5 + 0.04, "the final pass gets the speech plus a short pad only")


class Cleanup(unittest.TestCase):
    def test_the_cleanup_hook_runs_before_the_stability_check(self):
        seen = []

        class DropEhm:
            def begin(self, language, translate):
                return ""

            def apply(self, segments, language):
                seen.append(language)
                return [[w for w in ws if w.strip(",.").lower() != "ehm"] for ws in segments], 0

        drop_ehm = DropEhm()
        r = Scripted(["Můžeš ehm mi", "Můžeš ehm mi poslat"], final="Můžeš mi, ehm, poslat soubor?")
        d, rec, _ = make(r, cleanup=drop_ehm)
        d.begin("cs")
        speak(d, 2)
        self.assertEqual(rec.ops, [(0, "Můžeš mi")])
        d.end()
        self.assertEqual(rec.screen(), "Můžeš mi, poslat soubor?")
        self.assertEqual(set(seen), {"cs"})


class Lifecycle(unittest.TestCase):
    def test_cancel_types_nothing_more(self):
        r = Scripted(["a b c", "a b c d"], final="a b c d e.")
        d, rec, events = make(r)
        d.begin("en")
        speak(d, 2)
        d.cancel()
        self.assertEqual(rec.ops, [(0, "a b c")])
        self.assertFalse(d.active)
        self.assertEqual(events[-1], {"event": "state", "state": "idle"})

    def test_levels_are_published_between_zero_and_one(self):
        d, _, events = make(Scripted([""]))
        d.begin("cs")
        d.feed(tone(0.5, 0.3) + silence(0.5))
        levels = [e["value"] for e in events if e["event"] == "level"]
        self.assertGreater(len(levels), 20)
        self.assertTrue(all(0.0 <= v <= 1.0 for v in levels))
        self.assertGreater(levels[0], 0.5)
        self.assertEqual(levels[-1], 0.0)

    def test_sessions_are_independent(self):
        r = Scripted(["a b c", "a b c d"], final="a b c d.")
        d, rec, _ = make(r)
        for _ in range(2):
            d.begin("en")
            speak(d, 2)
            d.end()
        self.assertEqual(rec.screen(), "a b c d.a b c d.")

    def test_unknown_mode_is_rejected(self):
        d, _, _ = make(Scripted([]))
        with self.assertRaises(ValueError):
            d.begin("auto")


class LongSessions(unittest.TestCase):
    def test_the_window_slides_at_sentence_ends_without_losing_or_repeating_words(self):
        # 20 sentences of 5 words, one word every 0.4 s: 40 s of speech, longer than one whisper window.
        words, t = [], 0.0
        for s in range(20):
            for w in range(5):
                t += 0.4
                words.append((round(t, 2), f"w{s}x{w}" + ("." if w == 4 else "")))
        tl = Timeline(words)
        d, rec, _ = make(tl, config=Config(max_window=10.0))
        d.begin("en")
        d.feed(counting(0, 3.0))
        d.step()
        pos = 3.0
        while pos < t + 0.5:
            d.feed(counting(pos, 0.5))
            pos += 0.5
            d.step()
        typed_while_speaking = rec.screen()
        d.end()
        expected = " ".join(w for _, w in words)
        self.assertEqual(rec.screen(), expected)
        self.assertGreater(len(typed_while_speaking), len(expected) // 2)
        self.assertTrue(all(end - start <= 10.0 + 0.5 + 1e-6 for start, end in tl.windows[:-1]))
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops))


class ModeRace(unittest.TestCase):
    def test_mode_reads_the_session_once(self):
        class Racy(Dictation):
            """The session ends (another thread) between the check and the read."""
            reads = 0

            @property
            def _s(self):
                Racy.reads += 1
                return self._sess if Racy.reads % 2 else None

            @_s.setter
            def _s(self, value):
                self._sess = value

        d = Racy(Scripted([]), Recorder())
        d.begin("cs")
        Racy.reads = 0
        self.assertEqual(d.mode, "cs")


if __name__ == "__main__":
    unittest.main()
