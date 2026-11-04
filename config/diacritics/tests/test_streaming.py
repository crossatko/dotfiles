"""Streaming reply: llama.complete against a fake SSE server, and the service's partial events. Run: python3 -m unittest discover -s config/diacritics/tests"""
import http.client
import http.server
import json
import os
import socket
import sys
import threading
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import llama, prefs  # noqa: E402
from diacritics.llama import LlamaServer, ServerError  # noqa: E402
from diacritics.service import Service, finished_words  # noqa: E402

SRC = "Dobry den, posilam vam upravenou nabidku na zitrek. Prosim o potvrzeni terminu schuzky."
PIECES = ["Dobr", "ý", " den", ", pos", "ílám", " vám", " upravenou", " nabídku", " na", " zítřek", ".", " Pros", "ím", " o",
          " potvrzení", " termínu", " schůzky", "."]
FINAL = "".join(PIECES)


class Fake(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, pieces, finish="stop", delay=0.0, die_after=None, cut_after=None, done_line=True):
        super().__init__(("127.0.0.1", 0), Handler)
        self.pieces, self.finish, self.delay, self.die_after = pieces, finish, delay, die_after
        self.cut_after, self.done_line = cut_after, done_line
        self.requests, self.disconnected, self.finished = [], threading.Event(), threading.Event()
        threading.Thread(target=self.serve_forever, daemon=True).start()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def chunk(self, obj):
        data = (obj if isinstance(obj, str) else "data: " + json.dumps(obj, ensure_ascii=False)) + "\n\n"
        b = data.encode()
        self.wfile.write(f"{len(b):x}\r\n".encode() + b + b"\r\n")
        self.wfile.flush()

    def do_POST(self):
        s = self.server
        s.requests.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            self.chunk({"choices": [{"delta": {"role": "assistant", "content": None}}]})
            for i, p in enumerate(s.pieces):
                if s.die_after is not None and i == s.die_after:
                    self.connection.close()
                    return
                if s.cut_after is not None and i == s.cut_after:   # a chunk that promises more bytes than arrive
                    self.wfile.write(b"ff\r\ndata: {\"choices\": [{\"delta\": {\"con")
                    self.wfile.flush()
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
                time.sleep(s.delay)
                self.chunk({"choices": [{"index": 0, "delta": {"content": p}, "finish_reason": None}]})
            self.chunk({"choices": [{"index": 0, "delta": {}, "finish_reason": s.finish}]})
            self.chunk({"choices": [], "usage": {"completion_tokens": len(s.pieces)}})
            if s.done_line:
                self.chunk("data: [DONE]")
                self.wfile.write(b"0\r\n\r\n")
            s.finished.set()
        except OSError:
            s.disconnected.set()


def llama_for(fake):
    srv = LlamaServer("m.gguf")
    srv.port = fake.server_address[1]
    srv.start = lambda log=None: None
    srv.alive = lambda: True
    srv.stop = lambda: None
    return srv


def service(fake, events):
    svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs(), server_factory=lambda m: llama_for(fake))
    orig_state, orig_part = svc.set_state, svc.set_partial

    def state(st, text="", fixed=""):
        events.append((time.monotonic(), st, text, fixed))
        orig_state(st, text, fixed)

    def part(fixed):
        events.append((time.monotonic(), "partial", "", fixed))
        orig_part(fixed)

    svc.set_state, svc.set_partial = state, part
    return svc


