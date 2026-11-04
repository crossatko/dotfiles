"""Service lifecycle: lazy load, idle unload (fake clock), audio buffered while models load, every failure mode."""
import asyncio
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from helpers import Recorder, Scripted, tone

from dictation import audio, prefs, whisper
from dictation.engine import Config, RecognizerError
from dictation.service import Service
from test_service import Client, FakeCapture


class Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class Tracked(Scripted):
    closed = False

    def close(self):
        self.closed = True


def wait_for(pred, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if pred():
            return True
        time.sleep(0.01)
    return False


class Base(unittest.TestCase):
    def start(self, make, capture=FakeCapture, prefs_fn=None, models_key=None, clock=None):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "d.sock")
        self.rec = Recorder()
        self.clock = clock or Clock()
        self.svc = Service(self.path, make, self.rec, lambda: "0x1", capture, prefs=prefs_fn, clock=self.clock,
                           models_key=models_key)
        ready = threading.Event()
        self.thread = threading.Thread(target=lambda: asyncio.run(self.svc.serve(ready)), daemon=True)
        self.thread.start()
        self.assertTrue(ready.wait(5))

    def tearDown(self):
        self.svc.shutdown()
        self.thread.join(10)
        self.tmp.cleanup()

    def status(self, c):
        c.send("status")
        return c.until(lambda e: e.get("event") == "status")[-1]

    def dictate(self, c, mode="en"):
        c.send(f"begin {mode}")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")


def good():
    return Tracked(["a b", "a b c"], final="a b c.")


class IdleUnload(Base):
    def test_models_load_on_the_first_begin_not_at_start(self):
        made = []
        self.start(lambda: made.append(1) or good())
        c = Client(self.path)
        st = self.status(c)
        self.assertEqual((made, st["loaded"], st["state"]), ([], False, "idle"))
        self.dictate(c)
        self.assertEqual(len(made), 1)
        self.assertTrue(self.status(c)["loaded"])
        c.close()

    def test_unload_after_the_idle_timeout_and_a_correct_dictation_after_it(self):
        made = []
        self.start(lambda: made.append(good()) or made[-1], prefs_fn=lambda: prefs.Prefs(idle_timeout_s=60))
        c = Client(self.path)
        self.dictate(c)
        self.clock.t += 59
        time.sleep(0.2)
        self.assertFalse(made[0].closed, "still resident before the timeout")
        self.clock.t += 2
        self.assertTrue(wait_for(lambda: made[0].closed), "worker closed after the timeout")
        st = self.status(c)
        self.assertEqual((st["loaded"], st["state"]), (False, "idle"))
        self.dictate(c)  # the first dictation after an unload works
        self.assertEqual((len(made), self.rec.screen()), (2, "a b c. a b c. "))
        c.close()

    def test_a_session_resets_the_idle_timer(self):
        made = []
        self.start(lambda: made.append(good()) or made[-1], prefs_fn=lambda: prefs.Prefs(idle_timeout_s=60))
        c = Client(self.path)
        self.dictate(c)
        self.clock.t += 50
        self.dictate(c)
        self.clock.t += 50
        time.sleep(0.3)
        self.assertEqual(len(made), 1)
        self.assertFalse(made[0].closed)
        c.close()

    def test_zero_and_negative_timeouts_never_unload(self):
        for value in (0, -1):
            made = []
            self.start(lambda: made.append(good()) or made[-1], prefs_fn=lambda v=value: prefs.Prefs(idle_timeout_s=v))
            c = Client(self.path)
            self.dictate(c)
            self.clock.t += 10 ** 6
            time.sleep(0.3)
            self.assertFalse(made[0].closed)
            c.close()
            self.tearDown()

    def test_a_timeout_changed_while_resident_applies(self):
        made = []
        timeout = [600]
        self.start(lambda: made.append(good()) or made[-1], prefs_fn=lambda: prefs.Prefs(idle_timeout_s=timeout[0]))
        c = Client(self.path)
        self.dictate(c)
        timeout[0] = 5
        self.clock.t += 10  # the prefs are re-read every couple of seconds while idle
        self.assertTrue(wait_for(lambda: made[0].closed))
        c.close()

    def test_no_prefs_means_never_unload(self):
        made = []
        self.start(lambda: made.append(good()) or made[-1])
        c = Client(self.path)
        self.dictate(c)
        self.clock.t += 10 ** 6
        time.sleep(0.3)
        self.assertFalse(made[0].closed)
        c.close()


