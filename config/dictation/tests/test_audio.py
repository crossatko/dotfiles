"""Capture stand-ins: the recording player used instead of a mic, and pw-record ending on its own."""
import os
import stat
import tempfile
import threading
import time
import unittest

import helpers  # noqa: F401  (puts lib/ on sys.path)

from dictation.audio import CaptureError, FileCapture, PwRecord


class FilePlayback(unittest.TestCase):
    def test_plays_the_recording_at_speaking_speed_then_silence_until_stopped(self):
        got = []
        lock = threading.Lock()

        def on_pcm(b):
            with lock:
                got.append(b)

        pcm = b"\x01\x00\x00\x00" * 1600  # 0.1 s
        cap = FileCapture(on_pcm, pcm, chunk_s=0.02)
        cap.start()
        time.sleep(0.3)
        cap.stop()
        data = b"".join(got)
        self.assertEqual(data[: len(pcm)], pcm)
        self.assertGreater(len(data), len(pcm) * 2)  # kept going after the clip
        self.assertEqual(data[len(pcm):].strip(b"\0"), b"")
        self.assertLess(len(data), len(pcm) * 5)  # real time, not as fast as possible


class Recorder(unittest.TestCase):
    def test_a_recorder_that_ends_by_itself_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "rec")
            with open(fake, "w") as f:
                f.write("#!/bin/bash\nprintf 'abcd'\nexit 3\n")
            os.chmod(fake, stat.S_IRWXU)
            rec = PwRecord(lambda b: None, cmd=[fake])
            rec.start()
            for _ in range(100):
                if rec.failed:
                    break
                time.sleep(0.02)
            self.assertIn("exit code 3", rec.failed or "")
            rec.stop()

    def test_stop_is_not_a_failure_and_a_missing_recorder_is_a_mic_error(self):
        rec = PwRecord(lambda b: None, cmd=["sh", "-c", "exec sleep 30"])  # the appended "-" becomes $0
        rec.start()
        rec.stop()
        self.assertIsNone(rec.failed)
        with self.assertRaises(CaptureError) as cm:
            PwRecord(lambda b: None, cmd=["/nonexistent/pw-record"]).start()
        self.assertEqual(cm.exception.code, "mic")


if __name__ == "__main__":
    unittest.main()
