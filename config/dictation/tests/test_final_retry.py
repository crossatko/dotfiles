"""A failed final pass is retried once with a fresh worker over the whole audio: nothing the user said is lost."""
import asyncio
import os
import tempfile
import threading
import time
import unittest

from helpers import Recorder, Scripted

from dictation import whisper
from dictation.engine import Dictation, RecognizerError
from dictation.service import Service
from test_lifecycle import wait_for
from test_service import Client, FakeCapture

LIVE_HYP = ["alpha beta", "alpha beta gamma delta", "alpha beta gamma delta epsilon zeta eta"]


class Flaky(Scripted):
    """Fails the final pass (the first one after the capture stopped) in the way `how` says."""

    def __init__(self, stopped, how, live=LIVE_HYP, final="alpha beta gamma delta epsilon zeta eta."):
        super().__init__(live, final)
        self.stopped, self.how, self.aborted, self.closed = stopped, how, threading.Event(), False
        self.release = threading.Event()

    def transcribe(self, audio, *, slot, language, translate):
        if self.stopped.is_set() and self.how != "ok":
            self.calls.append((slot, language, translate, len(audio) / 4 / 16000))
            if self.how == "die":
                raise RecognizerError("worker exited (code -9)")
            self.release.wait(30)  # hang until aborted
            raise RecognizerError("worker killed")
        return super().transcribe(audio, slot=slot, language=language, translate=translate)

    def abort(self):
        self.aborted.set()
        self.release.set()

    def close(self):
        self.closed = True
        self.release.set()


class Base(unittest.TestCase):
    def setUp(self):
        self.stopped = threading.Event()
        stopped = self.stopped

        class Capture(FakeCapture):
            def stop(self):
                super().stop()
                stopped.set()

        self.capture = Capture
        self.made = []
        self.focus = "0x1"
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "d.sock")
        self.rec = Recorder()

    def tearDown(self):
        try:
            self.c.close()
        except OSError:
            pass
        self.svc.shutdown()
        self.thread.join(10)
        self.tmp.cleanup()

    def start(self, hows, retry_timeout=30.0, factory=None):
        """hows: how each successive recognizer behaves in its final pass."""
        def make():
            n = len(self.made)
            if factory:
                r = factory(n)
            else:
                r = Flaky(self.stopped, hows[min(n, len(hows) - 1)])
            self.made.append(r)
            return r

        self.svc = Service(self.path, make, self.rec, lambda: self.focus, self.capture, retry_timeout=retry_timeout)
        ready = threading.Event()
        self.thread = threading.Thread(target=lambda: asyncio.run(self.svc.serve(ready)), daemon=True)
        self.thread.start()
        self.assertTrue(ready.wait(5))
        self.c = Client(self.path)

    def speak(self, mode):
        self.c.send(f"begin {mode}")
        if mode != "translate":
            self.c.until(lambda e: e.get("event") == "edit" and "zeta" in "".join(o[1] for o in self.rec.ops))
        else:
            self.c.until(lambda e: e.get("event") == "preview" and "zeta" in e["text"])

    def finish(self):
        self.c.send("end")
        return self.c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")

    def events(self, seen, name):
        return [e for e in seen if e.get("event") == name]


