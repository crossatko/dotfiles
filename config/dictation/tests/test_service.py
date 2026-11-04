"""The control interface: a real unix socket, with fake capture, recognizer and injector."""
import asyncio
import json
import os
import socket
import tempfile
import threading
import time
import unittest

from helpers import Recorder, Scripted, tone

from dictation.service import Service, parse_command


class FakeCapture:
    """Delivers 0.1 s of loud audio every 10 ms of wall time while running (fast-forwarded speech)."""

    def __init__(self, on_pcm, mode=None):
        self.on_pcm = on_pcm
        self.mode = mode
        self._stop = threading.Event()
        self._t = None

    def start(self):
        def pump():
            while not self._stop.is_set():
                self.on_pcm(tone(0.1))
                time.sleep(0.01)

        self._t = threading.Thread(target=pump, daemon=True)
        self._t.start()

    def stop(self):
        self._stop.set()
        self._t.join()


class Client:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(path)
        self.sock.settimeout(10)
        self.f = self.sock.makefile("rb")

    def send(self, line):
        self.sock.sendall(line.encode() + b"\n")

    def until(self, pred):
        seen = []
        while True:
            ev = json.loads(self.f.readline())
            seen.append(ev)
            if pred(ev):
                return seen

    def close(self):
        self.f.close()
        self.sock.close()


