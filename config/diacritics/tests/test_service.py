"""Unit tests without a model: whitespace handling and preferences. Run: python3 -m unittest discover -s config/diacritics/tests"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import prefs  # noqa: E402
from diacritics.service import Service, restore_whitespace  # noqa: E402


class Whitespace(unittest.TestCase):
    def test_outer_whitespace_kept(self):
        self.assertEqual(restore_whitespace("  a b \n\n", "á b\n"), "  á b \n\n")

    def test_one_trailing_newline_of_the_reply_dropped(self):
        self.assertEqual(restore_whitespace("a", "á\n"), "á")
        self.assertEqual(restore_whitespace("a", "á\n\n"), "á\n")

    def test_inner_text_untouched(self):
        self.assertEqual(restore_whitespace("a  b\n\n😀", "á  b\n\n😀"), "á  b\n\n😀")


class Events(unittest.TestCase):
    def setUp(self):
        self.svc = Service("/nonexistent")

    def event(self):
        return json.loads(self.svc.event())

    def test_done_carries_fixed_text(self):
        self.svc.set_state("done", fixed="á b\n")
        self.assertEqual(self.event(), {"event": "state", "state": "done", "fixed": "á b\n"})

    def test_working_carries_text_not_fixed(self):
        self.svc.set_state("working", "a b")
        self.assertEqual(self.event(), {"event": "state", "state": "working", "text": "a b"})

    def test_other_states_have_no_extra_field(self):
        for state in ("idle", "loading", "failed", "unsupported"):
            self.svc.set_state(state)
            self.assertEqual(self.event(), {"event": "state", "state": state})

    def test_fixed_not_kept_after_done(self):
        self.svc.set_state("done", fixed="á")
        self.svc.set_state("idle")
        self.assertEqual(self.event(), {"event": "state", "state": "idle"})


class Prefs(unittest.TestCase):
    def load(self, content):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write(content)
        try:
            return prefs.load(f.name)
        finally:
            os.unlink(f.name)

    def test_defaults(self):
        self.assertEqual(prefs.load("/nonexistent"), prefs.Prefs())
        self.assertEqual(self.load("not json"), prefs.Prefs())

    def test_values(self):
        p = self.load(json.dumps({"model": "m.gguf", "idle_timeout_s": 3}))
        self.assertEqual((p.model, p.idle_timeout_s), ("m.gguf", 3.0))

    def test_bad_types_and_paths(self):
        p = self.load(json.dumps({"model": "../x.gguf", "idle_timeout_s": "5"}))
        self.assertEqual(p, prefs.Prefs())


if __name__ == "__main__":
    unittest.main()
