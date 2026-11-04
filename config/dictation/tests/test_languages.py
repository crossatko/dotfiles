"""Selectable languages: the mode strings, the engine and the cleanup for languages beyond Czech and English."""
import json
import os
import re
import unittest

from helpers import Recorder, Scripted, TranslateScripted, tone
from test_cleanup import Words

from dictation.cleanup import Cleanup
from dictation.engine import Config, Dictation
from dictation.languages import NAMES, clean_languages, is_language, parse_mode

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def session(recognizer, mode, cleanup=None):
    rec, events = Recorder(), []
    kwargs = {"cleanup": cleanup} if cleanup else {}
    d = Dictation(recognizer, rec, emit=events.append, config=Config(trailing_space=False), **kwargs)
    d.begin(mode)
    d.feed(tone(3.0))
    d.step()
    d.feed(tone(0.5))
    d.step()
    return d, rec, events


class Modes(unittest.TestCase):
    def test_a_language_code_dictates_and_translate_code_translates(self):
        m = parse_mode("ja")
        self.assertEqual((m.language, m.translate), ("ja", False))
        m = parse_mode("translate:de")
        self.assertEqual((m.language, m.translate), ("de", True))
        m = parse_mode("translate")
        self.assertEqual((m.language, m.translate), ("cs", True), "plain translate stays Czech to English")

    def test_auto_is_a_mode_and_cleans_its_languages(self):
        m = parse_mode("auto")
        self.assertEqual((m.name, m.language, m.translate), ("auto", "auto", False))
        self.assertFalse(is_language("auto"))
        m = parse_mode("translate:auto")
        self.assertEqual((m.name, m.language, m.translate), ("translate:auto", "auto", True))
        self.assertEqual(clean_languages("cs, de,xx"), ("cs",), "a space inside a code makes it invalid")
        self.assertEqual(clean_languages("cs,de,cs"), ("cs", "de"))
        self.assertEqual(clean_languages(["ja", "ja", "x", 3]), ("ja",))
        self.assertEqual(clean_languages(None), ())

    def test_anything_else_is_refused(self):
        for bad in ("", "klingon", "xx", "CS", "translate:", "translate:xx", "translate:en", "cs-en", "translate:cs ",
                    None, 5, ["cs"], {"a": 1}):
            self.assertIsNone(parse_mode(bad), repr(bad))

    def test_the_list_has_whispers_languages(self):
        self.assertEqual(len(NAMES), 100)
        for code in ("cs", "en", "ja", "de", "yue", "haw"):
            self.assertTrue(is_language(code), code)
        self.assertTrue(all(re.fullmatch(r"[a-z]{2,3}", c) and n for c, n in NAMES.items()))

    def test_quickshell_carries_the_same_list(self):
        with open(os.path.join(ROOT, "quickshell", "launcher", "js", "DictLangs.js"), encoding="utf-8") as f:
            src = f.read()
        block = src[src.index("var LANGS"):src.index("];", src.index("var LANGS"))]
        pairs = dict(re.findall(r'\["([a-z]{2,3})", "([^"]+)"\]', block))
        self.assertEqual(pairs, NAMES)


class EngineLanguages(unittest.TestCase):
    def test_the_session_language_reaches_the_recognizer(self):
        for code in ("ja", "de"):
            r = Scripted(["Guten Tag", "Guten Tag zusammen"], final="Guten Tag zusammen.")
            d, rec, events = session(r, code)
            d.end()
            self.assertTrue(all(c[1:3] == (code, False) for c in r.calls), code)
            self.assertIn({"event": "state", "state": "listening", "mode": code}, events)
            self.assertEqual(rec.screen(), "Guten Tag zusammen.")

    def test_translate_code_recognises_that_language_and_types_english(self):
        r = TranslateScripted(["I made"], final="I made a commit.")
        d, rec, events = session(r, "translate:ja")
        r.ending = True
        d.end()
        self.assertTrue(all(c[1:3] == ("ja", True) for c in r.calls))
        self.assertEqual(rec.screen(), "I made a commit.")
        self.assertIn({"event": "state", "state": "listening", "mode": "translate:ja"}, events)

    def test_an_unknown_mode_raises(self):
        d = Dictation(Scripted([]), Recorder(), emit=lambda e: None)
        with self.assertRaises(ValueError):
            d.begin("klingon")