class Retry(Base):
    def test_transcribe_retry_fixes_the_tail_and_types_the_rest(self):
        self.start(["die", "ok"])
        self.speak("en")
        before = len(self.rec.ops)
        seen = self.finish()
        self.assertEqual(len(self.made), 2)
        retry = self.events(seen, "retry")
        self.assertEqual(len(retry), 1)
        self.assertEqual((retry[0]["what"], retry[0]["code"]), ("final", "worker"))
        final = self.events(seen, "final")
        self.assertEqual(len(final), 1)
        self.assertTrue(final[0]["retried"])
        self.assertEqual(self.events(seen, "error"), [])
        self.assertEqual(self.rec.screen(), "alpha beta gamma delta epsilon zeta eta.")
        # the retry ran over the whole audio: as long as the failed attempt's
        failed = [c for c in self.made[0].calls if c[0] == "final"][0]
        retried = [c for c in self.made[1].calls if c[0] == "final"][0]
        self.assertAlmostEqual(failed[3], retried[3], places=3)
        self.assertGreater(len(self.rec.ops), before)
        self.assertTrue(self.made[0].closed)

    def test_translate_types_nothing_until_the_retry_then_the_whole_text(self):
        self.start(["die", "ok"])
        self.speak("translate")
        self.assertEqual(self.rec.ops, [])
        seen = self.finish()
        self.assertEqual(self.rec.ops, [(0, "alpha beta gamma delta epsilon zeta eta.")])
        self.assertTrue(self.events(seen, "final")[0]["retried"])

    def test_normal_final_has_no_retry_marker(self):
        self.start(["ok"])
        self.speak("en")
        seen = self.finish()
        self.assertEqual(self.events(seen, "retry"), [])
        self.assertNotIn("retried", self.events(seen, "final")[0])
        self.assertEqual(len(self.made), 1)

    def test_two_failures_leave_the_typed_text_and_report_the_error(self):
        self.start(["die", "die", "ok"])
        self.speak("en")
        typed = list(self.rec.ops)
        seen = self.finish()
        self.assertEqual(len(self.made), 2, "retried exactly once")
        err = self.events(seen, "error")
        self.assertEqual([e["code"] for e in err], ["worker"])
        self.assertEqual(self.events(seen, "final"), [])
        self.assertEqual(self.rec.ops[: len(typed)], typed)
        self.assertEqual(self.rec.ops, typed, "no backspaces, no garbage")
        self.assertTrue(wait_for(lambda: self.made[1].closed), "the failed worker is dropped")
        # recovered: the next session loads a fresh worker and dictates
        self.rec.ops.clear()
        self.stopped.clear()
        self.speak("en")
        seen = self.finish()
        self.assertEqual(len(self.made), 3)
        self.assertEqual(self.rec.screen(), "alpha beta gamma delta epsilon zeta eta.")

    def test_translate_total_failure_types_nothing(self):
        self.start(["die"])
        self.speak("translate")
        seen = self.finish()
        self.assertEqual(self.events(seen, "error")[0]["code"], "worker")
        self.assertEqual(self.rec.ops, [])

    def test_reload_failure_codes(self):
        for exc, code in ((whisper.GpuFailed("no gpu"), "gpu-failed"), (whisper.ModelMissing("gone"), "no-model"),
                          (whisper.WorkerFailed("no start"), "worker")):
            with self.subTest(code=code):
                self.setUp()

                def factory(n, exc=exc):
                    if n == 0:
                        return Flaky(self.stopped, "die")
                    raise exc

                self.start(None, factory=factory)
                self.speak("en")
                seen = self.finish()
                self.assertEqual([e["code"] for e in self.events(seen, "error")], [code])
                self.assertEqual(len(self.events(seen, "retry")), 1)
                self.tearDown()

    def test_a_hung_retry_is_bounded(self):
        self.start(["die", "hang"], retry_timeout=0.5)
        self.speak("en")
        t0 = time.monotonic()
        seen = self.finish()
        self.assertLess(time.monotonic() - t0, 4)
        self.assertEqual(self.events(seen, "error")[0]["code"], "worker")
        self.assertTrue(self.made[1].aborted.is_set(), "the stuck worker was killed")
        self.assertEqual(self.events(seen, "final"), [])

    def test_a_hung_first_attempt_that_the_recognizer_kills_is_retried(self):
        class Hangs(Flaky):
            def transcribe(s, audio, **k):
                if s.stopped.is_set():
                    raise RecognizerError("worker did not answer within 60 s")
                return super().transcribe(audio, **k)

        self.start(None, factory=lambda n: Hangs(self.stopped, "die") if n == 0 else Flaky(self.stopped, "ok"))
        self.speak("en")
        seen = self.finish()
        self.assertTrue(self.events(seen, "final")[0]["retried"])

    def test_cancel_during_the_retry_types_nothing_and_leaves_no_worker(self):
        self.start(["die", "hang"])
        self.speak("en")
        typed = list(self.rec.ops)
        self.c.send("end")
        self.c.until(lambda e: e.get("event") == "retry")
        self.assertTrue(wait_for(lambda: len(self.made) == 2 and self.made[1].calls))
        self.c.send("cancel")
        seen = self.c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertTrue(wait_for(lambda: self.made[1].aborted.is_set()))
        self.assertTrue(wait_for(lambda: self.made[1].closed))
        self.assertEqual(self.events(seen, "final"), [])
        self.assertEqual(self.events(seen, "error"), [])
        self.assertEqual(self.rec.ops, typed)
        self.c.send("status")
        st = self.c.until(lambda e: e.get("event") == "status")[-1]
        self.assertFalse(st["loaded"])
        self.assertEqual([t.name for t in threading.enumerate() if t.name == "dictation-final" and t.is_alive()], [])

    def test_cancel_while_the_worker_reloads_closes_the_new_worker(self):
        gate = threading.Event()
        made = []

        def factory(n):
            if n == 0:
                return Flaky(self.stopped, "die")
            gate.wait(10)
            r = Flaky(self.stopped, "ok")
            made.append(r)
            return r

        self.start(None, factory=factory)
        self.speak("en")
        self.c.send("end")
        self.c.until(lambda e: e.get("event") == "retry")
        time.sleep(0.2)
        self.c.send("cancel")
        self.c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        gate.set()
        self.assertTrue(wait_for(lambda: made and made[0].closed))
        self.assertEqual(self.rec.screen(), "alpha beta gamma delta epsilon zeta"[: len(self.rec.screen())])
        self.assertNotIn("eta.", self.rec.screen())

    def test_owner_disconnect_during_the_retry_cancels_it(self):
        self.start(["die", "hang"])
        self.speak("en")
        self.c.send("end")
        self.c.until(lambda e: e.get("event") == "retry")
        self.assertTrue(wait_for(lambda: len(self.made) == 2 and self.made[1].calls))
        typed = list(self.rec.ops)
        self.c.close()
        self.assertTrue(wait_for(lambda: self.made[1].aborted.is_set()))
        self.assertEqual(self.rec.ops, typed)
        self.c = Client(self.path)
        self.assertTrue(wait_for(lambda: (self.c.send("status"), self.c.until(lambda e: e.get("event") == "status")[-1])[1]["state"] == "idle"))

    def test_cancel_during_the_first_attempt(self):
        self.start(["hang"])
        self.speak("en")
        typed = list(self.rec.ops)
        self.c.send("end")
        self.assertTrue(wait_for(lambda: self.made and self.made[0].calls and self.stopped.is_set()))
        time.sleep(0.1)
        self.c.send("cancel")
        seen = self.c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertEqual(self.events(seen, "retry"), [])
        self.assertEqual(self.rec.ops, typed)
        self.assertEqual(len(self.made), 1)

    def test_focus_change_still_suppresses_typing_on_the_retry(self):
        self.start(["die", "ok"])
        self.speak("en")
        typed = list(self.rec.ops)
        self.focus = "0x2"
        seen = self.finish()
        self.assertEqual(self.rec.ops, typed)
        self.assertTrue(self.events(seen, "aborted"))
        self.assertTrue(self.events(seen, "final"))  # the session still ends normally

    def test_sigterm_style_shutdown_during_the_retry_is_prompt(self):
        self.start(["die", "hang"])
        self.speak("en")
        self.c.send("end")
        self.c.until(lambda e: e.get("event") == "retry")
        self.assertTrue(wait_for(lambda: len(self.made) == 2 and self.made[1].calls))
        t0 = time.monotonic()
        self.svc.shutdown()
        self.thread.join(10)
        self.assertLess(time.monotonic() - t0, 4)
        self.assertTrue(self.made[1].aborted.is_set())


