"""The key flow's default ignored classes equal the Settings page default (DiacriticsPrefs.qml) and cover the repo's own terminals."""
import json
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))

from diacritics import prefs  # noqa: E402

QML = os.path.join(HERE, "..", "..", "quickshell", "DiacriticsPrefs.qml")


def qml_default_classes():
    text = open(QML, encoding="utf-8").read()
    body = re.search(r"ignored_classes:\s*\[(.*?)\]", text, re.S).group(1)
    return re.findall(r'"([^"]+)"', body)


class IgnoredClasses(unittest.TestCase):
    def test_flow_default_contains_every_settings_default(self):
        qml = qml_default_classes()
        self.assertGreaterEqual(len(qml), 19)
        self.assertEqual(sorted(set(qml) - set(prefs.DEFAULT_IGNORED_CLASSES)), [])

    def test_lists_are_identical(self):
        self.assertEqual(list(prefs.DEFAULT_IGNORED_CLASSES), qml_default_classes())

    def test_repo_terminals_ignored(self):
        for c in ("com.mitchellh.ghostty", "com.herdr.terminal", "dotfiles.scratchpad"):
            self.assertIn(c, prefs.DEFAULT_IGNORED_CLASSES)

    def load(self, content):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write(content)
        try:
            return prefs.load(f.name).ignored_classes
        finally:
            os.unlink(f.name)

    def test_missing_file_or_list_gives_defaults(self):
        self.assertEqual(prefs.load("/nonexistent").ignored_classes, prefs.DEFAULT_IGNORED_CLASSES)
        self.assertEqual(self.load("{}"), prefs.DEFAULT_IGNORED_CLASSES)
        self.assertEqual(self.load(json.dumps({"ignored_classes": "kitty"})), prefs.DEFAULT_IGNORED_CLASSES)

    def test_saved_list_wins_lowercased_and_empty_is_valid(self):
        self.assertEqual(self.load(json.dumps({"ignored_classes": ["Kitty ", ""]})), ("kitty",))
        self.assertEqual(self.load(json.dumps({"ignored_classes": []})), ())

    def test_shell_only_keys_are_ignored(self):
        # the Settings page also saves the key, show_text and where the pill sits: the service and the flow ignore them
        shell = {"key": "SUPER + SHIFT + D", "show_text": False, "pill_edge": "top", "pill_gap": 3.5, "pill_x": 0,
                 "pill_screen": "Some monitor", "model": "m.gguf", "idle_timeout_s": 30}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write(json.dumps(shell))
        try:
            self.assertEqual(prefs.load(f.name), prefs.Prefs(model="m.gguf", idle_timeout_s=30.0))
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
