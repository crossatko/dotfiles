"""Cleanup stage: filler filter, replacement list, vocabulary hints, word file loading; and through the engine seam
(scripted passes in, edit operations out)."""
import json
import os
import tempfile
import unittest

from helpers import Recorder, Scripted, TranslateScripted, tone

from dictation.cleanup import Cleanup, load_rules
from dictation.engine import Config, Dictation


class Words(unittest.TestCase):
    """A temporary word file per test."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "dictation-words.json")
        self.prefs = os.path.join(self.tmp.name, "dictation-prefs.json")
        self._env = os.environ.get("DICTATION_PREFS_FILE")
        os.environ["DICTATION_PREFS_FILE"] = self.prefs  # never the user's real prefs

    def tearDown(self):
        if self._env is None:
            del os.environ["DICTATION_PREFS_FILE"]
        else:
            os.environ["DICTATION_PREFS_FILE"] = self._env
        self.tmp.cleanup()

    def write_prefs(self, data):
        with open(self.prefs, "w", encoding="utf-8") as f:
            f.write(data if isinstance(data, str) else json.dumps(data))
        st = os.stat(self.prefs)
        os.utime(self.prefs, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))

    def write(self, data):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(data if isinstance(data, str) else json.dumps(data))
        st = os.stat(self.path)
        os.utime(self.path, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))  # a visibly newer mtime every write

    def cleanup(self, replacements=(), **extra):
        self.write({"version": 1, "replacements": [dict(zip(("heard", "typed", "lang"), r)) for r in replacements],
                    **extra})
        return Cleanup(self.path)

    def clean(self, c, text, language="en"):
        segs, hold = c.apply([text.split()], language)
        return " ".join(segs[0]), hold


class Fillers(Words):
    def test_default_fillers_go_and_real_words_stay(self):
        c = Cleanup(self.path)  # no file: built-in defaults
        self.assertEqual(self.clean(c, "I uh think um we should")[0], "I think we should")
        self.assertEqual(self.clean(c, "Ehm, no, tak jako jo.", "cs")[0], "No, tak jako jo.")
        self.assertEqual(self.clean(c, "Hmmm, eeee, to je ono.", "cs")[0], "To je ono.")
        self.assertEqual(self.clean(c, "To err is human.")[0], "To err is human.", "a doubled letter is no filler")
        self.assertEqual(self.clean(c, "Je to 5 mm.", "cs")[0], "Je to 5 mm.")

    def test_punctuation_and_capitals_after_removal(self):
        c = Cleanup(self.path)
        self.assertEqual(self.clean(c, "Well, um, I agree.")[0], "Well, I agree.")
        self.assertEqual(self.clean(c, "Um, so I agree.")[0], "So I agree.")
        self.assertEqual(self.clean(c, "Uh, um, so")[0], "So")
        self.assertEqual(self.clean(c, "I see, um. Then we go.")[0], "I see. Then we go.")
        self.assertEqual(self.clean(c, "I think, um")[0], "I think", "no comma left dangling at the end")
        self.assertEqual(self.clean(c, "Um, iPhone works.")[0], "iPhone works.")
        self.assertEqual(self.clean(c, "He said (um, well) yes")[0], "He said (well) yes")
        self.assertEqual(self.clean(c, "Um.")[0], "")
        self.assertEqual(self.clean(c, "(um) yes")[0], "yes")
        self.assertEqual(self.clean(c, "yes (well um) no")[0], "yes (well) no")
        self.assertEqual(self.clean(c, "I was, Um, thinking")[0], "I was, thinking", "no capital mid-sentence")
        self.assertEqual(self.clean(c, "Done. um, next")[0], "Done. Next")
        self.assertEqual(self.clean(c, "so um, next")[0], "so next", "the window may start mid-sentence")

    def test_diacritics_and_case_do_not_matter(self):
        c = Cleanup(self.path)
        self.assertEqual(self.clean(c, "Éé, EHM, dobře.", "cs")[0], "Dobře.")

    def test_per_language_and_editable(self):
        c = Cleanup(self.path)
        self.assertEqual(self.clean(c, "Ehm, I agree", "en")[0], "Ehm, I agree", "ehm is a Czech default only")
        c = self.cleanup(fillers={"en": ["ehm"]})
        self.assertEqual(self.clean(c, "Ehm, I um agree", "en")[0], "I um agree", "the user list replaces the default")
        self.assertEqual(self.clean(c, "Ehm, jo", "cs")[0], "Jo", "a language not in the file keeps its default")


class Replacements(Words):
    def test_single_words_copy_capitalization(self):
        c = self.cleanup([("century", "sentry", "any")])
        self.assertEqual(self.clean(c, "Send it to century.")[0], "Send it to sentry.")
        self.assertEqual(self.clean(c, "Century is up")[0], "Sentry is up")
        self.assertEqual(self.clean(c, "CENTURY is up")[0], "SENTRY is up")
        self.assertEqual(self.clean(c, '"century," he said')[0], '"sentry," he said')
        self.assertEqual(self.clean(c, "centuryfox and centuries")[0], "centuryfox and centuries", "whole words only")

    def test_mixed_case_targets_and_odd_entries(self):
        c = self.cleanup([("aws", "Amazon Web Services", "any"), ("ios", "iOS", "any"), ("c++", "cpp", "any"),
                          ("zero", "ze\u200bro\ud800", "any")], hints=True)
        self.assertEqual(self.clean(c, "AWS and Ios apps")[0], "Amazon Web Services and iOS apps")
        self.assertEqual(self.clean(c, "I write c")[0], "I write c", "a heard word with symbols is skipped")
        self.assertEqual(self.clean(c, "zero")[0], "zero", "control, format and surrogate characters are dropped")
        c.prompt("en").encode()

    def test_typed_form_keeps_its_own_case(self):
        c = self.cleanup([("github", "GitHub", "any"), ("pull requests", "PRs", "any")])
        self.assertEqual(self.clean(c, "open github and review pull requests.")[0], "open GitHub and review PRs.")
        self.assertEqual(self.clean(c, "Pull requests are open")[0], "PRs are open")

    def test_phrases_longest_wins_and_no_rematching(self):
        c = self.cleanup([("pull", "PULL-X", "any"), ("pull request", "PR", "any"), ("PR", "nope", "any"),
                          ("docker compose up", "docker compose up -d", "any")])
        self.assertEqual(self.clean(c, "a pull request and a pull")[0], "a PR and a PULL-X")
        self.assertEqual(self.clean(c, "run docker compose up now")[0], "run docker compose up -d now")
        self.assertEqual(self.clean(c, "a pull, request")[0], "a PULL-X, request", "no phrase across punctuation")

    def test_language_scoped_entries(self):
        c = self.cleanup([("komit", "commit", "cs"), ("century", "sentry", "en")])
        self.assertEqual(self.clean(c, "komit century", "cs")[0], "commit century")
        self.assertEqual(self.clean(c, "komit century", "en")[0], "komit sentry")

    def test_fillers_inside_a_phrase_do_not_break_it(self):
        c = self.cleanup([("pull request", "PR", "any")])
        self.assertEqual(self.clean(c, "a pull um request")[0], "a PR")

    def test_hold_counts_a_trailing_phrase_start(self):
        c = self.cleanup([("two factor authentication", "2FA", "any"), ("pull", "PULL-X", "any"),
                          ("pull request", "PR", "any")])
        self.assertEqual(self.clean(c, "enable two factor"), ("enable two factor", 2))
        self.assertEqual(self.clean(c, "enable two"), ("enable two", 1))
        self.assertEqual(self.clean(c, "enable two factor authentication"), ("enable 2FA", 0))
        self.assertEqual(self.clean(c, "enable two factor is"), ("enable two factor is", 0))
        self.assertEqual(self.clean(c, "enable two factor."), ("enable two factor.", 0))
        self.assertEqual(self.clean(c, "open a pull"), ("open a PULL-X", 1))

    def test_phrase_across_segments(self):
        c = self.cleanup([("pull request", "PR", "any")])
        self.assertEqual(c.apply([["a", "pull"], ["request", "now."]], "en"), ([["a", "PR"], ["now."]], 0))


class Loading(Words):
    def test_malformed_files_fall_back_to_defaults(self):
        for bad in ("", "{", "[]", "null", '{"version": 2, "fillers": {"en": []}}',
                    '{"fillers": "x", "replacements": {"a": 1}}',
                    '{"replacements": [1, {"heard": ""}, {"heard": "a", "typed": 3}, {"heard": "a", "typed": "b",'
                    ' "lang": "de"}, {"heard": "...", "typed": "b"}, {"heard": "ok", "typed": "fine"}]}'):
            self.write(bad)
            c = Cleanup(self.path)
            self.assertEqual(self.clean(c, "um ok")[0], "fine" if "fine" in bad else "ok", bad)
        rules = load_rules(os.path.join(self.tmp.name, "missing.json"))
        self.assertIn("um", rules.fillers["en"])
        self.assertEqual(rules.replacements, [])
        self.assertFalse(rules.hints)

    def test_missing_defaults_file_never_crashes(self):
        c = Cleanup(self.path, defaults=os.path.join(self.tmp.name, "nope.json"))
        self.assertEqual(self.clean(c, "um ok")[0], "um ok")

    def test_reload_when_the_file_changes(self):
        c = self.cleanup([("century", "sentry", "any")])
        c.begin("en", False)
        self.assertEqual(self.clean(c, "century")[0], "sentry")
        self.write({"replacements": [{"heard": "century", "typed": "Sentry.io"}]})
        self.assertEqual(self.clean(c, "century")[0], "sentry", "only a session start reloads")
        c.begin("en", False)
        self.assertEqual(self.clean(c, "century")[0], "Sentry.io")
        os.unlink(self.path)
        c.begin("en", False)
        self.assertEqual(self.clean(c, "century")[0], "century")

    def test_env_override(self):
        self.write({"replacements": [{"heard": "century", "typed": "sentry"}]})
        old = os.environ.get("DICTATION_WORDS_FILE")
        os.environ["DICTATION_WORDS_FILE"] = self.path
        try:
            self.assertEqual(self.clean(Cleanup(), "century")[0], "sentry")
        finally:
            if old is None:
                del os.environ["DICTATION_WORDS_FILE"]
            else:
                os.environ["DICTATION_WORDS_FILE"] = old


class Hints(Words):
    def test_prompt_only_when_on_and_only_when_transcribing(self):
        entries = [("century", "sentry", "any"), ("komit", "commit", "cs"), ("gh", "GitHub", "en")]
        self.assertEqual(self.cleanup(entries).begin("cs", False), "", "off by default")
        c = self.cleanup(entries, hints=True)
        self.assertEqual(c.begin("cs", False), "sentry, commit.")
        self.assertEqual(c.begin("en", False), "sentry, GitHub.")
        self.assertEqual(c.begin("en", True), "", "never in translate mode")

    def test_the_prefs_switch_wins_over_the_words_file_mirror(self):
        c = self.cleanup([("century", "sentry", "any")], hints=True)
        self.write_prefs({"version": 1, "prompt_hints": False})
        self.assertEqual(c.begin("en", False), "", "prefs say off")
        self.write_prefs({"version": 1, "prompt_hints": True})
        self.assertEqual(c.begin("en", False), "sentry.", "a prefs change alone reloads")
        c = self.cleanup([("century", "sentry", "any")], hints=False)
        self.assertEqual(c.begin("en", False), "sentry.")
        for bad in ('{"version": 1}', "{", '{"prompt_hints": "yes"}'):
            self.write_prefs(bad)
            self.assertEqual(c.begin("en", False), "", f"no usable switch: the mirror (off) counts: {bad}")
        c = self.cleanup([("century", "sentry", "any")], hints=True)
        self.assertEqual(c.begin("en", False), "sentry.", "no usable switch: the mirror (on) counts")

    def test_prompt_stays_short(self):
        c = self.cleanup([(f"w{i}", f"Term{i}", "any") for i in range(40)], hints=True)
        prompt = c.begin("en", False)
        self.assertLessEqual(len(prompt), 161)
        self.assertLessEqual(prompt.count(","), 11)


# --- through the engine ---------------------------------------------------------------------------------------------


class Prompted(Scripted):
    def transcribe(self, audio, *, slot, language, translate, prompt=""):
        self.prompts = getattr(self, "prompts", []) + [prompt]
        return super().transcribe(audio, slot=slot, language=language, translate=translate)


def session(recognizer, cleanup, mode, passes):
    rec, events = Recorder(), []
    d = Dictation(recognizer, rec, emit=events.append, cleanup=cleanup, config=Config(trailing_space=False))
    d.begin(mode)
    d.feed(tone(3.0))
    d.step()
    for _ in range(passes - 1):
        d.feed(tone(0.5))
        d.step()
    live_ops = list(rec.ops)
    d.end()
    return rec, live_ops, events


class Engine(Words):
    def assertNeverErased(self, rec):
        self.assertTrue(all(bs == 0 for bs, _ in rec.ops), rec.ops)

    def test_fillers_are_never_typed(self):
        r = Scripted(["Um, so I", "Um, so I think", "Um, so I think, uh, we", "Um, so I think, uh, we should go"],
                     final="Um, so I think, uh, we should go.")
        rec, live, _ = session(r, Cleanup(self.path), "en", 4)
        self.assertEqual(live, [], "nothing is typed before the release")
        self.assertEqual(rec.screen(), "So I think, we should go.")
        self.assertNeverErased(rec)

    def test_czech_fillers_and_real_words(self):
        r = Scripted(["Ehm, no", "Ehm, no, tak", "Ehm, no, tak eee jako", "Ehm, no, tak eee jako jo"],
                     final="Ehm, no, tak, eee, jako jo.")
        rec, _, _ = session(r, Cleanup(self.path), "cs", 4)
        self.assertEqual(rec.screen(), "No, tak, jako jo.")
        self.assertNotIn("hm", "".join(t for _, t in rec.ops).casefold())

    def test_phrase_is_held_back_until_it_completes(self):
        c = self.cleanup([("two factor authentication", "2FA", "any")])
        r = Scripted(["Please enable two", "Please enable two factor", "Please enable two factor authentication now",
                      "Please enable two factor authentication now please"],
                     final="Please enable two factor authentication now please.")
        rec, live, _ = session(r, c, "en", 4)
        self.assertEqual(live, [])
        self.assertNeverErased(rec)
        self.assertEqual(rec.screen(), "Please enable 2FA now please.")

    def test_held_words_are_released_when_the_phrase_fails(self):
        c = self.cleanup([("two factor authentication", "2FA", "any")])
        r = Scripted(["it has two", "it has two factor", "it has two factor issues", "it has two factor issues now"],
                     final="It has two factor issues now.")
        rec, live, _ = session(r, c, "en", 4)
        self.assertEqual((live, rec.screen()), ([], "It has two factor issues now."))

    def test_held_words_are_flushed_at_the_end(self):
        c = self.cleanup([("two factor authentication", "2FA", "any")])
        r = Scripted(["enable the two", "enable the two factor", "enable the two factor"],
                     final="Enable the two factor")
        rec, live, events = session(r, c, "en", 3)
        self.assertEqual(live, [])
        self.assertEqual(rec.screen().casefold(), "enable the two factor")
        self.assertEqual(events[-2]["event"], "final")

    def test_tail_correction_still_works_when_word_counts_change(self):
        c = self.cleanup([("pull request", "PR", "any")])
        # typed "open a pull" first (the phrase was not heard yet), later passes agree on "PR"
        r = Scripted(["open a pull it", "open a pull it now", "open a pull request now", "open a pull request now ok"],
                     final="Open a pull request now, okay.")
        rec, _, _ = session(r, c, "en", 4)
        self.assertEqual(rec.screen(), "Open a PR now, okay.")

    def test_translate_mode_uses_english_rules_and_no_prompt(self):
        c = self.cleanup([("century", "sentry", "en"), ("komit", "commit", "cs")], hints=True)
        r = TranslateScripted(["Um, check century"], final="Um, check century and komit.")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, cleanup=c, config=Config(trailing_space=False))
        d.begin("translate")
        d.feed(tone(3.0))
        d.step()
        self.assertEqual([e["text"] for e in events if e["event"] == "preview"], ["Check sentry"])
        r.ending = True
        d.end()
        self.assertEqual(rec.screen(), "Check sentry and komit.")

    def test_prompt_reaches_the_recognizer_only_in_transcribe_modes(self):
        c = self.cleanup([("century", "sentry", "any")], hints=True)
        r = Prompted(["send to century now", "send to century now ok"], final="Send to century now, ok.")
        rec, _, _ = session(r, c, "en", 2)
        self.assertEqual(set(r.prompts), {"sentry."})
        self.assertEqual(rec.screen(), "Send to sentry now, ok.")
        c = self.cleanup([("century", "sentry", "any")])  # hints off: the recognizer is called without a prompt
        r = Scripted(["send to century now", "send to century now ok"], final="Send to century now, ok.")
        rec, _, _ = session(r, c, "en", 2)
        self.assertEqual(rec.screen(), "Send to sentry now, ok.")


if __name__ == "__main__":
    unittest.main()
