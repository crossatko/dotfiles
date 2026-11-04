"""User Corrections (words.py) and their use in the service, without a model. Words are invented.
Run: python3 -m unittest discover -s config/diacritics/tests"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import htmlmode, llama, prefs, words  # noqa: E402
from diacritics.service import Service  # noqa: E402


def entries(*items):
    """items: (typed, correct) or (typed, correct, always)"""
    return words.parse({"entries": [{"typed": i[0], "correct": i[1], "always": len(i) > 2 and i[2]} for i in items]})


def typed_of(found):
    return [e.typed for e in found]


class Relevance(unittest.TestCase):
    def test_case_and_diacritics_ignored_on_both_sides(self):
        e = entries(("uzdraveni", "uzdravení"), ("Zorvelka", "Žorvelka"))
        self.assertEqual(typed_of(words.relevant(e, "Prejeme Uzdraveni")), ["uzdraveni"])
        self.assertEqual(typed_of(words.relevant(e, "UZDRAVENÍ!")), ["uzdraveni"])
        self.assertEqual(typed_of(words.relevant(e, "ahoj zorvelka, ahoj Žorvelka")), ["Zorvelka"])

    def test_typed_with_marks_matches_text_without(self):
        self.assertEqual(len(words.relevant(entries(("přání", "přání")), "nase prani")), 1)

    def test_whole_words_only(self):
        e = entries(("plim", "plím"))
        for text in ("plimbrex", "aplim", "plim_x", "x_plim", "plim2", "9plim"):
            self.assertEqual(words.relevant(e, text), [], text)
        for text in ("plim", "ahoj plim.", "(plim)", "plim-plim", "a,plim"):
            self.assertEqual(len(words.relevant(e, text)), 1, text)

    def test_phrases(self):
        e = entries(("plimbrex forte", "Plimbrex Forté"))
        self.assertEqual(len(words.relevant(e, "dej mi Plimbrex   Forte pls")), 1)
        self.assertEqual(len(words.relevant(e, "dej mi plimbrex\nforte")), 1)
        self.assertEqual(words.relevant(e, "plimbrex a forte"), [])
        self.assertEqual(words.relevant(e, "plimbrex forteX"), [])
        self.assertEqual(words.relevant(e, "plimbrex, forte"), [])

    def test_punctuation_in_typed(self):
        e = entries(("c++", "C++"), ("co-op", "co-op"))
        self.assertEqual(len(words.relevant(e, "pisu v c++ a ne v c")), 1)
        self.assertEqual(len(words.relevant(e, "ten Co-Op tam")), 1)
        self.assertEqual(words.relevant(e, "co op"), [])

    def test_empty_inputs(self):
        self.assertEqual(words.relevant((), "text"), [])
        self.assertEqual(words.relevant(entries(("a", "á")), ""), [])

    def test_fold_keeps_length(self):
        for s in ("Příliš žluťoučký kůň", "ǅ ß İ é", "😀 ř"):
            self.assertEqual(len(words.fold(s)), len(s))
        self.assertEqual(words.fold("Příliš žluťoučký kůň"), "prilis zlutoucky kun")


class Parsing(unittest.TestCase):
    def test_bad_entries_dropped(self):
        e = words.parse({"entries": [
            {"typed": "", "correct": "x"}, {"typed": "x", "correct": " "}, {"typed": 1, "correct": "x"}, "text", None,
            {"typed": "---", "correct": "x"}, {"typed": "a\nb", "correct": "x"}, {"typed": "a", "correct": "b\tc"},
            {"typed": "ok", "correct": "ók", "always": "yes"}, {"typed": "  pad ", "correct": " páď "}]})
        self.assertEqual([(x.typed, x.correct, x.always) for x in e], [("ok", "ók", False), ("pad", "páď", False)])

    def test_field_length_cap_drops_the_entry(self):
        ok, long_ = "a" * words.MAX_FIELD, "a" * (words.MAX_FIELD + 1)
        e = words.parse({"entries": [{"typed": ok, "correct": ok}, {"typed": long_, "correct": "x"}, {"typed": "x", "correct": long_}]})
        self.assertEqual(typed_of(e), [ok])

    def test_entry_count_cap(self):
        e = words.parse({"entries": [{"typed": f"w{i}", "correct": "x"} for i in range(words.MAX_ENTRIES + 50)]})
        self.assertEqual(len(e), words.MAX_ENTRIES)

    def test_wrong_shapes(self):
        for data in (None, [], "x", {}, {"entries": None}, {"entries": {}}, 3):
            self.assertEqual(words.parse(data), ())


class FileLoading(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "w.json")

    def tearDown(self):
        self.dir.cleanup()

    def write(self, text):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(text)

    def test_missing_and_malformed_mean_no_entries(self):
        self.assertEqual(words.load(self.path), ())
        for text in ("", "{", "[1]", '{"entries": 5}', "\x00\xff", "[" * 100000):
            self.write(text)
            self.assertEqual(words.load(self.path), (), text[:10])

    def test_reread_when_the_file_changes(self):
        self.write(json.dumps({"entries": [{"typed": "a", "correct": "á"}]}))
        self.assertEqual(typed_of(words.load(self.path)), ["a"])
        self.write(json.dumps({"entries": [{"typed": "bb", "correct": "bě"}, {"typed": "c", "correct": "č"}]}))
        os.utime(self.path, ns=(1, 1))   # a new mtime even on a coarse clock
        self.assertEqual(typed_of(words.load(self.path)), ["bb", "c"])
        os.remove(self.path)
        self.assertEqual(words.load(self.path), ())

    def test_cached_while_unchanged(self):
        self.write(json.dumps({"entries": [{"typed": "a", "correct": "á"}]}))
        self.assertIs(words.load(self.path), words.load(self.path))

    def test_default_path_follows_the_state_home(self):
        old = {k: os.environ.pop(k, None) for k in ("DIACRITICS_WORDS_FILE", "XDG_STATE_HOME")}
        try:
            os.environ["XDG_STATE_HOME"] = "/x/state"
            self.assertEqual(words.paths.words_file(), "/x/state/quickshell/diacritics-words.json")
            os.environ["DIACRITICS_WORDS_FILE"] = "/y/w.json"
            self.assertEqual(words.paths.words_file(), "/y/w.json")
        finally:
            for k, v in old.items():
                os.environ.pop(k, None)
                if v is not None:
                    os.environ[k] = v


class PromptBlock(unittest.TestCase):
    def test_no_entries_no_block(self):
        self.assertEqual(words.prompt_block(()), "")

    def test_block_lists_typed_and_correct(self):
        block = words.prompt_block(entries(("nasadim", "nasadím"), ("zorvelku", "Žorvelku")))
        self.assertTrue(block.startswith("\n\nKnown spellings"))
        self.assertTrue(block.endswith("\nnasadim -> nasadím\nzorvelku -> Žorvelku\n"))

    def test_at_most_thirty_hints(self):
        e = entries(*[(f"w{i}", f"x{i}") for i in range(45)])
        block = words.prompt_block(e)
        self.assertEqual(block.count(" -> "), words.MAX_HINTS)
        self.assertIn("w29 -> x29", block)
        self.assertNotIn("w30 ->", block)


class Always(unittest.TestCase):
    def apply(self, text, *items, html=False):
        return words.apply_always(text, entries(*[(i[0], i[1], True) for i in items]), html)

    def test_replaces_whole_words_case_insensitive(self):
        self.assertEqual(self.apply("a zdravenim b", ("zdravenim", "zdravením")), "a zdravením b")
        self.assertEqual(self.apply("a zdravěním b", ("zdravenim", "zdravením")), "a zdravením b")
        self.assertEqual(self.apply("zdravenimx zdravenim_ ", ("zdravenim", "zdravením")), "zdravenimx zdravenim_ ")

    def test_capital_carried_over(self):
        e = ("plimbrex", "plímbrex")
        self.assertEqual(self.apply("Plimbrex PLIMBREX plimbrex", e), "Plímbrex PLÍMBREX plímbrex")
        self.assertEqual(self.apply("P", ("p", "q")), "Q")      # a single capital is not "ALL CAPS"
        self.assertEqual(self.apply("PL", ("pl", "ql")), "QL")

    def test_stored_capital_and_mixed_case_kept(self):
        self.assertEqual(self.apply("zorvelka", ("zorvelka", "Žorvelka")), "Žorvelka")
        self.assertEqual(self.apply("Plimbrex PLIMBREX", ("plimbrex", "PlimBrex")), "PlimBrex PlimBrex")

    def test_correct_form_is_idempotent_and_other_case_fixed(self):
        e = ("uzdraveni", "uzdravení")
        once = self.apply("uzdravení Uzdravení uzdraveni", e)
        self.assertEqual(once, "uzdravení Uzdravení uzdravení")
        self.assertEqual(self.apply(once, e), once)
        # the correct form differs from typed by more than marks: its other case is normalised as well
        self.assertEqual(self.apply("plimbreks Plímbreks", ("plimbrex", "Plimbrex"), ), "plimbreks Plímbreks")
        self.assertEqual(self.apply("PLIMBREX", ("plimbrex", "Plimbrex")), "PLIMBREX")

    def test_whitespace_and_everything_else_byte_exact(self):
        text = "  Zdravenim,\t\tPlimbrex  forte!\n\n\n(zorvelka) 😀 a_b  \n"
        out = self.apply(text, ("plimbrex forte", "Plimbrex Forté"), ("zorvelka", "Žorvelka"), ("zdravenim", "zdravením"))
        self.assertEqual(out, "  Zdravením,\t\tPlimbrex Forté!\n\n\n(Žorvelka) 😀 a_b  \n")

    def test_phrase_longest_wins_and_no_overlap(self):
        out = self.apply("plimbrex forte", ("plimbrex", "A"), ("plimbrex forte", "B"))
        self.assertEqual(out, "B")

    def test_only_always_entries(self):
        e = entries(("a", "b"), ("c", "d", True))
        self.assertEqual(words.apply_always("a c", e), "a d")
        self.assertEqual(words.apply_always("a c", entries(("a", "b"))), "a c")
        self.assertEqual(words.apply_always("", e), "")

    def test_html_text_nodes_only(self):
        e = ("cesky", "český")
        src = ('<p class="cesky" title="Cesky">Cesky <b>cesky</b> &amp; cesky<!-- cesky --><script>var cesky;</script>'
               '<style>.cesky{}</style> <a href="https://example.com/cesky">cesky</a></p>')
        want = ('<p class="cesky" title="Cesky">Český <b>český</b> &amp; český<!-- cesky --><script>var cesky;</script>'
                '<style>.cesky{}</style> <a href="https://example.com/cesky">český</a></p>')
        self.assertEqual(self.apply(src, e, html=True), want)
        self.assertTrue(htmlmode.same_markup(src, self.apply(src, e, html=True)))

    def test_html_entities_never_touched_and_block_a_match(self):
        self.assertEqual(self.apply("<p>a&nbsp;cesky &lt; cesky</p>", ("cesky", "český"), html=True), "<p>a&nbsp;český &lt; český</p>")
        self.assertEqual(self.apply("<p>caf&eacute; caf</p>", ("caf", "kaf"), html=True), "<p>caf&eacute; kaf</p>")
        self.assertEqual(self.apply("<p>AT&amp;T</p>", ("t", "x"), html=True), "<p>AT&amp;X</p>")
        self.assertEqual(self.apply("<p>amp cesky</p>", ("amp", "ámp"), html=True), "<p>ámp cesky</p>")

    def test_html_phrase_does_not_span_a_tag(self):
        self.assertEqual(self.apply("<p>plimbrex <b>forte</b></p>", ("plimbrex forte", "X"), html=True), "<p>plimbrex <b>forte</b></p>")
        self.assertEqual(self.apply("<p>plimbrex  forte</p>", ("plimbrex forte", "X"), html=True), "<p>X</p>")


class FakeServer:
    reply = ""
    prompts: list = []

    def __init__(self, model):
        self.model = model

    def start(self, log):
        pass

    def alive(self):
        return True

    def stop(self):
        pass

    def complete(self, system, text, timeout=0, on_delta=None):
        FakeServer.prompts.append((system, text))
        return FakeServer.reply


class InService(unittest.TestCase):
    def setUp(self):
        FakeServer.prompts = []
        self.svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs(), server_factory=FakeServer,
                           load_words=lambda: self.entries)
        self.states = []
        orig = self.svc.set_state
        self.svc.set_state = lambda state, text="", fixed="": (self.states.append((state, fixed)), orig(state, text, fixed))
        self.entries = ()

    def test_no_entries_prompt_identical(self):
        FakeServer.reply = "Ahoj"
        self.svc.fix("ahoj")
        self.svc.fix("<p>ahoj</p>", "html")
        self.assertEqual([p[0] for p in FakeServer.prompts], [llama.read_prompt("text"), llama.read_prompt("html")])

    def test_irrelevant_entries_do_not_reach_the_prompt(self):
        self.entries = entries(("zorvelka", "Žorvelka"), ("plimbrex", "Plimbrex", True))
        FakeServer.reply = "Ahoj"
        self.svc.fix("ahoj plimbrexe")
        self.svc.fix("<p>ahoj <b>zorvelk</b>ax</p>", "html")
        self.assertEqual([p[0] for p in FakeServer.prompts], [llama.read_prompt("text"), llama.read_prompt("html")])

    def test_relevant_entries_are_added(self):
        self.entries = entries(("zorvelka", "Žorvelka"), ("plimbrex", "Plimbrex"))
        FakeServer.reply = "Ahoj Zorvelka"
        self.svc.fix("ahoj Zorvelka")
        self.assertEqual(FakeServer.prompts[0][0], llama.read_prompt("text") + words.prompt_block(self.entries[:1]))
        self.assertNotIn("Plimbrex", FakeServer.prompts[0][0])

    def test_relevant_entries_in_html_text_not_in_attributes(self):
        self.entries = entries(("zorvelka", "Žorvelka"))
        FakeServer.reply = '<p><a href="/zorvelka">x</a></p>'
        self.svc.fix('<p><a href="/zorvelka">x</a></p>', "html")
        self.assertEqual(FakeServer.prompts[0][0], llama.read_prompt("html"))
        self.svc.fix('<p><a href="/q">Zorvelka</a></p>', "html")
        self.assertTrue(FakeServer.prompts[1][0].endswith("zorvelka -> Žorvelka\n"))

    def test_always_applied_to_the_final_text_and_done_event(self):
        self.entries = entries(("zdravenim", "zdravením", True))
        FakeServer.reply = "  Ahoj zdravěním\n"
        out = self.svc.fix("  ahoj   zdravenim ")
        self.assertEqual(out, {"ok": True, "text": "  Ahoj   zdravením "})
        self.assertEqual(self.states[-1], ("done", "  Ahoj   zdravením "))

    def test_always_in_html(self):
        self.entries = entries(("cesky", "český", True))
        FakeServer.reply = '<p class="cesky">Cesky <b>cesky</b></p>'
        out = self.svc.fix('<p class="cesky">Cesky <b>cesky</b></p>', "html")
        self.assertEqual(out["text"], '<p class="cesky">Český <b>český</b></p>')
        self.assertEqual(self.states[-1], ("done", "Český český"))

    def test_hint_without_always_leaves_the_reply_alone(self):
        self.entries = entries(("cesky", "český"))
        FakeServer.reply = "česky"
        self.assertEqual(self.svc.fix("cesky")["text"], "česky")


if __name__ == "__main__":
    unittest.main()