class Detecting(Scripted):
    """A recognizer that can detect: answers with `probs` (a list: one answer per call, the last repeats)."""

    def __init__(self, probs, live, final=""):
        super().__init__(live, final)
        self.probs = list(probs)
        self.detected = []

    def detect(self, audio, *, slot):
        self.detected.append(slot)
        return self.probs[min(len(self.detected) - 1, len(self.probs) - 1)]


class Blind(Scripted):
    """A recognizer without detection."""


class RefusingDetect(Scripted):
    """What WhisperRecognizer.detect does on a worker that did not announce detection: nothing sent, {}."""

    def detect(self, audio, *, slot):
        return {}


class Auto(unittest.TestCase):
    def run_session(self, r, languages=(), passes=3):
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=Config(trailing_space=False))
        d.begin("auto", languages)
        d.feed(tone(3.0))
        d.step()
        for _ in range(passes - 1):
            d.feed(tone(0.5))
            d.step()
        d.end()
        return rec, events

    def test_detects_once_on_the_first_pass_and_pins_the_language(self):
        r = Detecting([{"ja": 0.7, "de": 0.2}, {"de": 0.9, "ja": 0.1}], ["a b c", "a b c d", "a b c d e"], final="a b c d e.")
        rec, events = self.run_session(r)
        self.assertEqual(r.detected, ["live"], "once: later passes never ask again")
        self.assertEqual({c[1] for c in r.calls}, {"ja"}, "live and final passes use the pinned language")
        self.assertEqual([e for e in events if e["event"] == "language"],
                         [{"event": "language", "language": "ja", "detected": True}])
        self.assertEqual(rec.screen(), "a b c d e.")

    def test_the_selection_restricts_the_choice(self):
        r = Detecting([{"ja": 0.7, "de": 0.2, "cs": 0.1}], ["a b c"], final="a b c.")
        self.run_session(r, ("cs", "de"), passes=2)
        self.assertEqual({c[1] for c in r.calls}, {"de"}, "the most probable among the selected languages")

    def test_the_detection_is_logged_with_the_top_probabilities(self):
        import contextlib, io
        r = Detecting([{"en": 0.5, "ja": 0.3, "cs": 0.1, "de": 0.05, "fr": 0.05}], ["a b c"], final="a b c.")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.run_session(r, ("cs", "en", "ja"), passes=2)
        line = err.getvalue().strip()
        self.assertEqual(line.count("\n"), 0, "one line per session")
        self.assertIn("language en (detected), allowed cs,en,ja, top en 0.50, ja 0.30, cs 0.10, de 0.05", line)

    def test_no_selection_means_any_language(self):
        r = Detecting([{"ja": 0.7, "de": 0.2}], ["a b c"], final="a b c.")
        self.run_session(r, (), passes=2)
        self.assertEqual({c[1] for c in r.calls}, {"ja"})

    def test_no_detection_falls_back_to_the_first_selected_language_else_english(self):
        for cls in (Blind, RefusingDetect):
            r = cls(["a b c"], final="a b c.")
            self.run_session(r, ("de", "cs"), passes=2)
            self.assertEqual({c[1] for c in r.calls}, {"de"}, cls.__name__)
            r = cls(["a b c"], final="a b c.")
            self.run_session(r, (), passes=2)
            self.assertEqual({c[1] for c in r.calls}, {"en"}, cls.__name__)

    def test_a_probability_list_with_none_of_the_selection_falls_back(self):
        r = Detecting([{"ja": 1.0}], ["a b c"], final="a b c.")
        rec, events = self.run_session(r, ("cs", "en"), passes=2)
        self.assertEqual({c[1] for c in r.calls}, {"cs"})
        self.assertFalse([e for e in events if e["event"] == "language"][0]["detected"])

    def test_a_session_without_a_live_pass_detects_on_the_final_pass(self):
        r = Detecting([{"de": 0.8}], [], final="Hallo liebe Leute heute.")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=Config(trailing_space=False))
        d.begin("auto")
        d.feed(tone(1.0))
        d.end()
        self.assertEqual(r.detected, ["final"])
        self.assertEqual({c[1] for c in r.calls}, {"de"})
        self.assertEqual(rec.screen(), "Hallo liebe Leute heute.")

    def test_auto_to_english_detects_once_then_translates_with_english_cleanup(self):
        r = Detecting([{"ja": 0.7, "de": 0.2}], ["I made"], final="I made a commit.")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=Config(trailing_space=False))
        d.begin("translate:auto", ("de", "ja"))
        d.feed(tone(3.0))
        d.step()
        d.end()
        self.assertEqual(r.detected, ["final"], "translate runs on the final model, so the detection does too")
        self.assertEqual({c[1:3] for c in r.calls}, {("ja", True)})
        self.assertEqual(d.mode, None)
        self.assertEqual([e for e in events if e["event"] == "language"],
                         [{"event": "language", "language": "ja", "detected": True}])
        self.assertEqual(rec.screen(), "I made a commit.")

    def test_a_cancelled_session_announces_no_language(self):
        events = []

        class Cancelling(Detecting):
            def detect(self, audio, *, slot):
                d.cancel()  # the key released and cancelled while the detection ran
                return super().detect(audio, slot=slot)

        r = Cancelling([{"de": 0.8}], ["a b c"], final="a b c.")
        d = Dictation(r, Recorder(), emit=events.append, config=Config(trailing_space=False))
        d.begin("auto")
        d.feed(tone(3.0))
        d.step()
        self.assertEqual([e for e in events if e["event"] == "language"], [])

    def test_unknown_language_codes_in_the_selection_are_ignored(self):
        r = Detecting([{"de": 0.8, "ja": 0.1}], ["a b c"], final="a b c.")
        self.run_session(r, ("klingon", "ja", 5), passes=2)
        self.assertEqual({c[1] for c in r.calls}, {"ja"})


