"""A fragment (one word, or up to four without a sentence end) is typed without the capital whisper puts on it; a
sentence is untouched. The live passes type the capitalised words, the final edit fixes the first one."""
import json
import os
import tempfile
import unittest

from helpers import Recorder, Scripted, TranslateScripted, tone

from dictation.cleanup import Cleanup, is_fragment, lowercase_fragment
from dictation.engine import Config, Dictation
from dictation.prefs import load
from test_pause import talk, pause, CFG


def session(recognizer, mode="en", live_passes=3, config=None, cleanup=None):
    rec, events = Recorder(), []
    kwargs = {"cleanup": cleanup} if cleanup else {}
    d = Dictation(recognizer, rec, emit=events.append, config=config or Config(trailing_space=False), **kwargs)
    d.begin(mode)
    d.feed(tone(3.0))
    d.step()
    for _ in range(live_passes - 1):
        d.feed(tone(0.5))
        d.step()
    live = list(rec.ops)
    d.end()
    return rec, live, events


class Rule(unittest.TestCase):
    CASES = (
        ("Yes", "yes"), ("Ano.", "ano"), ("Yes?", "yes?"), ("Yes!", "yes!"), ("Docker", "docker"),
        ("Yes,", "yes"), ("Yes;", "yes"), ("Yes:", "yes"), ("Yes…", "yes"), ("Yes...", "yes"), ("Yes?!", "yes?!"),
        ("\"Yes.\"", "\"yes\""), ("API.", "API"), ("I.", "I"),
        ("Ano, jasně.", "Ano, jasně."), ("Docker compose up…", "Docker compose up…"),
        ("Docker compose up", "docker compose up"), ("Run the tests", "run the tests"),
        ("Run the tests.", "Run the tests."), ("Docker compose up!", "Docker compose up!"),
        ("Run the tests now please", "Run the tests now please"),  # 5 words, no period: a sentence
        ("This is a test.", "This is a test."), ("Yes. Do it", "Yes. Do it"),
        ("I think", "I think"), ("I'm here", "I'm here"), ("I", "I"), ("API call", "API call"), ("GitHub", "GitHub"),
        ("iPhone", "iPhone"), ("Python3 rocks", "Python3 rocks"), ("\"Yes\"", "\"yes\""), ("Ano, jasně", "ano, jasně"),
        ("Děkuji.", "děkuji"), ("Čau", "čau"), ("Jean-Paul", "Jean-Paul"),
    )

    def test_final_text(self):
        for text, expected in self.CASES:
            for live in (text, "garbage"):  # the live pass typed it capitalised, or nothing agreed
                with self.subTest(text=text, live=live):
                    rec, _, _ = session(Scripted([live], final=text))
                    self.assertEqual(rec.screen(), expected)

    def test_is_fragment(self):
        self.assertTrue(is_fragment(["Yes."]))
        self.assertTrue(is_fragment("a b c d".split()))
        self.assertFalse(is_fragment("a b c d e".split()))
        self.assertFalse(is_fragment("a b c.".split()))
        self.assertFalse(is_fragment([]))

    def test_every_mode_and_translate(self):
        for mode in ("cs", "en"):
            rec, _, _ = session(Scripted(["Docker compose up"], final="Docker compose up"), mode)
            self.assertEqual(rec.screen(), "docker compose up")
        r = TranslateScripted(["Docker"], final="Docker compose up")
        r.ending = True
        rec, _, _ = session(r, "translate")
        self.assertEqual(rec.screen(), "docker compose up")
        r = TranslateScripted(["Hello"], final="This is a test.")
        r.ending = True
        rec, _, _ = session(r, "translate")
        self.assertEqual(rec.screen(), "This is a test.")

    def test_flag_off_is_the_old_behaviour(self):
        for text in ("Yes", "Docker compose up", "Ano."):
            rec, _, _ = session(Scripted([text], final=text), config=Config(trailing_space=False, lowercase_fragments=False, strip_single_word_punct=False))
            self.assertEqual(rec.screen(), text)

    def test_each_flag_alone(self):
        for kw, text, expected in (({"strip_single_word_punct": False}, "Ano.", "ano."),
                                   ({"lowercase_fragments": False}, "Ano.", "Ano"),
                                   ({"lowercase_fragments": False}, "Ano compose", "Ano compose")):
            rec, _, _ = session(Scripted([text], final=text), config=Config(trailing_space=False, **kw))
            self.assertEqual(rec.screen(), expected)


