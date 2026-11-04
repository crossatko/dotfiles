"""Tests for bin/stt-models against a local HTTP server serving small fake model files (no network).

python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stt-models")
DATA = bytes((i * 7 + i // 251) % 256 for i in range(3 * 1024 * 1024 + 123))
SHA = hashlib.sha256(DATA).hexdigest()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    cut_after = None        # close the connection after this many body bytes (first request only, then cleared)
    ranges = True
    slow = False
    body = DATA
    seen = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        cls = type(self)
        data = cls.body
        start = 0
        rng = self.headers.get("Range")
        cls.seen.append(rng)
        if rng and cls.ranges:
            start = int(rng.split("=")[1].split("-")[0])
            if start >= len(data):
                self.send_response(416)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
        else:
            self.send_response(200)
        out = data[start:]
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        limit = cls.cut_after
        cls.cut_after = None
        sent = 0
        try:
            while sent < len(out):
                n = 64 * 1024
                if limit is not None and sent + n > limit:
                    n = limit - sent
                if n <= 0:
                    self.wfile.flush()
                    self.close_connection = True
                    self.connection.shutdown(2)
                    return
                self.wfile.write(out[sent:sent + n])
                sent += n
                if cls.slow:
                    time.sleep(0.05)
        except OSError:
            pass


class Base(unittest.TestCase):
    def setUp(self):
        Handler.cut_after = None
        Handler.ranges = True
        Handler.slow = False
        Handler.body = DATA
        Handler.seen = []
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "models")
        cat = {"version": 1, "models": [{
            "name": "fake", "file": "ggml-fake.bin", "url": "http://127.0.0.1:%d/m" % self.srv.server_address[1],
            "size": len(DATA), "sha256": SHA, "translate": True}]}
        self.cat = os.path.join(self.tmp.name, "cat.json")
        self.write_cat(cat)
        self.env = dict(os.environ, QS_STT_MODELS_DIR=self.dir, QS_STT_CATALOG=self.cat, QS_STT_ALLOW_HTTP="1",
                        QS_STT_RETRY_WAIT="0.05")
        self.part = os.path.join(self.dir, "ggml-fake.bin.part")
        self.final = os.path.join(self.dir, "ggml-fake.bin")

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        self.tmp.cleanup()

    def write_cat(self, cat):
        with open(os.path.join(self.tmp.name, "cat.json"), "w") as f:
            json.dump(cat, f)

    def run_cli(self, *args, **env):
        p = subprocess.run([sys.executable, "-I", BIN, *args], env=dict(self.env, **env), capture_output=True, text=True, timeout=60)
        ev = [json.loads(l) for l in p.stdout.splitlines() if l.startswith("{")]
        return p.returncode, ev, p.stdout

    def last(self, ev):
        return ev[-1]


class Download(Base):
    def test_plain(self):
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 0)
        self.assertEqual([e["event"] for e in ev if e["event"] != "progress" and e["event"] != "verifying"], ["start", "done"])
        self.assertTrue(any(e["event"] == "verifying" for e in ev))
        self.assertEqual(open(self.final, "rb").read(), DATA)
        self.assertFalse(os.path.exists(self.part))

    def test_progress_lines_are_machine_readable(self):
        Handler.slow = True
        rc, ev, _ = self.run_cli("download", "fake")
        prog = [e for e in ev if e["event"] == "progress"]
        self.assertTrue(prog)
        for e in prog:
            self.assertEqual(set(e), {"event", "name", "pct", "bytes", "total", "bps", "eta"})
            self.assertEqual(e["total"], len(DATA))
        self.assertEqual([e["bytes"] for e in prog], sorted(e["bytes"] for e in prog))

    def test_already_installed_is_noop(self):
        self.run_cli("download", "fake")
        Handler.seen = []
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual((rc, ev[-1]["event"]), (0, "done"))
        self.assertEqual(Handler.seen, [])

    def test_interrupted_connection_resumes_automatically(self):
        Handler.cut_after = 1_000_000
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 0)
        self.assertIn("retry", [e["event"] for e in ev])
        self.assertEqual(open(self.final, "rb").read(), DATA)
        self.assertTrue(Handler.seen[0] is None and Handler.seen[1].startswith("bytes="))

    def test_failure_then_resume_by_second_run(self):
        Handler.cut_after = 900_000
        rc, ev, _ = self.run_cli("download", "fake", QS_STT_RETRIES="0")
        self.assertEqual(rc, 1)
        e = ev[-1]
        self.assertEqual((e["event"], e["code"], e["resumable"]), ("error", "network", True))
        have = os.path.getsize(self.part)
        self.assertTrue(0 < have < len(DATA))
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 0)
        self.assertEqual(ev[0]["from"], have)
        self.assertEqual(Handler.seen[-1], "bytes=%d-" % have)
        self.assertEqual(open(self.final, "rb").read(), DATA)

    def test_server_without_range_restarts(self):
        os.makedirs(self.dir)
        with open(self.part, "wb") as f:
            f.write(DATA[:500_000])
        Handler.ranges = False
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 0)
        self.assertEqual(open(self.final, "rb").read(), DATA)

    def test_checksum_mismatch_deletes_part_and_never_installs(self):
        bad = bytearray(DATA)
        bad[100] ^= 1
        Handler.body = bytes(bad)
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 1)
        self.assertEqual((ev[-1]["code"], ev[-1]["resumable"]), ("checksum", False))
        self.assertFalse(os.path.exists(self.final))
        self.assertFalse(os.path.exists(self.part))

    def test_corrupt_part_from_earlier_run_is_caught(self):
        os.makedirs(self.dir)
        with open(self.part, "wb") as f:
            f.write(b"x" * 400_000)               # wrong bytes already on disk
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual((rc, ev[-1]["code"]), (1, "checksum"))
        self.assertFalse(os.path.exists(self.final))

    def test_wrong_size_from_server(self):
        Handler.body = DATA + b"extra"
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual((rc, ev[-1]["code"], ev[-1]["resumable"]), (1, "size", False))
        self.assertFalse(os.path.exists(self.final))

    def test_http_error(self):
        self.write_cat({"models": [dict(json.load(open(self.cat))["models"][0], url="http://127.0.0.1:1/x")]})
        rc, ev, _ = self.run_cli("download", "fake", QS_STT_RETRIES="0")
        self.assertEqual((rc, ev[-1]["code"]), (1, "network"))

    def test_disk_full_precheck_downloads_nothing(self):
        rc, ev, _ = self.run_cli("download", "fake", QS_STT_FREE_BYTES="1000000")
        self.assertEqual((rc, ev[-1]["code"], ev[-1]["resumable"]), (1, "space", True))
        self.assertEqual(Handler.seen, [])
        self.assertFalse(os.path.exists(self.part))

    def test_space_check_counts_existing_part(self):
        os.makedirs(self.dir)
        with open(self.part, "wb") as f:
            f.write(DATA[:2_000_000])
        need = len(DATA) - 2_000_000 + 64 * 1024 * 1024
        rc, ev, _ = self.run_cli("download", "fake", QS_STT_FREE_BYTES=str(need))
        self.assertEqual(rc, 0)

    def test_https_only_by_default(self):
        env = dict(self.env)
        env.pop("QS_STT_ALLOW_HTTP")
        p = subprocess.run([sys.executable, "-I", BIN, "download", "fake"], env=env, capture_output=True, text=True)
        self.assertEqual(json.loads(p.stdout.splitlines()[-1])["code"], "catalog")

    def test_catalog_without_checksum_is_refused(self):
        m = json.load(open(self.cat))["models"][0]
        del m["sha256"]
        self.write_cat({"models": [m]})
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual((rc, ev[-1]["code"]), (1, "catalog"))
        self.assertEqual(Handler.seen, [])

    def test_cancel_by_pid_keeps_part_then_resume(self):
        Handler.slow = True
        p = subprocess.Popen([sys.executable, "-I", BIN, "download", "fake"], env=self.env, stdout=subprocess.PIPE, text=True)
        n = 0
        while n < 3:                                    # wait for real progress
            if json.loads(p.stdout.readline())["event"] == "progress":
                n += 1
        p.send_signal(signal.SIGTERM)
        out = p.stdout.read()
        p.wait(timeout=10)
        self.assertEqual(p.returncode, 130)
        last = json.loads([l for l in out.splitlines() if l.startswith("{")][-1])
        self.assertEqual(last["event"], "cancelled")
        self.assertEqual(last["bytes"], os.path.getsize(self.part))
        self.assertFalse(os.path.exists(self.final))
        Handler.slow = False
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual(rc, 0)
        self.assertEqual(ev[0]["from"], last["bytes"])
        self.assertEqual(open(self.final, "rb").read(), DATA)

    def test_second_downloader_of_same_model_is_refused(self):
        Handler.slow = True
        p = subprocess.Popen([sys.executable, "-I", BIN, "download", "fake"], env=self.env, stdout=subprocess.PIPE, text=True)
        p.stdout.readline()
        rc, ev, _ = self.run_cli("download", "fake")
        self.assertEqual((rc, ev[-1]["code"]), (1, "busy"))
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=10)


class Listing(Base):
    def listing(self):
        rc, ev, out = self.run_cli("list")
        self.assertEqual(rc, 0)
        return json.loads(out)

    def test_states(self):
        d = self.listing()
        m = d["models"][0]
        self.assertEqual((m["installed"], m["damaged"], m["partialBytes"]), (False, False, 0))
        self.assertNotIn("url", m)
        os.makedirs(self.dir)
        with open(self.part, "wb") as f:
            f.write(b"x" * 10)
        self.assertEqual(self.listing()["models"][0]["partialBytes"], 10)
        with open(self.final, "wb") as f:
            f.write(b"short")
        m = self.listing()["models"][0]
        self.assertEqual((m["installed"], m["damaged"]), (False, True))
        self.run_cli("discard", "fake")
        self.run_cli("download", "fake")
        m = self.listing()["models"][0]
        self.assertEqual((m["installed"], m["damaged"], m["partialBytes"], m["diskBytes"]), (True, False, 0, len(DATA)))

    def test_verify_and_delete(self):
        self.run_cli("download", "fake")
        rc, ev, _ = self.run_cli("verify", "fake")
        self.assertEqual((rc, ev[-1]["ok"]), (0, True))
        with open(self.final, "r+b") as f:
            f.write(b"\xff")
        rc, ev, _ = self.run_cli("verify", "fake")
        self.assertEqual((rc, ev[-1]["ok"]), (1, False))
        rc, ev, _ = self.run_cli("delete", "fake")
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(self.final))

    def test_discard_keeps_installed(self):
        self.run_cli("download", "fake")
        with open(self.part, "wb") as f:
            f.write(b"x")
        self.run_cli("discard", "fake")
        self.assertFalse(os.path.exists(self.part))
        self.assertTrue(os.path.exists(self.final))


class Catalog(unittest.TestCase):
    def test_real_catalog_is_complete(self):
        cat = json.load(open(os.path.join(os.path.dirname(BIN), "stt-models.json")))
        names = [m["name"] for m in cat["models"]]
        self.assertEqual(len(names), len(set(names)))
        for m in cat["models"]:
            self.assertEqual(m["file"], "ggml-%s.bin" % m["name"])
            self.assertTrue(m["url"].startswith("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"))
            self.assertTrue(m["url"].endswith(m["file"]))
            self.assertRegex(m["sha256"], r"^[0-9a-f]{64}$")
            self.assertGreater(m["size"], 10_000_000)
            self.assertIsInstance(m["translate"], bool)
            self.assertIn(m["czech"], ("good", "fair", "poor"))
        self.assertNotIn("medium", names)


if __name__ == "__main__":
    unittest.main()