class BufferedLoad(Base):
    def test_audio_captured_while_the_models_load_is_not_lost(self):
        order, release = [], threading.Event()
        delivered = []

        class Cap(FakeCapture):
            def __init__(self, on_pcm, mode=None):
                super().__init__(lambda pcm: (delivered.append(len(pcm)), on_pcm(pcm)), mode)

            def start(self):
                order.append("capture")
                super().start()

        def make():
            order.append("load")
            release.wait(5)
            return good()

        self.start(make, capture=Cap)
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "status" and e["state"] == "loading")
        time.sleep(0.5)  # the speaker talks while the models load: about 5 s of audio at fast-forward
        before_release = sum(delivered)
        self.assertGreater(before_release, 4 * 16000 * 4)
        release.set()
        c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")
        self.assertEqual(order, ["capture", "load"])
        final = [call for call in self.svc.engine.recognizer.calls if call[0] == "final"][0]
        self.assertGreaterEqual(final[3] * 16000 * 4, before_release)  # the final pass saw the buffered speech
        c.close()

    def test_end_during_the_load_still_recognises_what_was_said(self):
        release = threading.Event()
        self.start(lambda: release.wait(5) and good())
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "status" and e["state"] == "loading")
        time.sleep(0.4)
        c.send("end")  # key released before the load finished
        release.set()
        c.until(lambda e: e.get("event") == "final")
        self.assertEqual(self.rec.screen(), "a b c. ")
        c.close()

    def test_cancel_during_the_load_types_nothing(self):
        release = threading.Event()
        self.start(lambda: release.wait(5) and good())
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "status" and e["state"] == "loading")
        c.send("cancel")
        release.set()
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertEqual(self.rec.ops, [])
        c.close()


class Failures(Base):
    def test_no_microphone_is_a_mic_error_and_loads_nothing(self):
        made = []

        class NoMic(FakeCapture):
            def start(self):
                raise audio.CaptureError("microphone 'nope' not found")

        self.start(lambda: made.append(1) or good(), capture=NoMic)
        c = Client(self.path)
        c.send("begin en")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertEqual((err["code"], made), ("mic", []))
        self.assertIn("not found", err["message"])
        c.send("begin en")  # recovers: the next press tries again
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "mic")
        c.close()

    def test_the_recorder_dying_mid_session_ends_it_with_a_mic_error(self):
        caps = []

        class Dies(FakeCapture):
            def start(self):
                super().start()
                caps.append(self)

        self.start(lambda: good(), capture=Dies)
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        caps[0].failed = "microphone capture stopped (pw-record exit code 1)"
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertEqual(err["code"], "mic")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        n = len(self.rec.ops)
        time.sleep(0.3)
        self.assertEqual(len(self.rec.ops), n, "nothing typed after the failure")
        self.dictate_again(c)
        c.close()

    def dictate_again(self, c):
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        c.send("end")
        c.until(lambda e: e.get("event") == "final")

    def test_gpu_failure_is_reported_and_never_falls_back_to_the_cpu(self):
        made = []

        def make():
            made.append(1)
            if len(made) == 1:
                raise whisper.GpuFailed("no GPU backend available (Vulkan initialisation failed)")
            return good()

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertEqual(err["code"], "gpu-failed")
        self.assertEqual(self.status(c)["code"], "gpu-failed")
        self.assertEqual(self.rec.ops, [])
        self.dictate_again(c)  # the GPU is back (or the pref changed): works without a restart
        self.assertEqual(len(made), 2)
        c.close()

    def test_a_worker_that_dies_twice_in_a_session_is_an_error_then_it_recovers(self):
        made = []

        class Dies(Scripted):
            def transcribe(self, *a, **k):
                raise RecognizerError("worker exited (code -9)")

        def make():
            made.append(1)
            return Tracked([]) if False else (Dies([]) if len(made) <= 2 else good())

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        err = c.until(lambda e: e.get("event") == "error")[-1]
        self.assertEqual(err["code"], "worker")
        c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertEqual(len(made), 2, "restarted once")
        self.assertFalse(self.status(c)["loaded"])
        self.dictate_again(c)
        self.assertEqual(len(made), 3)
        c.close()

    def test_a_worker_that_cannot_restart_reports_why(self):
        made = []

        class Dies(Scripted):
            def transcribe(self, *a, **k):
                raise RecognizerError("worker exited (code -9)")

        def make():
            made.append(1)
            if len(made) == 1:
                return Dies([])
            raise whisper.ModelMissing("speech model x is not installed")

        self.start(make)
        c = Client(self.path)
        c.send("begin en")
        self.assertEqual(c.until(lambda e: e.get("event") == "error")[-1]["code"], "no-model")
        c.close()

    def test_a_second_begin_leaves_the_session_alone(self):
        self.start(lambda: good())
        c, other = Client(self.path), Client(self.path)
        other.until(lambda e: e.get("event") == "status")  # the greeting
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        other.send("begin cs")
        st = other.until(lambda e: e.get("event") == "status" and e["state"] == "listening")[-1]
        self.assertEqual(st["mode"], "en")
        c.send("end")
        seen = c.until(lambda e: e.get("event") == "final")
        self.assertNotIn("error", [e["event"] for e in seen])
        self.assertEqual(self.rec.screen(), "a b c. ")
        c.close()
        other.close()

    def test_the_owner_disconnecting_cancels_the_session(self):
        stopped = []

        class Cap(FakeCapture):
            def stop(self):
                super().stop()
                stopped.append(1)

        self.start(lambda: good(), capture=Cap)
        shell, spy = Client(self.path), Client(self.path)
        shell.send("begin en")
        shell.until(lambda e: e.get("event") == "edit")
        shell.close()
        spy.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        self.assertEqual(stopped, [1])
        n = len(self.rec.ops)
        time.sleep(0.3)
        self.assertEqual(len(self.rec.ops), n, "nothing keeps typing")
        spy.close()

    def test_a_detached_session_survives_its_sender(self):
        self.start(lambda: good())
        sender, spy = Client(self.path), Client(self.path)
        sender.send(json.dumps({"cmd": "begin", "mode": "en", "detached": True}))
        sender.until(lambda e: e.get("event") == "edit")
        sender.close()
        time.sleep(0.3)
        spy.send("end")
        spy.until(lambda e: e.get("event") == "final")
        spy.close()

    def test_sigterm_during_a_session_cancels_cleanly(self):
        stopped, recs = [], []

        class Cap(FakeCapture):
            def stop(self):
                super().stop()
                stopped.append(1)

        self.start(lambda: recs.append(good()) or recs[-1], capture=Cap)
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "edit")
        self.svc.shutdown()  # what the SIGTERM handler does
        self.thread.join(5)
        self.assertFalse(self.thread.is_alive())
        self.assertEqual(stopped, [1])
        self.assertTrue(recs[0].closed)
        n = len(self.rec.ops)
        time.sleep(0.3)
        self.assertEqual(len(self.rec.ops), n)
        self.assertNotIn("a b c.", self.rec.screen(), "no final pass on SIGTERM")
        c.close()

    def test_shutdown_while_the_models_load(self):
        release = threading.Event()
        recs = []
        self.start(lambda: release.wait(5) and (recs.append(good()) or recs[-1]))
        c = Client(self.path)
        c.send("begin en")
        c.until(lambda e: e.get("event") == "status" and e["state"] == "loading")
        threading.Timer(0.5, release.set).start()
        self.svc.shutdown()
        self.thread.join(8)
        self.assertFalse(self.thread.is_alive())
        self.assertTrue(recs[0].closed)
        self.assertEqual(self.rec.ops, [])
        c.close()