class ServiceTest(unittest.TestCase):
    svc = None

    def start(self, make_recognizer, capture=FakeCapture, models_key=None):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "d.sock")
        self.rec = Recorder()
        self.svc = Service(self.path, make_recognizer, self.rec, lambda: "0x1", capture, models_key=models_key)
        ready = threading.Event()
        self.thread = threading.Thread(target=lambda: asyncio.run(self.svc.serve(ready)), daemon=True)
        self.thread.start()
        self.assertTrue(ready.wait(5))

    def tearDown(self):
        if self.svc is None:
            return
        self.svc.shutdown()
        self.thread.join(10)
        self.assertFalse(os.path.exists(self.path), "socket removed on shutdown")
        self.tmp.cleanup()

    def test_begin_stream_end(self):
        r = Scripted(["Hello there", "Hello there my", "Hello there my friend"], final="Hello there my friend.")
        self.start(lambda: r)
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)
        c.send('{"cmd": "begin", "mode": "en"}')
        seen = c.until(lambda e: e.get("event") == "edit")
        self.assertIn({"event": "state", "state": "listening", "mode": "en"}, seen)
        self.assertTrue(any(e["event"] == "level" for e in seen))
        self.assertTrue(any(e["event"] == "preview" for e in seen))
        c.send("end")
        seen = c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        final = [e for e in seen if e["event"] == "final"]
        self.assertEqual(final[0]["text"], "Hello there my friend. ")
        self.assertEqual(self.rec.screen(), "Hello there my friend. ", "one space after the session's text")
        c.send("status")
        st = c.until(lambda e: e.get("event") == "status")[-1]
        self.assertEqual(st["state"], "idle")
        c.close()

    def test_cancel_and_bad_commands(self):
        self.start(lambda: Scripted(["a b c", "a b c d"], final="a b c d."))
        c = Client(self.path)
        c.send("begin klingon")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertIn("unknown mode", err["message"])
        self.assertEqual(err["code"], "mode")
        c.send("dance")
        self.assertIn("unknown command", c.until(lambda e: e.get("event") == "error")[-1]["message"])
        c.send("begin cs")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()

    def test_a_missing_model_is_reported_on_begin(self):
        from dictation.whisper import ModelMissing

        def fail():
            raise ModelMissing("speech model large-v3 (final) is not installed: expected /x/ggml-large-v3.bin")

        self.start(fail)
        c = Client(self.path)
        c.send("begin cs")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertIn("ggml-large-v3.bin", err["message"])
        self.assertEqual(err["code"], "no-model")
        c.send("status")
        st = c.until(lambda e: e.get("event") == "status" and e["state"] == "error")[-1]
        self.assertEqual(st["code"], "no-model")
        c.close()

    def test_a_model_installed_later_works_without_a_restart(self):
        from dictation.whisper import ModelMissing

        installed = []

        def make():
            if not installed:
                raise ModelMissing("speech model large-v3 (final) is not installed")
            return Scripted(["a b", "a b c"], final="a b c.")

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "no-model")
        installed.append(1)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        self.assertEqual(self.rec.screen(), "a b c. ")
        c.close()

    def test_a_changed_model_choice_reloads_on_the_next_begin(self):
        choice = ["turbo"]
        made = []

        def make():
            made.append(choice[0])
            return Scripted(["a b", "a b c"], final="a b c.")

        self.start(make, models_key=lambda: choice[0])
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertEqual(made, ["turbo"])  # same choice: no reload
        choice[0] = "small"
        c.send("begin en")
        seen = c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        self.assertIn("loading", [e.get("state") for e in seen if e.get("event") == "status"])
        self.assertEqual(made, ["turbo", "small"])
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()

    def test_the_capture_gets_the_mode_and_a_dead_mic_is_an_error(self):
        modes = []

        class Dies(FakeCapture):
            def start(self):
                modes.append(self.mode)
                self.failed = "microphone capture stopped (pw-record exit code 1)"

            def stop(self):
                pass

        self.start(lambda: Scripted(["a b"]), capture=Dies)
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        c.send("begin translate")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertEqual((err["code"], modes), ("mic", ["translate"]))
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()


    def test_a_broken_recognizer_is_restarted_once_and_the_session_goes_on(self):
        from dictation.engine import RecognizerError

        made = []

        class Dies(Scripted):
            def transcribe(self, *a, **k):
                raise RecognizerError("worker exited (code -9)")

        def make():
            made.append(1)
            return Dies([]) if len(made) == 1 else Scripted(["a b", "a b c"], final="a b c.")

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        self.assertEqual((len(made), self.rec.screen()), (2, "a b c. "))
        c.close()

    def test_a_failed_final_pass_reports_the_error_before_idle(self):
        class FinalFails(Scripted):
            def transcribe(self, audio, *, slot, language, translate):
                if slot == "final":
                    raise ValueError("worker refused the request: out of memory")
                return super().transcribe(audio, slot=slot, language=language, translate=translate)

        self.start(lambda: FinalFails(["a b", "a b c"], final="a b c."))
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        seen = c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        names = [e["event"] for e in seen if e["event"] in ("error", "state")]
        self.assertEqual(names[-2:], ["error", "state"], seen)
        c.close()

    def test_a_bad_command_is_answered_only_to_its_sender(self):
        self.start(lambda: Scripted(["a b"]))
        shell, script = Client(self.path), Client(self.path)
        for c in (shell, script):
            c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        script.send("begin klingon")
        self.assertEqual(script.until(lambda e: e.get("event") == "error")[-1]["code"], "mode")
        shell.send("status")  # the shell sees its own reply next, not the script's error
        self.assertEqual(shell.until(lambda e: e.get("event") in ("status", "error"))[-1]["event"], "status")
        shell.close()
        script.close()

    def test_a_mode_of_the_wrong_type_is_a_mode_error_and_the_service_goes_on(self):
        self.start(lambda: Scripted(["a b", "a b c"], final="a b c."))
        c = Client(self.path)
        c.send('{"cmd": "begin", "mode": ["cs"]}')  # unhashable: used to kill the controller thread
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "mode")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()

    def test_an_unexpected_exception_is_an_error_not_a_dead_controller(self):
        calls = []

        def focus():
            calls.append(1)
            if len(calls) == 1:
                raise OSError("hyprctl went away")
            return "0x1"

        self.start(lambda: Scripted(["a b", "a b c"], final="a b c."))
        self.svc._focus = focus
        c = Client(self.path)
        c.send("begin en")
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "error")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("cancel")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()

    def test_a_failed_worker_restart_loads_a_fresh_worker_on_the_next_begin(self):
        from dictation.engine import RecognizerError
        from dictation.whisper import ModelMissing

        made = []

        class Dies(Scripted):
            def transcribe(self, *a, **k):
                raise RecognizerError("worker exited (code -9)")

        def make():
            made.append(1)
            if len(made) == 1:
                return Dies([])
            if len(made) == 2:
                raise ModelMissing("speech model large-v3 (final) is not installed")
            return Scripted(["a b", "a b c"], final="a b c.")

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "no-model")
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        self.assertEqual((len(made), self.rec.screen()), (3, "a b c. "))
        c.close()

    def test_the_retry_timeout_defaults_to_30_s(self):
        self.svc = None
        self.assertEqual(Service("x", None, None, None, None).retry_timeout, 30.0)

    def test_shutdown_with_a_client_still_connected(self):
        self.start(lambda: Scripted([""]))
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status")
        t0 = time.monotonic()
        self.svc.shutdown()
        self.thread.join(5)
        self.assertFalse(self.thread.is_alive(), "serve() returned")
        self.assertLess(time.monotonic() - t0, 3)
        c.close()


class Parse(unittest.TestCase):
    def test_words_and_json(self):
        self.assertEqual(parse_command("begin translate"), {"cmd": "begin", "mode": "translate"})
        self.assertEqual(parse_command('{"cmd":"end"}'), {"cmd": "end"})
        self.assertEqual(parse_command("{oops"), {"cmd": "invalid"})
        self.assertIsNone(parse_command("  "))


if __name__ == "__main__":
    unittest.main()