class EngineSeam(unittest.TestCase):
    def test_keep_on_failure_keeps_audio_and_typed_text_for_a_second_end(self):
        from helpers import tone
        rec = Recorder()
        r = Flaky(threading.Event(), "ok", final="one two three four five six.")
        r.stopped.set()
        r.how = "die"
        d = Dictation(r, rec)
        d.begin("en")
        d.feed(tone(4))
        with self.assertRaises(RecognizerError):
            d.end(keep_on_failure=True)
        self.assertTrue(d.active)
        d.recognizer = Flaky(threading.Event(), "ok", final="one two three four five six.")
        d.end(retry=True)
        self.assertFalse(d.active)
        self.assertEqual(rec.screen(), "one two three four five six.")
        self.assertAlmostEqual(r.calls[0][3], 4.0, places=1)

    def test_without_keep_the_session_closes_as_before(self):
        from helpers import tone
        r = Flaky(threading.Event(), "die")
        r.stopped.set()
        d = Dictation(r, Recorder())
        d.begin("en")
        d.feed(tone(4))
        with self.assertRaises(RecognizerError):
            d.end()
        self.assertFalse(d.active)

    def test_cancel_from_another_thread_during_the_pass_types_nothing(self):
        from helpers import tone
        rec = Recorder()
        gate = threading.Event()

        class Slow(Scripted):
            def transcribe(self, audio, **k):
                gate.wait(5)
                return super().transcribe(audio, **k)

        d = Dictation(Slow([], final="late words."), rec)
        d.begin("en")
        d.feed(tone(4))
        t = threading.Thread(target=d.end)
        t.start()
        time.sleep(0.1)
        d.cancel()
        gate.set()
        t.join(5)
        self.assertEqual(rec.ops, [])


if __name__ == "__main__":
    unittest.main()