class LiveThenFixed(unittest.TestCase):
    def test_the_typed_capital_is_fixed_by_the_final_edit(self):
        r = Scripted(["Docker compose up now", "Docker compose up now", "Docker compose up now"], final="Docker compose up")
        rec, live, events = session(r)
        self.assertEqual(rec.screen(), "docker compose up")
        self.assertTrue(live and live[0][1].startswith("Docker"), live)
        self.assertEqual(rec.ops[len(live):], [(len("Docker compose up"), "docker compose up")])
        self.assertEqual([e["text"] for e in events if e["event"] == "final"], ["docker compose up"])

    def test_the_trailing_space_follows_the_fixed_text(self):
        r = Scripted(["Docker compose up now"], final="Docker compose up")
        rec, _, _ = session(r, config=Config())
        self.assertEqual(rec.screen(), "docker compose up ")

    def test_a_sentence_typed_live_is_not_touched(self):
        r = Scripted(["Run the tests now please"] * 3, final="Run the tests now please.")
        rec, live, _ = session(r)
        self.assertEqual(rec.screen(), "Run the tests now please.")

    def test_more_words_typed_than_the_final_has_stay_consistent(self):
        # five words went out live, the final pass hears four: the first word is out of the tail's reach, so it keeps
        # its capital (never garbled text)
        r = Scripted(["Run the tests now please later"] * 3, final="Run the tests now")
        rec, live, _ = session(r)
        self.assertTrue(rec.screen().startswith("Run the tests now"), rec.screen())  # nothing reachable to fix: the typed capital stays

    def test_every_fragment_first_word_is_in_reach(self):
        # fragment <= tail_words words: a live pass cannot have typed more than the final has, unless it heard more
        self.assertLessEqual(__import__("dictation.cleanup", fromlist=["x"]).MAX_FRAGMENT_WORDS, Config().tail_words)


class Pauses(unittest.TestCase):
    def test_pause_flush_then_release(self):
        r = Scripted(["Docker compose up"] * 20, final="Docker compose up")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=CFG)
        d.begin("en")
        pause(d, 0.5)
        talk(d, 2.0)
        pause(d, 1.5)
        self.assertEqual(rec.screen(), "Docker compose up")  # live: capitalised, all words flushed at the pause
        d.end()
        self.assertEqual(rec.screen(), "docker compose up")

    def test_pause_then_the_speech_goes_on_into_a_sentence(self):
        r = Scripted(["Docker compose up"] * 4 + ["Docker compose up and then run the tests"] * 20,
                     final="Docker compose up and then run the tests.")
        rec, _ = Recorder(), []
        d = Dictation(r, rec, config=CFG)
        d.begin("en")
        pause(d, 0.5)
        talk(d, 2.0)
        pause(d, 1.5)
        talk(d, 3.0)
        d.end()
        self.assertEqual(rec.screen(), "Docker compose up and then run the tests.")

    def test_a_silent_session_types_nothing(self):
        r = Scripted(["Yes"], final="Yes")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=Config())
        d.begin("en")
        d.feed(tone(2.0, 0.0))
        d.step()
        d.end()
        self.assertEqual(rec.ops, [])


class Replacements(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "words.json")
        self.prefs = os.path.join(self.tmp.name, "prefs.json")

    def cleanup(self, replacements):
        with open(self.path, "w") as f:
            json.dump({"version": 1, "replacements": replacements}, f)
        return Cleanup(self.path, prefs=self.prefs)

    def run_text(self, replacements, text, live=None):
        c = self.cleanup(replacements)
        rec, _, _ = session(Scripted([live or text], final=text), cleanup=c)
        return rec.screen()

    def test_replacement_text_keeps_its_case(self):
        rep = [{"heard": "docker", "typed": "Docker"}]
        # whisper capitalised or not, the user's "Docker" wins; the rest of the fragment is plain
        self.assertEqual(self.run_text(rep, "Docker"), "Docker")
        self.assertEqual(self.run_text(rep, "docker"), "Docker")
        self.assertEqual(self.run_text(rep, "Docker compose up"), "Docker compose up")
        self.assertEqual(self.run_text(rep, "Run docker compose"), "run Docker compose")

    def test_workaround_for_proper_nouns(self):
        # whisper's "Praha" is a title-case word and loses its capital; a replacement brings it back
        self.assertEqual(self.run_text([], "Praha"), "praha")
        self.assertEqual(self.run_text([{"heard": "praha", "typed": "Praha"}], "Praha"), "Praha")
        self.assertEqual(self.run_text([{"heard": "praha", "typed": "Praha"}], "Praha je hezká"), "Praha je hezká")

    def test_lowercase_typed_form_of_a_capitalised_heard_word_is_copied_capital(self):
        # the existing rule: the typed form takes the heard word's capital ("Docker" -> "Docker", never lowered)
        self.assertEqual(self.run_text([{"heard": "docker", "typed": "docker"}], "Docker"), "Docker")

    def test_word_count_is_the_typed_one(self):
        rep = [{"heard": "pull requests", "typed": "PRs"}]
        self.assertEqual(self.run_text(rep, "Open pull requests"), "open PRs")
        long = [{"heard": "pee are", "typed": "pull request"}]
        self.assertEqual(self.run_text(long, "Open the pee are"), "open the pull request")  # 4 typed words: a fragment
        self.assertEqual(self.run_text(long, "Open the new pee are"), "Open the new pull request")  # 5: a sentence

    def test_filler_before_the_first_word(self):
        c = self.cleanup([])
        rec, _, _ = session(Scripted(["Um, docker compose"], final="Um, docker compose"), cleanup=c)
        self.assertEqual(rec.screen(), "docker compose")  # the capital the filler passed on goes too
        rec, _, _ = session(Scripted(["Um, Docker compose"], final="Um, Docker compose"), cleanup=c)
        self.assertEqual(rec.screen(), "docker compose")
        rec, _, _ = session(Scripted(["Yes, um, I know that is right."], final="Yes, um, I know that is right."), cleanup=c)
        self.assertEqual(rec.screen(), "Yes, I know that is right.")