class PauseFromPrefs(Base):
    def test_begin_applies_the_prefs_pause_silence_and_the_default_without_it(self):
        made, pause = [], [1.5]
        self.start(lambda: made.append(good()) or made[-1], prefs_fn=lambda: prefs.Prefs(pause_silence_s=pause[0]))
        c = Client(self.path)
        self.dictate(c)
        self.assertEqual(self.svc.engine.config.pause_silence, 1.5)
        pause[0] = None
        self.dictate(c)
        self.assertEqual(self.svc.engine.config.pause_silence, Config().pause_silence)
        c.close()

    def test_the_prefs_switch_turns_the_trailing_space_off(self):
        space = [False]
        self.start(lambda: good(), prefs_fn=lambda: prefs.Prefs(trailing_space=space[0]))
        c = Client(self.path)
        self.dictate(c)
        space[0] = True
        self.dictate(c)
        self.assertEqual(self.rec.screen(), "a b c.a b c. ")
        c.close()


class Prefs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "p.json")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text):
        with open(self.path, "w") as f:
            f.write(text)
        return prefs.load(self.path)

    def test_defaults_when_missing_or_malformed(self):
        d = prefs.Prefs()
        self.assertEqual(prefs.load(self.path), d)
        for text in ("", "not json", "[1]", "null", '"x"', "{"):
            self.assertEqual(self.write(text), d, text)
        self.assertEqual((d.mic, d.gpu, d.idle_timeout_s, d.prompt_hints), ("", True, 600.0, False))

    def test_the_settings_page_schema(self):
        p = self.write('{"version": 1, "mic": "alsa_input.x", "gpu": false, "idle_timeout_s": 30, "prompt_hints": true}')
        self.assertEqual(p, prefs.Prefs("alsa_input.x", False, 30.0, True))

    def test_a_wrong_type_leaves_only_that_key_at_its_default(self):
        p = self.write('{"mic": 5, "gpu": "no", "idle_timeout_s": true, "prompt_hints": 1}')
        self.assertEqual(p, prefs.Prefs())
        p = self.write('{"mic": "m", "idle_timeout_s": "soon", "gpu": false}')
        self.assertEqual((p.mic, p.gpu, p.idle_timeout_s), ("m", False, 600.0))
        self.assertEqual(self.write('{"idle_timeout_s": 0}').idle_timeout_s, 0.0)
        self.assertEqual(self.write('{"idle_timeout_s": -1}').idle_timeout_s, -1.0)

    def test_gpu_device_and_the_shell_only_pill_key(self):
        self.assertEqual(prefs.Prefs().gpu_device, 0)
        self.assertEqual(self.write('{"version": 1}').gpu_device, 0)
        self.assertEqual(self.write('{"gpu_device": 1, "pill_bottom": true}').gpu_device, 1)
        self.assertEqual(self.write('{"gpu_device": 1.0}').gpu_device, 1)
        self.assertEqual(self.write('{"gpu_device": -3}').gpu_device, 0, "clamped")
        for bad in ('"1"', "true", "null", "1.5", "[1]", "NaN", "Infinity"):
            self.assertEqual(self.write('{"gpu_device": %s}' % bad).gpu_device, 0, bad)
        self.assertEqual(self.write('{"gpu_device": 1, "mic": "m"}').mic, "m")

    def test_pause_silence_without_ui(self):
        self.assertIsNone(self.write('{"version": 1}').pause_silence_s, "missing: the engine default")
        self.assertEqual(self.write('{"pause_silence_s": 1.5}').pause_silence_s, 1.5)
        self.assertEqual(self.write('{"pause_silence_s": 0}').pause_silence_s, 0.0, "0 = only on release")
        self.assertEqual(self.write('{"pause_silence_s": 0.05}').pause_silence_s, 0.3, "clamped")
        self.assertEqual(self.write('{"pause_silence_s": 99}').pause_silence_s, 10.0)
        for bad in ('"1"', "true", "null", "[1]"):
            self.assertIsNone(self.write('{"pause_silence_s": %s}' % bad).pause_silence_s, bad)

    def test_trailing_space_without_ui(self):
        self.assertTrue(self.write('{"version": 1}').trailing_space)
        self.assertFalse(self.write('{"trailing_space": false}').trailing_space)
        self.assertTrue(self.write('{"trailing_space": "no"}').trailing_space, "a wrong type is the default")

    def test_the_file_follows_the_environment(self):
        old = {k: os.environ.pop(k, None) for k in ("DICTATION_PREFS_FILE", "XDG_STATE_HOME")}
        try:
            os.environ["XDG_STATE_HOME"] = "/state"
            self.assertEqual(prefs.prefs_file(), "/state/quickshell/dictation-prefs.json")
            os.environ["DICTATION_PREFS_FILE"] = self.path
            self.assertEqual(prefs.prefs_file(), self.path)
        finally:
            for k, v in old.items():
                os.environ.pop(k, None)
                if v is not None:
                    os.environ[k] = v