class AutoCleanup(Words):
    def test_the_detected_language_picks_the_fillers_generic_before(self):
        c = self.cleanup([("kubernetes", "K8s", "de")], fillers={"de": ["ähm"]})
        self.assertEqual(self.clean(c, "Hallo ähm kubernetes.", "")[0], "Hallo ähm kubernetes.")
        r = Detecting([{"de": 0.9}], ["Hallo ähm kubernetes"], final="Hallo ähm kubernetes.")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, cleanup=c, config=Config(trailing_space=False))
        d.begin("auto", ("de",))
        d.feed(tone(3.0))
        d.step()
        d.end()
        self.assertEqual(rec.screen(), "Hallo K8s.")


class CleanupLanguages(Words):
    def test_a_language_without_entries_keeps_the_text_and_does_not_fail(self):
        c = Cleanup(self.path)
        self.assertEqual(self.clean(c, "Hallo ähm Welt.", "de")[0], "Hallo ähm Welt.")
        self.assertEqual(self.clean(c, "um uh", "ja")[0], "um uh")
        self.assertEqual(c.begin("ja", False), "")

    def test_fillers_and_replacements_for_any_whisper_code(self):
        c = self.cleanup([("kubernetes", "K8s", "de"), ("docker", "Docker", "any"), ("foo", "bar", "ja")],
                         fillers={"de": ["ähm", "äh"]})
        self.assertEqual(self.clean(c, "Hallo ähm kubernetes.", "de")[0], "Hallo K8s.")
        self.assertEqual(self.clean(c, "docker kubernetes", "ja")[0], "Docker kubernetes")
        self.assertEqual(self.clean(c, "foo", "ja")[0], "bar")
        self.assertEqual(self.clean(c, "foo", "de")[0], "foo")

    def test_a_filler_list_for_an_unknown_code_and_a_bad_replacement_language_are_dropped(self):
        c = self.cleanup([("a b", "c", "klingon")], fillers={"xx": ["um"]})
        self.assertEqual(self.clean(c, "um a b", "xx")[0], "um a b")

    def test_the_default_czech_and_english_fillers_stay(self):
        c = Cleanup(self.path)
        self.assertEqual(self.clean(c, "Ehm, ahoj.", "cs")[0], "Ahoj.")
        self.assertEqual(self.clean(c, "um hello", "en")[0], "hello")


if __name__ == "__main__":
    unittest.main()