class Unit(unittest.TestCase):
    def test_lowercase_fragment_skips_replaced_first_word(self):
        self.assertEqual(lowercase_fragment([(0, "Docker")], [True]), [(0, "Docker")])
        self.assertEqual(lowercase_fragment([(0, "Docker")], [False]), [(0, "docker")])
        self.assertEqual(lowercase_fragment([]), [])

    def test_strip_in_brackets(self):
        # (a whole-segment "(Yes.)" is an annotation the engine drops before any of this)
        self.assertEqual(lowercase_fragment([(0, "(Yes.)")]), [(0, "(yes)")])
        self.assertEqual(lowercase_fragment([(0, "(Yes?)")]), [(0, "(yes?)")])
        self.assertEqual(lowercase_fragment([(0, "Yes."), (0, "ok")]), [(0, "Yes."), (0, "ok")])  # two words: a sentence

    def test_prefs(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, 'p.json')
            self.assertTrue(load(p).strip_single_word_punct)
            with open(p, 'w') as f:
                f.write('{"strip_single_word_punct": false}')
            self.assertFalse(load(p).strip_single_word_punct)
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "p.json")
            self.assertTrue(load(p).lowercase_fragments)
            for raw, want in (('{"lowercase_fragments": false}', False), ('{"lowercase_fragments": "no"}', True),
                              ('{"lowercase_fragments": true}', True), ('{}', True)):
                with open(p, "w") as f:
                    f.write(raw)
                self.assertEqual(load(p).lowercase_fragments, want, raw)


class LonePunctuation(unittest.TestCase):
    def test_the_typed_period_and_the_trailing_space(self):
        # the pause flush types the lone word without its period (live: "Yes"); the final edit lower-cases it, keeps no period and adds exactly one space
        r = Scripted(["Yes."] * 20, final="Yes.")
        rec, events = Recorder(), []
        d = Dictation(r, rec, emit=events.append, config=Config(pause_silence=1.0, min_pass_audio=1.5, pass_every=0.5))
        d.begin("en")
        pause(d, 0.5)
        talk(d, 2.0)
        pause(d, 1.5)
        self.assertEqual(rec.screen(), "Yes")
        d.end()
        self.assertEqual(rec.screen(), "yes ")
        self.assertEqual([e["text"] for e in events if e["event"] == "final"], ["yes "])

    def test_a_period_typed_live_is_backspaced(self):
        # a custom recognizer view: the lone word typed with its period (as the pause flush of an earlier build did)
        rec = Recorder()
        d = Dictation(Scripted(["Yes."], final="Yes."), rec, config=Config())
        d.begin("en")
        d.feed(tone(3.0))
        d.step()
        d._s.typed = "Yes."
        rec.ops.append((0, "Yes."))
        d.end()
        self.assertEqual(rec.screen(), "yes ")

    def test_translate_mode(self):
        r = TranslateScripted(["Yes."], final="Yes.")
        r.ending = True
        rec, _, _ = session(r, "translate")
        self.assertEqual(rec.screen(), "yes")

    def test_replacement_targets_are_untouched(self):
        with tempfile.TemporaryDirectory() as t:
            path = os.path.join(t, "w.json")
            with open(path, "w") as f:
                json.dump({"version": 1, "replacements": [{"heard": "et cetera", "typed": "etc."},
                                                          {"heard": "ok", "typed": "OK."}]}, f)
            c = Cleanup(path, prefs=os.path.join(t, "p.json"))
            for text, expected in (("et cetera", "etc."), ("Ok", "OK.")):
                rec, _, _ = session(Scripted([text], final=text), cleanup=c)
                self.assertEqual(rec.screen(), expected)