class RecorderProcess(unittest.TestCase):
    def test_an_unknown_named_source_is_refused_before_recording(self):
        rec = audio.PwRecord(lambda b: None, target="nope", cmd=["sh", "-c", "exit 0"], sources=lambda: {"alsa_input.a"})
        with self.assertRaises(audio.CaptureError) as cm:
            rec.start()
        self.assertEqual(cm.exception.code, "mic")
        self.assertIn("'nope'", str(cm.exception))

    def test_a_known_source_and_an_unlistable_source_list_both_start(self):
        for sources in (lambda: {"alsa_input.a"}, lambda: None):
            rec = audio.PwRecord(lambda b: None, target="alsa_input.a", cmd=["sh", "-c", "sleep 30", "x"], sources=sources)
            rec.start()
            self.assertTrue(rec.running)
            rec.stop()

    def test_stop_leaves_no_process(self):
        rec = audio.PwRecord(lambda b: None, cmd=["sh", "-c", "exec sleep 30", "x"])
        rec.start()
        pid = rec._proc.pid
        rec.stop()
        self.assertFalse(os.path.exists(f"/proc/{pid}"))

    def test_a_recorder_that_goes_silent_is_a_failure(self):
        now = [0.0]
        rec = audio.PwRecord(lambda b: None, cmd=["sh", "-c", "exec sleep 30", "x"], stall_s=3.0, clock=lambda: now[0])
        rec.start()
        try:
            now[0] = 2.0
            self.assertIsNone(rec.failed)
            now[0] = 3.5
            self.assertIn("no audio", rec.failed)
        finally:
            rec.stop()

    def test_kill_all_stops_a_recorder_that_is_still_running(self):
        rec = audio.PwRecord(lambda b: None, cmd=["sh", "-c", "exec sleep 30", "x"])
        rec.start()
        proc = rec._proc
        audio.kill_all()
        proc.wait(5)
        rec.stop()


