"""Unit tests without a model: whitespace handling and preferences. Run: python3 -m unittest discover -s config/diacritics/tests"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import prefs  # noqa: E402
from diacritics.service import restore_whitespace  # noqa: E402


class Whitespace(unittest.TestCase):
    def test_outer_whitespace_kept(self):
        self.assertEqual(restore_whitespace("  a b \n\n", "á b\n"), "  á b \n\n")

    def test_one_trailing_newline_of_the_reply_dropped(self):
        self.assertEqual(restore_whitespace("a", "á\n"), "á")
        self.assertEqual(restore_whitespace("a", "á\n\n"), "á\n")

    def test_inner_text_untouched(self):
        self.assertEqual(restore_whitespace("a  b\n\n😀", "á  b\n\n😀"), "á  b\n\n😀")


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
