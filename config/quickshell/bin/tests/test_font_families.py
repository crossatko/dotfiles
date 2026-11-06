"""Tests for bin/font-families (filtering of the fc-list output), all against canned text.

python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import importlib.machinery
import importlib.util
import os
import unittest

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "font-families")

UI = "\n".join([
    "Paper Mono,Paper Mono Light\t", "Paper Mono\t", "Obel Mono,Obel Mono Thin\t100", "Obel Mono\t100",
    "Noto Sans\t0", "Noto Sans Mono\t100", "Noto Sans Adlam\t0", "Noto Sans CJK JP\t0", "Noto Serif Display\t0",
    "Font Awesome 7 Free\t0", "Material Icons\t0", "Noto Color Emoji\t0", "DejaVu Math TeX Gyre\t0",
    "TX\\-02\t100", "Bad#Name\t0", "Quote\"d\t0", "Dollar$Font\t0", "Fira Sans,Fira Sans Light\t0", ".hidden\t0", "",
])
MONO = "\n".join(["Obel Mono\t100", "Hack\t100", "Paper Mono,Paper Mono Bold\t", "DejaVu Sans\t0", "Some Mono\t0", "Noto Sans Mono CJK JP\t100"])


def load():
    loader = importlib.machinery.SourceFileLoader("font_families_under_test", BIN)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class FontFamilies(unittest.TestCase):
    def setUp(self):
        self.got = load().families(UI, MONO)

    def test_ui_keeps_base_families_only(self):
        ui = self.got["ui"]
        self.assertEqual(ui.count("Paper Mono"), 1)
        for name in ("Paper Mono", "Obel Mono", "Noto Sans", "Noto Sans Mono", "Noto Serif Display", "TX-02", "Fira Sans"):
            self.assertIn(name, ui)
        for name in ("Paper Mono Light", "Noto Sans Adlam", "Noto Sans CJK JP", "Font Awesome 7 Free", "Material Icons",
                     "Noto Color Emoji", "DejaVu Math TeX Gyre", ".hidden", "Obel Mono Thin", "Bad#Name", 'Quote"d', "Dollar$Font"):
            self.assertNotIn(name, ui)

    def test_mono_by_spacing_or_name(self):
        self.assertEqual(self.got["mono"], ["Hack", "Obel Mono", "Paper Mono", "Some Mono"])

    def test_default_always_listed(self):
        got = load().families("", "")
        self.assertEqual((got["ui"], got["mono"]), (["Paper Mono"], ["Paper Mono"]))


if __name__ == "__main__":
    unittest.main()
