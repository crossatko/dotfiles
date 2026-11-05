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
    # trailing_space off: these tests are about the text; the space after it has its own tests (TrailingSpace)
    d = Dictation(recognizer, rec, emit=events.append, config=config or Config(trailing_space=False), **kwargs)
    return d, rec, events


def speak(d, passes, chunk=tone):
    """3 s of audio (the first pass), then 0.5 s per further pass, stepping after each chunk."""
    d.feed(chunk(3.0))
    d.step()
    for _ in range(passes - 1):
        d.feed(chunk(0.5))
        d.step()


class TypeOnRelease(unittest.TestCase):
    """The only mode: the fast model feeds the preview while the key is held, the full model's text is typed once."""

    def test_nothing_is_typed_while_the_key_is_held_but_the_preview_flows(self):
        r = Scripted(["Udělal jsem", "Udělal jsem commit", "Udělal jsem commit a pak"], final="x")
        d, rec, events = make(r)
        d.begin("cs")
        speak(d, 3)
        self.assertEqual(rec.ops, [])
        self.assertEqual([e["text"] for e in events if e["event"] == "preview"],
                         ["Udělal jsem", "Udělal jsem commit", "Udělal jsem commit a pak"])
        self.assertFalse([e for e in events if e["event"] == "edit"])

    def test_the_full_models_text_is_typed_once_on_release(self):
        r = Scripted(["Udělal jsem", "Udělal jsem commit"], final="Udělal jsem commit a pak otevřel pull request.")
        d, rec, events = make(r)
        d.begin("cs")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.ops, [(0, "Udělal jsem commit a pak otevřel pull request.")])
        self.assertEqual([e for e in events if e["event"] == "edit"],
                         [{"event": "edit", "backspace": 0, "text": "Udělal jsem commit a pak otevřel pull request."}])
        self.assertEqual([e["text"] for e in events if e["event"] == "final"], ["Udělal jsem commit a pak otevřel pull request."])

    def test_a_wrong_fast_model_does_not_matter_the_full_text_is_typed_in_full(self):
        # the failure that ended live typing: "Gidribis" was typed long before the final pass read "git rebase"
        r = Scripted(["Run Gidribis on", "Run Gidribis on Origin Main, then"],
                     final="Run git rebase on origin main, then force push the branch with lease.")
        d, rec, _ = make(r)
        d.begin("en")
        speak(d, 2)
        self.assertEqual(rec.ops, [])
        d.end()
        self.assertEqual(rec.ops, [(0, "Run git rebase on origin main, then force push the branch with lease.")])

    def test_no_pass_before_min_pass_audio_of_speech(self):
        r = Scripted(["garbage"], final="Ahoj.")
        d, rec, _ = make(r)
        d.begin("cs")
        d.feed(tone(Config().min_pass_audio - 0.1))
        d.step()
        self.assertEqual(r.calls, [])
        d.end()
        self.assertEqual([c[0] for c in r.calls], ["final"])
        self.assertEqual(rec.ops, [(0, "ahoj")])  # a lone word: lower-case, no period

    def test_pinned_language_and_models(self):
        r = Scripted(["Hello world", "Hello world again"], final="Hello world again.")
        d, _, _ = make(r)
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual([c[:3] for c in r.calls], [("live", "en", False), ("live", "en", False), ("final", "en", False)])

    def test_the_final_pass_gets_the_whole_session(self):
        r = Scripted(["a b"], final="a b c.")
        d, _, _ = make(r)
        d.begin("en")
        speak(d, 3)
        d.end()
        self.assertGreater(r.calls[-1][3], 3.5)

    def test_the_cleanup_runs_over_the_preview_and_the_final_text(self):
        seen = []

        class DropEhm:
            def begin(self, language, translate):
                return ""

            def apply(self, segments, language):
                seen.append(language)
                return [[w for w in ws if w.strip(",.").lower() != "ehm"] for ws in segments], 0

        r = Scripted(["Můžeš ehm mi", "Můžeš ehm mi poslat"], final="Můžeš mi, ehm, poslat soubor?")
        d, rec, events = make(r, cleanup=DropEhm())
        d.begin("cs")
        speak(d, 2)
        self.assertEqual([e["text"] for e in events if e["event"] == "preview"], ["Můžeš mi", "Můžeš mi poslat"])
        d.end()
        self.assertEqual(rec.ops, [(0, "Můžeš mi, poslat soubor?")])
        self.assertEqual(set(seen), {"cs"})


