"""Unit tests without a model: whitespace handling and preferences. Run: python3 -m unittest discover -s config/diacritics/tests"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import prefs  # noqa: E402
from diacritics.service import Service, keep_spacing, restore_whitespace  # noqa: E402


class Whitespace(unittest.TestCase):
    def test_outer_whitespace_kept(self):
        self.assertEqual(restore_whitespace("  a b \n\n", "á b\n"), "  á b \n\n")

    def test_one_trailing_newline_of_the_reply_dropped(self):
        self.assertEqual(restore_whitespace("a", "á\n"), "á")
        self.assertEqual(restore_whitespace("a", "á\n\n"), "á\n")

    def test_inner_text_untouched(self):
        self.assertEqual(restore_whitespace("a  b\n\n😀", "á  b\n\n😀"), "á  b\n\n😀")

    def test_collapsed_inner_spacing_restored(self):
        self.assertEqual(keep_spacing("a  b.  c\n\n\nd 😀", "á b. č\nd 😀"), "á  b.  č\n\n\nd 😀")
        self.assertEqual(keep_spacing("  a  b \n", "á b"), "  á  b \n")

    def test_different_word_count_left_alone(self):
        self.assertEqual(keep_spacing("a  b", "ab"), "ab")


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



class IdleUnload(unittest.TestCase):
    """reap_once: llama-server stops after idle_timeout_s without a fix; 0 < x <= 1 ("Immediately") = right after the fix."""
    class FakeServer:
        def __init__(self):
            self.stopped = False
        def alive(self):
            return True
        def stop(self):
            self.stopped = True

    def svc(self, idle):
        s = Service("/nonexistent", load_prefs=lambda: prefs.Prefs(idle_timeout_s=idle))
        s.server = self.FakeServer()
        s.last_used = 100.0
        return s

    def test_rule(self):
        self.assertFalse(prefs.unload_due(0, 10 ** 6))
        self.assertFalse(prefs.unload_due(-1, 10 ** 6))
        self.assertTrue(prefs.unload_due(1, 0))
        self.assertTrue(prefs.unload_due(0.5, 0))
        self.assertFalse(prefs.unload_due(30, 29))
        self.assertTrue(prefs.unload_due(30, 30))

    def test_immediately_stops_at_the_next_check(self):
        s = self.svc(1)
        server = s.server
        s.reap_once(now=100.0)
        self.assertTrue(server.stopped)
        self.assertIsNone(s.server)

    def test_timeout_and_never(self):
        s = self.svc(30)
        s.reap_once(now=129.0)
        self.assertIsNotNone(s.server)
        s.reap_once(now=130.0)
        self.assertIsNone(s.server)
        n = self.svc(0)
        n.reap_once(now=10 ** 9)
        self.assertIsNotNone(n.server)

    def test_never_during_a_fix(self):
        s = self.svc(1)
        s.fix_lock.acquire()
        try:
            s.reap_once(now=10 ** 9)
            self.assertIsNotNone(s.server)
        finally:
            s.fix_lock.release()


if __name__ == "__main__":
    unittest.main()
