"""The worker client against fake workers (tiny scripts), so hangs and garbage are handled without whisper.cpp."""
import os
import stat
import tempfile
import time
import unittest

import helpers  # noqa: F401

from dictation import whisper


class FakeWorker(unittest.TestCase):
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

    def test_a_missing_model_names_the_expected_file(self):
        with self.assertRaises(whisper.ModelMissing) as cm:
            whisper.WhisperRecognizer({"final": os.path.join(self.tmp.name, "ggml-large-v3.bin")},
                                      worker=self.worker("exit 0"))
        self.assertIn("ggml-large-v3.bin", str(cm.exception))

    def test_default_model_dir_follows_xdg_data_home(self):
        old = {k: os.environ.pop(k, None) for k in ("DICTATION_MODEL_DIR", "XDG_DATA_HOME")}
        try:
            os.environ["XDG_DATA_HOME"] = "/data"
            self.assertEqual(whisper.model_path("large-v3-turbo"), "/data/dictation/models/ggml-large-v3-turbo.bin")
        finally:
            for k, v in old.items():
                os.environ.pop(k, None)
                if v is not None:
                    os.environ[k] = v

    def test_the_model_choice_is_read_like_the_settings_page_writes_it(self):
        prefs = os.path.join(self.tmp.name, "stt-models.json")
        self.assertEqual(whisper.chosen_models(prefs), {"live": "large-v3-turbo", "final": "large-v3"})  # no file
        for text, want in (
            ('{"version": 1, "live": "small", "final": "large-v3-q5_0"}', {"live": "small", "final": "large-v3-q5_0"}),
            ('{"final": "large-v3-q5_0"}', {"live": "large-v3-turbo", "final": "large-v3-q5_0"}),
            ('{"live": "../../etc/passwd", "final": 7}', {"live": "large-v3-turbo", "final": "large-v3"}),
            ("not json", {"live": "large-v3-turbo", "final": "large-v3"}),
            ("[1]", {"live": "large-v3-turbo", "final": "large-v3"}),
            ('{"live": "small\\n"}', {"live": "large-v3-turbo", "final": "large-v3"}),
        ):
            with open(prefs, "w") as f:
                f.write(text)
            self.assertEqual(whisper.chosen_models(prefs), want, text)
        self.assertEqual(whisper.chosen_models(prefs, live="medium"), {"live": "medium", "final": "large-v3"})

    def test_the_models_file_follows_xdg_state_home(self):
        old = {k: os.environ.pop(k, None) for k in ("DICTATION_MODELS_FILE", "XDG_STATE_HOME")}
        try:
            os.environ["XDG_STATE_HOME"] = "/state"
            self.assertEqual(whisper.models_file(), "/state/quickshell/stt-models.json")
            os.environ["DICTATION_MODELS_FILE"] = "/x/m.json"
            self.assertEqual(whisper.models_file(), "/x/m.json")
        finally:
            for k, v in old.items():
                os.environ.pop(k, None)
                if v is not None:
                    os.environ[k] = v

    def test_a_chosen_model_that_is_missing_is_an_error_never_another_model(self):
        open(os.path.join(self.tmp.name, "ggml-large-v3-turbo.bin"), "w").close()
        open(os.path.join(self.tmp.name, "ggml-large-v3.bin"), "w").close()
        paths = whisper.model_paths({"live": "large-v3-turbo", "final": "large-v3"}, self.tmp.name)
        self.assertEqual(paths["final"], os.path.join(self.tmp.name, "ggml-large-v3.bin"))
        with self.assertRaises(whisper.ModelMissing) as cm:
            whisper.model_paths({"live": "large-v3-turbo", "final": "large-v3-q5_0"}, self.tmp.name)
        self.assertIn("large-v3-q5_0", str(cm.exception))
        self.assertEqual(cm.exception.code, "no-model")

    def test_a_hung_worker_is_killed_after_the_timeout(self):
        w = self.worker('echo \'{"ready":true}\'; exec sleep 30')
        r = whisper.WhisperRecognizer({"live": self.model}, worker=w, timeout=0.5)
        t0 = time.monotonic()
        with self.assertRaises(whisper.WorkerFailed):
            r.transcribe(b"\0" * 64000, slot="live", language="cs", translate=False)
        self.assertLess(time.monotonic() - t0, 3)
        r.close()
        self.assertIsNotNone(r._proc.poll())

    def test_garbage_at_startup_fails_and_leaves_no_process(self):
        w = self.worker("echo 'not json'; exec sleep 30")
        with self.assertRaises(whisper.WorkerFailed):
            whisper.WhisperRecognizer({"live": self.model}, worker=w, load_timeout=5)

    def test_a_load_error_is_reported(self):
        w = self.worker('echo \'{"error":"cannot load model live: /x"}\'; exit 2')
        with self.assertRaises(whisper.WorkerFailed) as cm:
            whisper.WhisperRecognizer({"live": self.model}, worker=w)
        self.assertIn("cannot load model", str(cm.exception))

    def test_a_request_after_close_is_a_worker_failure(self):
        r = whisper.WhisperRecognizer({"final": self.model}, worker=self.worker('echo \'{"ready":true}\'; cat >/dev/null'))
        r.close()  # stdin closed: a write used to raise ValueError, which the service did not treat as a dead worker
        with self.assertRaises(whisper.WorkerFailed):
            r.transcribe(b"\0" * 6400, slot="final", language="cs", translate=False)


if __name__ == "__main__":
    unittest.main()
