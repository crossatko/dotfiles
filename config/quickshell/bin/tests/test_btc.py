"""Tests for bin/btc (parsing, compact label, error paths), all against mock files.

python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "btc")
ROW = {"current_price": 67412.0, "price_change_percentage_24h": -1.25, "high_24h": 68000, "low_24h": 66000.5}


def load():
    loader = importlib.machinery.SourceFileLoader("btc_under_test", BIN)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Btc(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["QS_BTC_MOCK"] = self.tmp.name
        self.mod = load()

    def tearDown(self):
        os.environ.pop("QS_BTC_MOCK", None)
        self.tmp.cleanup()

    def put(self, status, body):
        with open(os.path.join(self.tmp.name, "markets.json"), "w") as f:
            json.dump({"status": status, "body": body}, f)

    def run_main(self, *args):
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.mod.main(list(args))
        return json.loads(buf.getvalue())

    def test_compact(self):
        c = self.mod.compact
        self.assertEqual(c(67412, "$"), "$67.4k")
        self.assertEqual(c(9999.6, "$"), "$10,000")
        self.assertEqual(c(950.5, "€"), "€950")
        self.assertEqual(c(1234567, "$"), "$1.23M")

    def test_ok(self):
        self.put(200, [ROW])
        d = self.run_main()
        self.assertTrue(d["ok"])
        self.assertEqual((d["label"], d["currency"], d["changePct"]), ("$67.4k", "USD", -1.25))
        self.assertNotIn("high", d)

    def test_currency(self):
        self.put(200, [ROW])
        d = self.run_main("--currency", "eur")
        self.assertEqual((d["currency"], d["label"]), ("EUR", "€67.4k"))
        self.assertEqual(self.run_main("--currency", "x/../y")["currency"], "USD")

    def test_missing_change(self):
        self.put(200, [{"current_price": 5.0}])
        d = self.run_main()
        self.assertTrue(d["ok"])
        self.assertIsNone(d["changePct"])

    def test_errors(self):
        self.put(429, None)
        self.assertEqual(self.run_main(), {"ok": False, "error": "rate limited"})
        self.put(500, None)
        self.assertEqual(self.run_main()["error"], "HTTP 500")
        for body in ([], {}, [{"current_price": None}], [{"current_price": "x"}], [{"current_price": 0}], None):
            self.put(200, body)
            d = self.run_main()
            self.assertFalse(d["ok"], body)
        os.remove(os.path.join(self.tmp.name, "markets.json"))
        self.assertEqual(self.run_main(), {"ok": False, "error": "offline"})
        with open(os.path.join(self.tmp.name, "markets.json"), "w") as f:
            f.write("{garbage")
        self.assertEqual(self.run_main()["error"], "offline")


if __name__ == "__main__":
    unittest.main()
