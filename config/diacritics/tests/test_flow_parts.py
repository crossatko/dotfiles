"""Logic of the key flow parts without a compositor, clipboard or model."""
import os
import subprocess
import sys
import unittest
from types import SimpleNamespace

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from diacritics import clipboard, hypr, llama  # noqa: E402


def result(code=0, out="", err=""):
    return lambda *a, **k: SimpleNamespace(returncode=code, stdout=out, stderr=err)


def raises(exc):
    def run(*a, **k):
        raise exc
    return run


class Shortcut(unittest.TestCase):
    def d(self, run):
        return hypr.dispatch_shortcut("c", "0x1", run=run)

    def test_ok(self):
        self.assertEqual(self.d(result(0, "ok\n")), hypr.OK)

    def test_clear_failures(self):
        self.assertEqual(self.d(result(1, "")), hypr.FAILED)
        self.assertEqual(self.d(result(0, "Error: no such window")), hypr.FAILED)
        self.assertEqual(self.d(raises(FileNotFoundError())), hypr.FAILED)

    def test_timeout_and_odd_answers_are_unknown_and_count_as_sent(self):
        self.assertEqual(self.d(raises(subprocess.TimeoutExpired("hyprctl", 2))), hypr.UNKNOWN)
        self.assertEqual(self.d(result(0, "done")), hypr.UNKNOWN)
        self.assertTrue(hypr.send_shortcut("c", "0x1", run=result(0, "done")))
        self.assertFalse(hypr.send_shortcut("c", "0x1", run=result(1, "")))


class Saving(unittest.TestCase):
    def runner(self, types, data=None, list_code=0, list_err=b""):
        def run(argv, **k):
            if "--list-types" in argv:
                return SimpleNamespace(returncode=list_code, stdout="\n".join(types).encode(), stderr=list_err)
            mime = argv[argv.index("--type") + 1]
            d = (data or {}).get(mime)
            return SimpleNamespace(returncode=0 if d is not None else 1, stdout=d or b"", stderr=b"")
        return run

    def test_failed_listing_is_unknown(self):
        self.assertIsNone(clipboard.save(self.runner([], list_code=1, list_err=b"boom")))
        self.assertIsNone(clipboard.save(raises(subprocess.TimeoutExpired("wl-paste", 3))))

    def test_empty_clipboard_is_empty(self):
        self.assertEqual(clipboard.save(self.runner([], list_code=1, list_err=b"Nothing is copied")), {})

    def test_nothing_readable_is_unknown_and_logged(self):
        msgs = []
        self.assertIsNone(clipboard.save(self.runner(["text/plain"], {}), log=msgs.append))
        self.assertTrue(any("not readable" in m for m in msgs))

    def test_partial_save_keeps_readable_types(self):
        self.assertEqual(clipboard.save(self.runner(["a/x", "text/plain"], {"text/plain": b"hi"})), {"text/plain": b"hi"})

    def test_restore_unknown_touches_nothing(self):
        def run(*a, **k):
            raise AssertionError("must not run")
        self.assertFalse(clipboard.restore(None, run))


class Limits(unittest.TestCase):
    def test_too_long_refused(self):
        system = "x" * 2900
        llama.check_fits(system, "a" * 1000)
        with self.assertRaises(llama.ServerError) as cm:
            llama.check_fits(system, "a" * (llama.max_input_bytes(system) + 1))
        self.assertEqual(cm.exception.code, "toolong")

    def test_reply_always_fits_the_context(self):
        system = "x" * 2900
        n = llama.max_input_bytes(system)
        need = llama.estimate_tokens(system) + llama.estimate_tokens("a" * n) * (1 + llama.REPLY_FACTOR)
        self.assertLess(need, llama.CONTEXT)


if __name__ == "__main__":
    unittest.main()