class Complete(unittest.TestCase):
    def setUp(self):
        self.fakes = []

    def tearDown(self):
        for f in self.fakes:
            f.shutdown()
            f.server_close()

    def fake(self, *a, **k):
        f = Fake(*a, **k)
        self.fakes.append(f)
        return f

    def test_stream_requested_and_pieces_joined(self):
        f = self.fake(PIECES)
        seen = []
        out = llama_for(f).complete("sys", SRC, on_delta=seen.append)
        self.assertEqual(out, FINAL)
        self.assertTrue(f.requests[0]["stream"])
        self.assertEqual(len(seen), len(PIECES))                 # in order, each the reply so far
        self.assertEqual(seen[-1], FINAL)
        self.assertTrue(all(b.startswith(a) for a, b in zip(seen, seen[1:])))

    def test_same_as_without_callback(self):
        f = self.fake(PIECES)
        self.assertEqual(llama_for(f).complete("sys", SRC), llama_for(f).complete("sys", SRC, on_delta=lambda s: None))

    def test_finish_reason_length_is_truncated(self):
        f = self.fake(PIECES, finish="length")
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC)
        self.assertEqual(cm.exception.code, "truncated")

    def test_stream_cut_off_is_truncated_or_server_error(self):
        f = self.fake(PIECES, die_after=5)
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC)
        self.assertIn(cm.exception.code, ("truncated", "server"))

    def test_chunk_cut_mid_way_is_a_server_error(self):
        f = self.fake(PIECES, cut_after=5)
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC)
        self.assertEqual(cm.exception.code, "server")

    def test_complete_reply_needs_no_done_line(self):
        f = self.fake(PIECES, done_line=False)
        self.assertEqual(llama_for(f).complete("sys", SRC), FINAL)

    def test_total_timeout_is_exact(self):
        f = self.fake(PIECES * 5, delay=0.08)
        t0 = time.monotonic()
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC, timeout=0.4)
        self.assertEqual(cm.exception.code, "timeout")
        self.assertLess(time.monotonic() - t0, 0.4 + 0.15)

    def test_toolong_before_any_request(self):
        f = self.fake(PIECES)
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", "x" * 20000)
        self.assertEqual(cm.exception.code, "toolong")
        self.assertEqual(f.requests, [])

    def test_timeout_for_a_silent_server(self):
        f = self.fake(PIECES, delay=1.0)
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC, timeout=0.3)
        self.assertEqual(cm.exception.code, "timeout")

    def test_total_timeout_for_a_slow_stream(self):
        f = self.fake(PIECES, delay=0.1)
        with self.assertRaises(ServerError) as cm:
            llama_for(f).complete("sys", SRC, timeout=0.5)       # every gap is short, the whole reply is not
        self.assertEqual(cm.exception.code, "timeout")

    def test_cancel_when_the_callback_fails(self):
        f = self.fake(PIECES * 20, delay=0.01)

        def boom(_):
            raise RuntimeError("client gone")

        with self.assertRaises(RuntimeError):
            llama_for(f).complete("sys", SRC, on_delta=boom)
        self.assertTrue(f.disconnected.wait(3), "the connection was not closed, the model would keep generating")
        self.assertFalse(f.finished.is_set())