class TrailingSpace(unittest.TestCase):
    """The default: one space after a session's final text, so the next dictation starts a new word."""

    def session(self, r, mode="en", passes=2, focus=None):
        d, rec, events = make(r, config=Config(), focus=focus)
        d.begin(mode)
        speak(d, passes)
        return d, rec, events

    def test_two_sessions_are_separated_by_one_space(self):
        rec = Recorder()
        for live, final in ((["First sentence", "First sentence here"], "First sentence here."),
                            (["Second one", "Second one too"], "Second one too.")):
            d = Dictation(Scripted(live, final=final), rec)
            d.begin("en")
            speak(d, 2)
            d.end()
        self.assertEqual(rec.screen(), "First sentence here. Second one too. ")

    def test_the_space_is_in_the_one_edit_and_the_final_event(self):
        d, rec, events = self.session(Scripted(["Spust docker compose", "Spust docker compose up"],
                                               final="Spusť docker compose up."), mode="cs")
        d.end()
        self.assertEqual(rec.ops, [(0, "Spusť docker compose up. ")])
        self.assertEqual([e["text"] for e in events if e["event"] == "final"], ["Spusť docker compose up. "])

    def test_translate_gets_the_space_after_the_english_text(self):
        r = TranslateScripted(["I made"], final="I made a commit.")
        d, rec, _ = self.session(r, mode="translate", passes=1)
        r.ending = True
        d.end()
        self.assertEqual(rec.ops, [(0, "I made a commit. ")])

    def test_no_lone_space_after_an_empty_session_a_cancel_or_a_focus_abort(self):
        d, rec, _ = make(Scripted([""], final=""), config=Config())
        d.begin("en")
        d.feed(silence(2.0))
        d.end()
        d.begin("en")
        speak(d, 2)  # the recognizer hears nothing
        d.end()
        self.assertEqual(rec.ops, [])
        d, rec, _ = self.session(Scripted(["a b c", "a b c d"], final="a b c d."))
        d.cancel()
        self.assertEqual(rec.ops, [])
        windows = iter(["0xa", "0xb"])
        d, rec, _ = self.session(Scripted(["a b c", "a b c d"], final="a b c d."), focus=lambda: next(windows, "0xb"))
        d.end()
        self.assertEqual(rec.ops, [], "focus changed: no text, no space")

    def test_the_switch_turns_it_off(self):
        d, rec, _ = make(Scripted(["a b c", "a b c d"], final="a b c d."), config=Config(trailing_space=False))
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.screen(), "a b c d.")


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
    def test_nothing_is_typed_when_the_focused_window_changed_during_the_session(self):
        windows = iter(["0xa", "0xb"])  # at begin, at release
        r = Scripted(["one two three", "one two three four"], final="one two three four five.")
        d, rec, events = make(r, focus=lambda: next(windows, "0xb"))
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual(rec.ops, [])
        self.assertEqual([e for e in events if e["event"] == "aborted"], [{"event": "aborted", "reason": "focus"}])
        self.assertFalse(d.active)

    def test_the_same_window_at_release_types(self):
        d, rec, _ = make(Scripted(["one two"], final="one two."), focus=lambda: "0xa")
        d.begin("en")
        speak(d, 1)
        d.end()
        self.assertEqual(rec.screen(), "one two.")

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
    def test_no_enter_no_tab_and_one_trailing_space_at_most(self):
        r = Scripted([" hello\nworld \r\n", "hello\nworld\tagain  \n"], final=" hello world\nagain and more.\n ")
        d, rec, _ = make(r, config=Config())
        d.begin("en")
        speak(d, 2)
        d.end()
        self.assertEqual(len(rec.ops), 1)
        self.assertNotRegex(rec.ops[0][1], r"[\n\r\t]")
        self.assertEqual(rec.screen(), "hello world again and more. ", "whitespace from whisper never doubles the space")

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


class Lifecycle(unittest.TestCase):
    def test_cancel_types_nothing(self):
        r = Scripted(["a b c", "a b c d"], final="a b c d e.")
        d, rec, events = make(r)
        d.begin("en")
        speak(d, 2)
        d.cancel()
        self.assertEqual(rec.ops, [])
        self.assertFalse(d.active)
        self.assertEqual(events[-1], {"event": "state", "state": "idle"})
        d.end()  # nothing running: no final pass, nothing typed
        self.assertEqual((rec.ops, [c[0] for c in r.calls]), ([], ["live", "live"]))

    def test_levels_are_published_between_zero_and_one(self):
        d, _, events = make(Scripted([""]))
        d.begin("cs")
        d.feed(tone(0.5, 0.001) + tone(0.5, 0.3) + tone(1.0, 0.001))  # room noise, speech, room noise
        levels = [e["value"] for e in events if e["event"] == "level"]
        self.assertGreater(len(levels), 50)
        self.assertTrue(all(0.0 <= v <= 1.0 for v in levels))
        self.assertEqual(levels[:15], [0.0] * 15, "the noise floor is silence")
        self.assertGreater(max(levels[16:31]), 0.9)
        self.assertEqual(levels[-10:], [0.0] * 10)

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
            d.begin("klingon")


class LongSessions(unittest.TestCase):
    def test_the_preview_window_slides_and_the_final_pass_reads_everything(self):
        # 20 sentences of 5 words, one word every 0.4 s: 40 s of speech, longer than one whisper window.
        words, t = [], 0.0
        for s in range(20):
            for w in range(5):
                t += 0.4
                words.append((round(t, 2), f"w{s}x{w}" + ("." if w == 4 else "")))
        tl = Timeline(words)
        d, rec, events = make(tl, config=Config(max_window=10.0, trailing_space=False))  # position-coded audio, not speech
        d.begin("en")
        d.feed(counting(0, 3.0))
        d.step()
        pos = 3.0
        while pos < t + 0.5:
            d.feed(counting(pos, 0.5))
            pos += 0.5
            d.step()
        self.assertEqual(rec.ops, [])
        expected = [w for _, w in words]
        last = [e["text"] for e in events if e["event"] == "preview"][-1].split()
        self.assertEqual(last[:-1], expected[: len(last) - 1], "the preview is the whole running text, nothing lost or repeated")
        self.assertGreater(len(last), len(expected) - 8)
        d.end()
        self.assertEqual(rec.ops, [(0, " ".join(expected))])
        self.assertTrue(all(end - start <= 10.0 + 0.5 + 1e-6 for start, end in tl.windows[:-1]))


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