class WorkerProcess(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.model = os.path.join(self.tmp.name, "ggml-x.bin")
        open(self.model, "w").close()

    def tearDown(self):
        self.tmp.cleanup()

    def worker(self, body):
        path = os.path.join(self.tmp.name, "worker")
        with open(path, "w") as f:
            f.write("#!/bin/bash\n" + body + "\n")
        os.chmod(path, stat.S_IRWXU)
        return path

    def test_a_gpu_init_failure_has_its_own_code(self):
        w = self.worker('echo \'{"error":"no GPU backend available","code":"gpu"}\'; exit 4')
        with self.assertRaises(whisper.GpuFailed) as cm:
            whisper.WhisperRecognizer({"live": self.model}, worker=w)
        self.assertEqual(cm.exception.code, "gpu-failed")

    def test_no_gpu_flag_is_passed_when_the_pref_says_cpu(self):
        out = os.path.join(self.tmp.name, "argv")
        w = self.worker(f'echo "$@" > {out}; echo \'{{"ready":true,"load_ms":1}}\'; cat >/dev/null')
        r = whisper.WhisperRecognizer({"live": self.model}, worker=w, gpu=False)
        r.close()
        with open(out) as f:
            self.assertIn("--no-gpu", f.read())
        w = self.worker(f'echo "$@" > {out}; echo \'{{"ready":true,"load_ms":1}}\'; cat >/dev/null')
        whisper.WhisperRecognizer({"live": self.model}, worker=w).close()
        with open(out) as f:
            self.assertNotIn("--no-gpu", f.read())

    def test_gpu_device_flag_is_passed_only_for_a_non_default_device(self):
        out = os.path.join(self.tmp.name, "argv")
        w = self.worker(f'echo "$@" > {out}; echo \'{{"ready":true,"load_ms":1}}\'; cat >/dev/null')
        for kwargs, flag in (({}, None), ({"gpu_device": 0}, None), ({"gpu_device": 1}, "--gpu-device 1"),
                             ({"gpu_device": 1, "gpu": False}, None)):
            whisper.WhisperRecognizer({"live": self.model}, worker=w, **kwargs).close()
            with open(out) as f:
                argv = f.read()
            if flag:
                self.assertIn(flag, argv)
            else:
                self.assertNotIn("--gpu-device", argv)

    def test_a_missing_gpu_device_is_gpu_failed(self):
        w = self.worker('echo \'{"error":"GPU device 7 does not exist (2 found)","code":"gpu"}\'; exit 4')
        with self.assertRaises(whisper.GpuFailed) as cm:
            whisper.WhisperRecognizer({"live": self.model}, worker=w, gpu_device=7)
        self.assertEqual(cm.exception.code, "gpu-failed")
        self.assertIn("7", str(cm.exception))

    def test_a_worker_without_gpu_device_support_is_gpu_failed_with_a_hint(self):
        w = self.worker('echo \'{"error":"unknown argument"}\'; exit 2')
        with self.assertRaises(whisper.GpuFailed) as cm:
            whisper.WhisperRecognizer({"live": self.model}, worker=w, gpu_device=1)
        self.assertIn("build.sh", str(cm.exception))
        with self.assertRaises(whisper.WorkerFailed) as cm:  # the default device sends no flag: other errors stay as they are
            whisper.WhisperRecognizer({"live": self.model}, worker=w)
        self.assertNotIsInstance(cm.exception, whisper.GpuFailed)

    def test_close_stops_the_worker_process(self):
        w = self.worker('echo \'{"ready":true,"load_ms":1}\'; cat >/dev/null')
        r = whisper.WhisperRecognizer({"live": self.model}, worker=w)
        pid = r.pid
        r.close()
        self.assertFalse(os.path.exists(f"/proc/{pid}"))

    def test_kill_all(self):
        w = self.worker('echo \'{"ready":true,"load_ms":1}\'; exec sleep 60')
        r = whisper.WhisperRecognizer({"live": self.model}, worker=w)
        proc = r._proc
        whisper.kill_all()
        proc.wait(5)
        r.close()


if __name__ == "__main__":
    unittest.main()
