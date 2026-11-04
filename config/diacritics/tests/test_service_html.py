"""HTML mode of the service with a fake model server. Run: python3 -m unittest discover -s config/diacritics/tests"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import htmlmode, llama, prefs  # noqa: E402
from diacritics.service import Service  # noqa: E402

SRC = '<p>Dobry den, <b>nabidka</b> &amp; <a href="https://example.com/?a=1&amp;b=2">cenik</a></p>\n'
FIXED = '<p>Dobrý den, <b>nabídka</b> &amp; <a href="https://example.com/?a=1&amp;b=2">ceník</a></p>'


class FakeServer:
    reply = FIXED
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


def service():
    svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs(), server_factory=FakeServer)
    svc.events = []
    orig = svc.set_state

    def spy(state, text="", fixed=""):
        svc.events.append((state, text, fixed))
        orig(state, text, fixed)

    svc.set_state = spy
    return svc


class HtmlFix(unittest.TestCase):
    def setUp(self):
        FakeServer.reply = FIXED
        FakeServer.prompts = []

    def test_html_keeps_markup_and_events_are_plain(self):
        svc = service()
        reply = svc.fix(SRC, "html")
        self.assertEqual(reply, {"ok": True, "text": FIXED + "\n"})
        working = [e for e in svc.events if e[0] == "working"][0]
        done = [e for e in svc.events if e[0] == "done"][0]
        self.assertEqual(working[1], htmlmode.to_plain(SRC))
        self.assertNotIn("<", working[1] + done[2])
        self.assertNotIn("&amp;", working[1] + done[2])
        self.assertIn("Dobrý den, nabídka & ceník", done[2])

    def test_markup_changed_is_refused(self):
        for bad in ('<p>Dobrý den, nabídka &amp; ceník</p>',
                    FIXED.replace("<b>", "<i>").replace("</b>", "</i>"),
                    FIXED.replace("?a=1", "?a=2")):
            FakeServer.reply = bad
            svc = service()
            self.assertEqual(svc.fix(SRC, "html"), {"ok": False, "error": "markup"})
            self.assertEqual(svc.events[-1][0], "failed")

    def test_plain_mode_unchanged(self):
        svc = service()
        FakeServer.reply = "<b>ahoj</b>"
        self.assertEqual(svc.fix("<b>ahoj</b>"), {"ok": True, "text": "<b>ahoj</b>"})
        FakeServer.reply = "zítra"
        self.assertEqual(svc.fix("zitra"), {"ok": True, "text": "zítra"})
        self.assertEqual([e for e in svc.events if e[0] == "working"][-1][1], "zitra")

    def test_prompt_by_format(self):
        svc = service()
        svc.fix(SRC, "html")
        svc.fix("zitra", "text")
        self.assertEqual(FakeServer.prompts[0][0], llama.read_prompt("html"))
        self.assertEqual(FakeServer.prompts[1][0], llama.read_prompt())
        self.assertNotEqual(FakeServer.prompts[0][0], FakeServer.prompts[1][0])
        self.assertIn("HTML", FakeServer.prompts[0][0])


class PromptFile(unittest.TestCase):
    def test_env_override(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("custom html prompt\n")
        try:
            with mock.patch.dict(os.environ, {"DIACRITICS_PROMPT_HTML": f.name}):
                self.assertEqual(llama.read_prompt("html"), "custom html prompt")
        finally:
            os.unlink(f.name)


class SameMarkup(unittest.TestCase):
    def test_same_and_different(self):
        self.assertTrue(htmlmode.same_markup("<p>a<br>b</p>", "<p>á<br>b</p>"))
        self.assertTrue(htmlmode.same_markup("<img src='x'>", '<img src="x">'))
        self.assertFalse(htmlmode.same_markup("<p>a</p>", "<p>a"))
        self.assertFalse(htmlmode.same_markup("<p>a</p>", "<div>a</div>"))
        self.assertFalse(htmlmode.same_markup("<a href='x'>a</a>", "<a href='y'>a</a>"))


if __name__ == "__main__":
    unittest.main()