class Partials(unittest.TestCase):
    def setUp(self):
        self.fakes = []

    def tearDown(self):
        for f in self.fakes:
            f.shutdown()
            f.server_close()

    def run_fix(self, pieces, text=SRC, delay=0.012, fmt="text", **kw):
        f = Fake(pieces, delay=delay, **kw)
        self.fakes.append(f)
        ev = []
        svc = service(f, ev)
        return svc.fix(text, fmt), ev

    def test_order_and_final_equals_plain_result(self):
        reply, ev = self.run_fix(PIECES)
        self.assertEqual(reply, {"ok": True, "text": FINAL})
        ev = [e for e in ev if e[1] != "loading"]
        kinds = [e[1] for e in ev]
        self.assertEqual(kinds[0], "working")
        self.assertEqual(kinds[-1], "done")
        self.assertTrue(all(k == "partial" for k in kinds[1:-1]) and len(kinds) > 3)
        self.assertEqual(ev[0][2], SRC)
        self.assertEqual(ev[-1][3], FINAL)
        # every partial is a growing prefix of the final words
        words = FINAL.split()
        counts = [len(e[3].split()) for e in ev if e[1] == "partial"]
        self.assertEqual(counts, sorted(set(counts)))
        for e in ev:
            if e[1] == "partial":
                self.assertEqual(e[3].split(), words[:len(e[3].split())])

    def test_no_half_words(self):
        _, ev = self.run_fix(PIECES)
        words = set(FINAL.split())
        for e in ev:
            if e[1] == "partial":
                self.assertTrue(set(e[3].split()) <= words, e[3])
                self.assertFalse(e[3].endswith("Dobr") or e[3].endswith("pos"))

    def test_throttle(self):
        _, ev = self.run_fix(PIECES, delay=0.004)             # the whole reply in about 80 ms
        times = [e[0] for e in ev if e[1] == "partial"]
        self.assertGreaterEqual(len(times), 1)
        self.assertLess(len(times), len(PIECES) // 2)
        for a, b in zip(times, times[1:]):
            self.assertGreaterEqual(b - a, 0.055)

    def test_final_word_comes_with_done_only(self):
        _, ev = self.run_fix(PIECES)
        parts = [e[3] for e in ev if e[1] == "partial"]
        self.assertTrue(parts and not parts[-1].endswith("schůzky."))   # last word held back until the end

    def test_length_finish_is_an_error_and_no_done(self):
        reply, ev = self.run_fix(PIECES, finish="length")
        self.assertEqual(reply, {"ok": False, "error": "truncated"})
        self.assertEqual(ev[-1][1], "failed")
        self.assertNotIn("done", [e[1] for e in ev])

    def test_late_subscriber_gets_the_partial(self):
        svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs())
        svc.set_state("working", "a b c")
        svc.set_partial("á b")
        self.assertEqual(json.loads(svc.event()), {"event": "state", "state": "working", "text": "a b c", "fixed": "á b"})
        svc.set_state("done", fixed="á b č")
        svc.set_partial("zzz")                                  # ignored outside working
        self.assertEqual(json.loads(svc.event())["fixed"], "á b č")

    def subscribe(self, svc):
        a, b = socket.socketpair()
        a.sendall(b'{"op":"subscribe"}\n')
        threading.Thread(target=svc.handle, args=(b,), daemon=True).start()
        a.settimeout(3)
        return a, a.makefile("rb")

    def test_text_only_in_the_first_working_event_and_for_late_subscribers(self):
        svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs())
        early, ef = self.subscribe(svc)
        self.assertEqual(json.loads(ef.readline())["state"], "idle")
        svc.set_state("working", "a b c d")
        svc.set_partial("á b")
        svc.set_partial("á b č")
        evs = [json.loads(ef.readline()) for _ in range(3)]
        self.assertEqual(evs[0], {"event": "state", "state": "working", "text": "a b c d"})
        self.assertEqual(evs[1], {"event": "state", "state": "working", "fixed": "á b"})
        self.assertEqual(evs[2], {"event": "state", "state": "working", "fixed": "á b č"})
        late, lf = self.subscribe(svc)
        self.assertEqual(json.loads(lf.readline()),
                         {"event": "state", "state": "working", "text": "a b c d", "fixed": "á b č"})
        svc.set_state("done", fixed="á b č d")
        self.assertEqual(json.loads(ef.readline()), {"event": "state", "state": "done", "fixed": "á b č d"})
        early.close()
        late.close()

    def test_a_stalled_subscriber_does_not_block_the_fix(self):
        svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs())
        stuck, _ = self.subscribe(svc)                          # never reads
        time.sleep(0.1)
        svc.set_state("working", "x " * 10)
        t0 = time.monotonic()
        for i in range(3000):
            svc.set_partial("y" * 2000 + f" {i}")
        self.assertLess(time.monotonic() - t0, 1.0)
        svc.set_state("done", fixed="z")                        # the other subscribers still get everything
        ok, of = self.subscribe(svc)
        self.assertEqual(json.loads(of.readline())["state"], "done")
        stuck.close()
        ok.close()

    def test_first_working_event_has_no_fixed(self):
        svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs())
        svc.set_state("working", "a b")
        self.assertNotIn("fixed", json.loads(svc.event()))

    def test_html_partials_are_plain_and_whole_words(self):
        src = "<p>Dobry den, <b>nabidka</b> na zitrek a dalsi veci</p>"
        fixed = "<p>Dobrý den, <b>nabídka</b> na zítřek a další věci</p>"
        pieces = [fixed[i:i + 3] for i in range(0, len(fixed), 3)]
        reply, ev = self.run_fix(pieces, text=src, fmt="html")
        self.assertTrue(reply["ok"])
        parts = [e[3] for e in ev if e[1] == "partial"]
        self.assertTrue(parts)
        final_words = ev[-1][3].split()
        for p in parts:
            self.assertNotIn("<", p)
            self.assertNotIn("&", p)
            self.assertEqual(p.split(), final_words[:len(p.split())])

    def test_chunk_cut_mid_way_ends_failed_not_working(self):
        reply, ev = self.run_fix(PIECES, cut_after=8)
        self.assertEqual(reply, {"ok": False, "error": "server"})
        self.assertEqual(ev[-1][1], "failed")

    def test_unexpected_exception_ends_failed(self):
        f = Fake(PIECES)
        self.fakes.append(f)
        ev = []
        svc = service(f, ev)
        svc.server_factory = lambda m: type("S", (), {"alive": lambda s: True, "stop": lambda s: None, "model": m,
                                                      "start": lambda s, log=None: None,
                                                      "complete": lambda s, *a, **k: (_ for _ in ()).throw(http.client.IncompleteRead(b"x"))})()
        self.assertEqual(svc.fix(SRC), {"ok": False, "error": "server"})
        self.assertEqual(svc.state, "failed")
        self.assertFalse(svc.fix_lock.locked())

    def test_pushed_failed_replaces_a_stuck_working_state(self):
        svc = Service("/nonexistent", load_prefs=lambda: prefs.Prefs())
        svc.set_state("working", "a b")                         # no fix is running
        a, b = socket.socketpair()
        a.sendall(b'{"op":"state","state":"failed"}\n')
        svc.handle(b)
        self.assertEqual(svc.state, "failed")
        a.close()
        svc.fix_lock.acquire()                                  # a fix is running: the push is refused
        svc.set_state("working", "a b")
        c, d = socket.socketpair()
        c.sendall(b'{"op":"state","state":"failed"}\n')
        svc.handle(d)
        self.assertEqual(svc.state, "working")
        c.close()

    def test_server_dies_mid_stream_is_failed(self):
        reply, ev = self.run_fix(PIECES, die_after=8)
        self.assertFalse(reply["ok"])
        self.assertEqual(ev[-1][1], "failed")


