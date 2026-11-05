"""The release tail (the mic records on after the key is up) and the final pass versus the idle unload."""
import json
import os
import tempfile
import time
import unittest

from helpers import Scripted

from dictation import prefs
from dictation.engine import Recognition, Segment
from test_lifecycle import Base, Tracked, wait_for
from test_service import Client


class Slow(Tracked):
    """The final pass takes a while; it notes the audio it got and whether the worker was closed while it ran."""

    def __init__(self, delay=0.6):
        super().__init__(["a b", "a b c"], final="a b c.")
        self.delay = delay
        self.final_audio = None
        self.closed_during_final = None

    def transcribe(self, audio, *, slot, language, translate):
        if slot != "final":
            return super().transcribe(audio, slot=slot, language=language, translate=translate)
        self.final_audio = len(audio) / 4 / 16000
        time.sleep(self.delay)
        self.closed_during_final = self.closed
        return Recognition([Segment(0.0, self.final_audio, self.final)], self.delay * 1000)


class ReleaseTail(Base):
    def audio_of_final(self, tail):
        """Seconds of audio the final pass receives when `end` comes with a release tail of `tail` seconds."""
        rec = Slow(delay=0)
        self.start(lambda: rec, prefs_fn=lambda: prefs.Prefs(idle_timeout_s=0, release_tail_s=tail))
        c = Client(self.path)
        self.dictate(c)
        c.close()
        self.tearDown()
        return rec.final_audio

    def test_audio_after_the_release_is_part_of_the_final_pass(self):
        # FakeCapture delivers 10 s of audio per wall second: 0.3 s of tail is about 3 s more audio in the final pass
        without, with_tail = self.audio_of_final(0.0), self.audio_of_final(0.3)
        self.assertGreater(with_tail, without + 1.5)

    def test_the_session_is_finishing_during_the_tail_and_cancel_ends_it_silently(self):
        rec = Slow()
        self.start(lambda: rec, prefs_fn=lambda: prefs.Prefs(idle_timeout_s=0, release_tail_s=1.5))
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "finishing")
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertIsNone(rec.final_audio)  # no final pass ran
        c.close()

    def test_a_new_begin_within_the_tail_finishes_the_old_session_first(self):
        rec = Slow(delay=0)
        self.start(lambda: rec, prefs_fn=lambda: prefs.Prefs(idle_timeout_s=0, release_tail_s=2))
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "final")
        self.assertIsNotNone(rec.final_audio)
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("cancel")
        c.close()

    def test_without_prefs_there_is_no_tail(self):
        rec = Slow(delay=0)
        self.start(lambda: rec)
        c = Client(self.path)
        self.dictate(c)
        self.assertLess(rec.final_audio, 3.0)
        c.close()


class UnloadVersusFinalPass(Base):
    def test_immediately_never_unloads_during_the_final_pass_but_right_after_it(self):
        rec = Slow(delay=0.8)
        self.start(lambda: rec, prefs_fn=lambda: prefs.Prefs(idle_timeout_s=1, release_tail_s=0.2))
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        self.assertIs(rec.closed_during_final, False)  # still resident while the full model ran
        self.assertTrue(self.rec.screen().startswith("a b c."))  # and its text was typed
        self.assertTrue(wait_for(lambda: rec.closed), "unloaded once the result was delivered")
        c.close()

    def test_a_status_poll_during_the_final_pass_does_not_unload(self):
        rec = Slow(delay=0.8)
        self.start(lambda: rec, prefs_fn=lambda: prefs.Prefs(idle_timeout_s=1, release_tail_s=0))
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.send("status")
        c.until(lambda e: e.get("event") == "final")
        self.assertIs(rec.closed_during_final, False)
        c.close()


class TailPref(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "p.json")
            with open(p, "w") as f:
                f.write(text)
            return prefs.load(p)

    def test_default_and_clamping(self):
        self.assertEqual(prefs.Prefs().release_tail_s, 0.5)
        self.assertEqual(self.load("{}").release_tail_s, 0.5)
        self.assertEqual(self.load(json.dumps({"release_tail_s": 0})).release_tail_s, 0.0)
        self.assertEqual(self.load(json.dumps({"release_tail_s": 9})).release_tail_s, 2.0)
        self.assertEqual(self.load(json.dumps({"release_tail_s": -1})).release_tail_s, 0.0)
        for bad in ('"x"', "true", "null"):
            self.assertEqual(self.load('{"release_tail_s": %s}' % bad).release_tail_s, 0.5)


if __name__ == "__main__":
    unittest.main()
