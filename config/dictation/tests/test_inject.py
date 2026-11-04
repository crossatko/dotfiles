"""The wtype adapter, against a fake runner only: these tests never start wtype."""
import os
import tempfile
import unittest

import helpers  # noqa: F401  (puts lib/ on sys.path)

from dictation.inject import InjectRefused, WtypeInjector, hyprland_focus


class FakeRun:
    def __init__(self, stdout=b""):
        self.calls = []
        self.stdout = stdout

    def __call__(self, argv, **kw):
        self.calls.append((argv, kw))

        class R:
            pass

        r = R()
        r.stdout = self.stdout
        return r


class Wtype(unittest.TestCase):
    def setUp(self):
        self.run = FakeRun()
        self.env = {"WAYLAND_DISPLAY": "wayland-test"}
        self.inj = WtypeInjector(run=self.run, env=self.env)
        os.environ.pop("DICTATION_FORBID_DISPLAY", None)

    def tearDown(self):
        os.environ.pop("DICTATION_FORBID_DISPLAY", None)

    def test_text_goes_on_stdin_after_the_backspaces(self):
        self.inj.apply(3, " Spusť příkaz")
        argv, kw = self.run.calls[0]
        self.assertEqual(argv, ["wtype", "-k", "Hyper_L", "-k", "BackSpace", "-k", "BackSpace", "-k", "BackSpace", "-"])
        self.assertEqual(kw["input"], " Spusť příkaz".encode())
        self.assertIs(kw["env"], self.env)

    def test_text_that_looks_like_an_option_is_still_text(self):
        self.inj.apply(0, "-k Return")
        argv, kw = self.run.calls[0]
        self.assertEqual(argv, ["wtype", "-k", "Hyper_L", "-"])
        self.assertEqual(kw["input"], b"-k Return")

    def test_long_text_is_typed_in_runs_of_at_most_12_keycodes(self):
        text = " Dnes odpoledne mám schůzku s klientem a potom půjdu na nákup."
        self.inj.apply(13, text)
        runs = [(argv, kw["input"].decode()) for argv, kw in self.run.calls]
        self.assertGreater(len(runs), 1)
        self.assertEqual("".join(t for _, t in runs), text)
        self.assertEqual(runs[0][0], ["wtype", "-k", "Hyper_L"] + ["-k", "BackSpace"] * 13 + ["-"])
        self.assertLessEqual(len(set(runs[0][1])), 11)  # BackSpace takes one of the 12
        for argv, t in runs[1:]:
            self.assertEqual(argv, ["wtype", "-k", "Hyper_L", "-"])
            self.assertLessEqual(len(set(t)), 12)
            self.assertTrue(t)

    def test_chunks_keep_short_text_in_one_run(self):
        self.assertEqual(WtypeInjector.chunks(0, "abcdefghijkl"), ["abcdefghijkl"])
        self.assertEqual(WtypeInjector.chunks(0, "abcdefghijklC"), ["abcdefghijkl", "C"])
        self.assertEqual(WtypeInjector.chunks(1, "abcdefghijkl"), ["abcdefghijk", "l"])
        self.assertEqual(WtypeInjector.chunks(2, ""), [""])

    def test_backspace_only(self):
        self.inj.apply(2, "")
        self.assertEqual(self.run.calls[0][0], ["wtype", "-k", "Hyper_L", "-k", "BackSpace", "-k", "BackSpace"])

    def test_nothing_to_do_runs_nothing(self):
        self.inj.apply(0, "")
        self.assertEqual(self.run.calls, [])

    def test_never_enter_tab_control_or_trailing_space(self):
        for bad in ("a\n", "a\rb", "a\tb", "a\x1bb", "a b", "word "):
            with self.assertRaises(InjectRefused, msg=repr(bad)):
                self.inj.apply(0, bad)
        self.assertEqual(self.run.calls, [])

    def test_refuses_without_a_display(self):
        inj = WtypeInjector(run=self.run, env={})
        with self.assertRaises(InjectRefused):
            inj.apply(0, "x")

    def test_refuses_a_forbidden_display(self):
        os.environ["DICTATION_FORBID_DISPLAY"] = "wayland-live, other"
        inj = WtypeInjector(run=self.run, env={"WAYLAND_DISPLAY": "/run/user/1000/wayland-live"})
        with self.assertRaises(InjectRefused):
            inj.apply(0, "x")
        self.assertEqual(self.run.calls, [])
        self.inj.apply(0, "x")  # a different display is fine
        self.assertEqual(len(self.run.calls), 1)


    def test_an_absolute_forbidden_path_refuses_only_that_socket(self):
        with tempfile.TemporaryDirectory() as live, tempfile.TemporaryDirectory() as nested:
            os.environ["DICTATION_FORBID_DISPLAY"] = os.path.join(live, "wayland-1")
            same_name = WtypeInjector(run=self.run, env={"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": nested})
            same_name.apply(0, "x")  # a nested compositor's socket with the live one's name is fine
            self.assertEqual(len(self.run.calls), 1)
            for env in ({"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": live},
                        {"WAYLAND_DISPLAY": os.path.join(live, "wayland-1"), "XDG_RUNTIME_DIR": nested}):
                with self.assertRaises(InjectRefused, msg=env):
                    WtypeInjector(run=self.run, env=env).apply(0, "x")
            self.assertEqual(len(self.run.calls), 1)


class Focus(unittest.TestCase):
    def test_reads_the_active_window_address(self):
        run = FakeRun(b'{"address": "0x55aa", "class": "x"}')
        self.assertEqual(hyprland_focus(run=run), "0x55aa")
        self.assertEqual(run.calls[0][0], ["hyprctl", "-j", "activewindow"])

    def test_no_compositor_means_unknown(self):
        def boom(*a, **k):
            raise FileNotFoundError("hyprctl")

        self.assertIsNone(hyprland_focus(run=boom))


if __name__ == "__main__":
    unittest.main()