class Hold(unittest.TestCase):
    def test_text(self):
        self.assertEqual(finished_words("Dobrý den, pos"), "Dobrý den,")
        self.assertEqual(finished_words("Dobrý den, "), "Dobrý den,")
        self.assertEqual(finished_words("Dobrý"), "")
        self.assertEqual(finished_words(""), "")

    def test_html_unfinished_tag_and_entity(self):
        self.assertEqual(finished_words("<p>Ahoj svete <b", True), "Ahoj svete")
        self.assertEqual(finished_words("<p>Ahoj svete <b>da", True), "Ahoj svete")
        self.assertEqual(finished_words("<p>Ahoj &am", True), "Ahoj")
        self.assertEqual(finished_words("<p>Ahoj &amp; svete", True), "Ahoj &")
        self.assertEqual(finished_words('<a href="https://x.example/?a=1&b=2">Ahoj sv', True), "Ahoj")
        self.assertEqual(finished_words("<p>R&D a dalsi slova", True), "R&D a dalsi")
        self.assertEqual(finished_words("<p>R&D a dalsi &", True), "R&D a dalsi")
        self.assertEqual(finished_words("<p>Ahoj &#26", True), "Ahoj")
        self.assertEqual(finished_words("<ul><li>jedna</li><li>dva", True), "- jedna\n-")


if __name__ == "__main__":
    unittest.main()
