"""Tests for bin/url-router: parsing / matching units, the exact argv with a stub `brave` on PATH in a throwaway
HOME, and xdg-mime / xdg-open resolution in a fully isolated XDG environment (no real browser can start: PATH has
the stub first, XDG_DATA_DIRS / XDG_CONFIG_DIRS are scratch-only and BROWSER is a stub too).

Run: python3 -I -m unittest discover -s config/url-router/tests
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROUTER = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "url-router"))
TEMPLATE = os.path.abspath(os.path.join(os.path.dirname(ROUTER), "..", "url-router.desktop.in"))

loader = importlib.machinery.SourceFileLoader("url_router", ROUTER)
spec = importlib.util.spec_from_loader("url_router", loader)
R = importlib.util.module_from_spec(spec)
loader.exec_module(R)

STUB = """#!/bin/sh
# records its argv (one JSON list per call) and does nothing else
exec python3 -I -c 'import json, sys; open(sys.argv[1], "a").write(json.dumps(sys.argv[2:]) + "\\n")' "$STUB_LOG" "$0" "$@"
"""


def entry(exec_line, name="App"):
    return "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nTerminal=false\n" % (name, exec_line)


FIXTURES = {
    "webapp_design.desktop": entry('brave --app="https://www.design.example/"'),
    "webapp_tracker.desktop": entry('brave --app="https://tracker.example/"'),
    "webapp_chat.desktop": entry('brave --app="https://chat.example/web"'),
    "webapp_docs.desktop": entry('brave --profile-directory="Profile 1" --app="https://docs.example/" %U'),
    "webapp_dev.desktop": entry('brave --app="https://dev.example:8443/"'),
    "webapp_other.desktop": entry('firefox --kiosk https://other.example/'),          # not Brave: ignored
    "webapp_sh.desktop": entry("sh -c 'brave --app=https://shell.example/'"),        # not a browser argv[0]
    "webapp_gone.desktop": entry('brave --app="https://gone.example/"') + "Hidden=true\n",
    "brave-browser.desktop": entry("brave %U"),                                      # not webapp_*: ignored
}


class Env:
    """throwaway HOME / XDG dirs with fixture entries and a stub brave first on PATH"""

    def __init__(self, fixtures=FIXTURES, config=None):
        self.root = tempfile.mkdtemp(prefix="url-router-test-")
        self.home = os.path.join(self.root, "home")
        self.data = os.path.join(self.home, ".local", "share")
        self.conf = os.path.join(self.home, ".config")
        self.bin = os.path.join(self.root, "bin")
        self.log = os.path.join(self.root, "stub.log")
        os.makedirs(os.path.join(self.data, "applications"))
        os.makedirs(self.conf)
        os.makedirs(self.bin)
        for name, text in fixtures.items():
            with open(os.path.join(self.data, "applications", name), "w") as f:
                f.write(text)
        for b in ("brave", "firefox", "leak-browser"):
            p = os.path.join(self.bin, b)
            with open(p, "w") as f:
                f.write(STUB)
            os.chmod(p, 0o755)
        if config is not None:
            os.makedirs(os.path.join(self.conf, "url-router"))
            with open(os.path.join(self.conf, "url-router", "config"), "w") as f:
                f.write(config)

    def env(self, **extra):
        e = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin", "XDG_DATA_HOME": self.data,
             "XDG_CONFIG_HOME": self.conf, "XDG_DATA_DIRS": os.path.join(self.root, "nodata"),
             "XDG_CONFIG_DIRS": os.path.join(self.root, "noconf"), "STUB_LOG": self.log,
             "BROWSER": os.path.join(self.bin, "leak-browser"), "XDG_CURRENT_DESKTOP": "X-Generic", "LANG": "C.UTF-8"}
        e.update(extra)
        return e

    def run(self, *urls, **extra):
        return subprocess.run([sys.executable, "-I", ROUTER, *urls], env=self.env(**extra),
                              capture_output=True, text=True, timeout=20)

    def calls(self, wait=0.0):
        end = time.time() + wait
        while True:
            try:
                with open(self.log) as f:
                    lines = [json.loads(l) for l in f if l.strip()]
            except FileNotFoundError:
                lines = []
            if lines or time.time() >= end:
                return lines
            time.sleep(0.05)

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class Units(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.e = Env()
        cls.apps = R.webapps(cls.e.data)
        cls.cfg = R.load_config(cls.e.conf)

    @classmethod
    def tearDownClass(cls):
        cls.e.close()

    def m(self, url, cfg=None):
        a = R.match(url, self.apps, cfg or self.cfg)
        return a and a["slug"]

    def test_scan_only_brave_app_entries(self):
        self.assertEqual(sorted(a["slug"] for a in self.apps), ["chat", "design", "dev", "docs", "tracker"])

    def test_exec_parsing(self):
        self.assertEqual(R.split_exec('brave --profile-directory="Profile 1" --app="https://a.example/?q=1%%2" %U'),
                         ["brave", "--profile-directory=Profile 1", "--app=https://a.example/?q=1%2"])
        self.assertEqual(R.split_exec(r'brave --app="https://a.example/\$x\"y\\z"'),
                         ["brave", '--app=https://a.example/$x"y\\z'])
        self.assertIsNone(R.split_exec('brave --app="unterminated'))

    def test_host_www_and_case(self):
        self.assertEqual(self.m("https://www.design.example/file/abc?node-id=1-2#frag"), "design")
        self.assertEqual(self.m("https://design.example/file/abc"), "design")
        self.assertEqual(self.m("HTTPS://WWW.DESIGN.EXAMPLE/File"), "design")
        self.assertEqual(self.m("https://design.example./x"), "design")
        self.assertEqual(self.m("https://www.tracker.example/team/issue/ABC-1"), "tracker")

    def test_scheme_and_ports(self):
        self.assertEqual(self.m("http://tracker.example/x"), "tracker")          # default ports: http ~ https
        self.assertEqual(self.m("https://tracker.example:443/x"), "tracker")
        self.assertIsNone(self.m("https://tracker.example:8443/x"))
        self.assertEqual(self.m("https://dev.example:8443/p"), "dev")
        self.assertIsNone(self.m("https://dev.example/p"))
        self.assertIsNone(self.m("ftp://tracker.example/x"))
        self.assertIsNone(self.m("https://tracker.example:99999/x"))

    def test_subdomains_and_lookalikes_do_not_match(self):
        for u in ("https://help.design.example/", "https://design.example.evil.example/",
                  "https://evildesign.example/", "https://design.examplex/", "https://wwwdesign.example/"):
            self.assertIsNone(self.m(u), u)

    def test_userinfo_tricks(self):
        for u in ("https://design.example@evil.example/", "https://www.design.example:443@evil.example/x",  # privacy-ok: fake userinfo test inputs
                  "https://user:pass@design.example/", "https://evil.example\\@design.example/",  # privacy-ok
                  "https://design.example\\.evil.example/", "https://evil.example\\design.example/"):
            self.assertIsNone(self.m(u), u)

    def test_path_scoped_start_url(self):
        self.assertEqual(self.m("https://chat.example/web"), "chat")
        self.assertEqual(self.m("https://chat.example/web/conversations/1"), "chat")
        self.assertIsNone(self.m("https://chat.example/webinar"))
        self.assertIsNone(self.m("https://chat.example/"))

    def test_punycode(self):
        apps = [{"slug": "idn", "argv": ["brave", "--app=https://bücher.example/"], "app_index": 1,
                 "start": R.parse("https://bücher.example/")}]
        self.assertEqual(R.match("https://xn--bcher-kva.example/a", apps, self.cfg)["slug"], "idn")
        self.assertEqual(R.match("https://BÜCHER.example/a", apps, self.cfg)["slug"], "idn")
        self.assertIsNone(R.match("https://bucher.example/a", apps, self.cfg))

    def test_weird_inputs(self):
        for u in ("", " ", "-", "--app=https://design.example/", "design.example", "https://", "https:///x",
                  "javascript:alert(1)", "file:///etc/passwd", "https://design.example/a b", "https://de\tsign.example/",
                  "https://[::1/", "https://%64esign.example/", None, "\x00https://design.example/"):
            self.assertIsNone(self.m(u), repr(u))

    def test_config_disable_and_alias(self):
        cfg = {"fallback": None, "disable": {"design"}, "alias": {"tracker": ["app.webapp.example", "*.sub.example"]},
               "dry_run": None}
        self.assertIsNone(self.m("https://design.example/x", cfg))
        self.assertEqual(self.m("https://app.webapp.example/x", cfg), "tracker")
        self.assertEqual(self.m("https://sub.example/x", cfg), "tracker")
        self.assertEqual(self.m("https://a.b.sub.example/x", cfg), "tracker")
        self.assertIsNone(self.m("https://notsub.example/x", cfg))
        self.assertIsNone(self.m("https://webapp.example/x", cfg))

    def test_fallback_refuses_loopers(self):
        cfg = dict(self.cfg, fallback="xdg-open")
        self.assertEqual(R.fallback_argv(cfg), ["brave", "--"])
        cfg = dict(self.cfg, fallback="/usr/bin/gio open")
        self.assertEqual(R.fallback_argv(cfg), ["brave", "--"])
        cfg = dict(self.cfg, fallback="firefox --new-tab")
        self.assertEqual(R.fallback_argv(cfg), ["firefox", "--new-tab"])
        self.assertEqual(R.plan("-x", self.apps, cfg)[1], ["firefox", "--new-tab", "--", "-x"])


class FigmaFocus(unittest.TestCase):
    def test_pick_window(self):
        c = lambda addr, cls="figma-linux-next", h=0, **k: dict(address=addr, **{"class": cls, "focusHistoryID": h}, **k)
        self.assertEqual(R.pick_figma_window([c("0x1", h=5), c("0x2", h=1), c("0x3", h=-1)]), "0x2")
        self.assertEqual(R.pick_figma_window([c("0x1", h=-1), c("0x3", h=-1)]), "0x1")
        self.assertIsNone(R.pick_figma_window([c("0x1", cls="figma-linux-next-other"), c("0x2", cls="brave-x__"),
                                               c("0x3", mapped=False), c("zz")]))
        self.assertIsNone(R.pick_figma_window(None))
        self.assertIsNone(R.pick_figma_window([]))

    def test_command_and_signature(self):
        self.assertEqual(R.figma_focus_cmd("0xab"), ["hyprctl", "dispatch", 'hl.dsp.focus({window="address:0xab"})'])
        d = tempfile.mkdtemp()
        try:
            for n, t in (("old", 100), ("new", 200), ("dead", 300)):
                os.makedirs(os.path.join(d, "hypr", n))
                open(os.path.join(d, "hypr", n, ".socket.sock"), "w").close()
                os.utime(os.path.join(d, "hypr", n), (t, t))
            self.assertEqual(R.hypr_signature(d, lambda p: "dead" not in p), "new")
            self.assertIsNone(R.hypr_signature(d, lambda p: False))
            self.assertIsNone(R.hypr_signature(os.path.join(d, "none")))
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_focus_waits_for_cold_start(self):
        class H:
            def __init__(s):
                s.n, s.d, s.act = 0, [], None
            ok = True
            def clients(s):
                s.n += 1
                return [] if s.n < 3 else [{"address": "0xf", "class": "figma-linux-next", "focusHistoryID": 0}]
            def dispatch(s, l):
                s.d.append(l); s.act = "0xf"; return True
            def active(s):
                return s.act
        h, t = H(), [0.0]
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE="x")
        old = os.environ.copy()
        os.environ.update(env)
        try:
            real = shutil.which
            shutil.which = lambda n: "/bin/hyprctl"
            st = R.figma_focus({}, hypr=h, sleep=lambda s: t.__setitem__(0, t[0] + s), clock=lambda: t[0], lock=False)
        finally:
            shutil.which = real
            os.environ.clear(); os.environ.update(old)
        self.assertEqual(st, "focused")
        self.assertEqual(h.d, ['hl.dsp.focus({window="address:0xf"})'])

    def test_dry_run_prints_focus_and_option_off(self):
        e = Env()
        try:
            p = os.path.join(e.bin, "figma-linux-next")
            open(p, "w").write(STUB); os.chmod(p, 0o755)
            r = e.run("https://www.figma.com/design/K/F", URL_ROUTER_DRY_RUN="-")
            self.assertEqual(json.loads(r.stdout)["focus"][:2], ["hyprctl", "dispatch"])
            e.close(); e = Env(config="focus_figma = no\n")
            p = os.path.join(e.bin, "figma-linux-next")
            open(p, "w").write(STUB); os.chmod(p, 0o755)
            r = e.run("https://www.figma.com/design/K/F", URL_ROUTER_DRY_RUN="-")
            self.assertNotIn("focus", json.loads(r.stdout))
        finally:
            e.close()


class Integration(unittest.TestCase):
    def setUp(self):
        self.e = Env()

    def tearDown(self):
        self.e.close()

    def test_routed_link_exact_argv(self):
        url = "https://www.design.example/file/abc?node-id=1-2&t=x#frag"
        r = self.e.run(url)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.e.calls(), [[os.path.join(self.e.bin, "brave"), "--app=" + url]])

    def test_entry_flags_kept_field_codes_dropped(self):
        self.e.run("https://docs.example/d/1")
        self.assertEqual(self.e.calls()[0][1:], ["--profile-directory=Profile 1", "--app=https://docs.example/d/1"])

    def test_unmatched_goes_to_brave_with_separator(self):
        for u in ("https://unknown.example/x", "https://design.example@evil.example/", "mailto:user@example.com"):
            self.e.run(u)
        self.assertEqual([c[1:] for c in self.e.calls()], [["--", "https://unknown.example/x"],
                                                            ["--", "https://design.example@evil.example/"],
                                                            ["--", "mailto:user@example.com"]])

    def test_shell_metacharacters_are_inert(self):
        canary = os.path.join(self.e.root, "pwned")
        url = "https://tracker.example/x?a=$(touch${IFS}%s)&b=`touch${IFS}%s`;touch${IFS}%s|sh" % ((canary,) * 3)
        self.e.run(url)
        self.assertEqual(self.e.calls()[0][1:], ["--app=" + url])
        self.assertFalse(os.path.exists(canary))

    def test_dash_argument_never_a_flag(self):
        self.e.run("--incognito")
        self.assertEqual(self.e.calls()[0][1:], ["--", "--incognito"])

    def _figma_stub(self):
        p = os.path.join(self.e.bin, "figma-linux-next")
        with open(p, "w") as f:
            f.write(STUB)
        os.chmod(p, 0o755)

    def test_figma_links_go_to_app_when_installed(self):
        self._figma_stub()
        ok = ["https://www.figma.com/design/K/F?node-id=1-2&t=x", "https://figma.com/file/K/x",
              "https://www.figma.com/proto/K/x?page-id=0%3A1", "figma://file/K"]
        no = ["https://www.figma.com/pricing", "https://www.notfigma.com/design/a",
              "https://figma.com.evil.example/design/a", "https://www.figma.com@evil.example/design/a",
              "https://evil.example/?u=figma.com/design/x", "https://sub.figma.com/design/a"]
        for u in ok + no:
            self.e.run(u)
        got = sorted(self.e.calls(wait=2), key=lambda c: c[1:])
        figma = [c[1:] for c in got if c[0].endswith("figma-linux-next")]
        brave = [c[-1] for c in got if c[0].endswith("brave")]
        self.assertEqual(sorted(figma), sorted([[u] for u in ok]))
        self.assertEqual(sorted(brave), sorted(no))

    def test_figma_links_fall_back_to_browser_when_not_installed(self):
        tools = os.path.join(self.e.root, "tools")     # PATH without /usr/bin: the real app must not be found
        os.makedirs(tools)
        for t in ("sh", "python3"):
            os.symlink(shutil.which(t), os.path.join(tools, t))
        self.e.run("https://www.figma.com/design/K/F", PATH=self.e.bin + ":" + tools)
        self.assertEqual(self.e.calls()[0][1:], ["--", "https://www.figma.com/design/K/F"])

    def test_figma_disable(self):
        self.e.close()
        self.e = Env(config="disable = figma\n")
        self._figma_stub()
        self.e.run("https://www.figma.com/design/K/F")
        self.assertEqual(self.e.calls()[0][1:], ["--", "https://www.figma.com/design/K/F"])

    def test_no_args_and_loop_guard(self):
        self.assertEqual(self.e.run().returncode, 1)
        self.assertEqual(self.e.run("https://x.example/", URL_ROUTER_ACTIVE="1").returncode, 1)
        self.assertEqual(self.e.calls(), [])

    def test_fallback_env_and_config(self):
        self.e.run("https://unknown.example/", URL_ROUTER_FALLBACK="firefox --new-window")
        self.assertEqual(self.e.calls()[0], [os.path.join(self.e.bin, "firefox"), "--new-window",
                                             "https://unknown.example/"])

    def test_config_file_disable_and_dry_run(self):
        e = Env(config="disable = design\nalias = tracker app.webapp.example\ndry_run = -\nbogus = 1\n")
        try:
            r = e.run("https://design.example/a", "https://app.webapp.example/b")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual([json.loads(l) for l in r.stdout.splitlines()],
                             [{"app": None, "argv": ["brave", "--", "https://design.example/a"], "group": False},
                              {"app": "tracker", "argv": ["brave", "--app=https://app.webapp.example/b"],
                               "group": False}])
            self.assertIn("unknown key", r.stderr)
            self.assertEqual(e.calls(), [])
        finally:
            e.close()

    def test_two_urls_both_launched(self):
        self.e.run("https://tracker.example/1", "https://unknown.example/2")
        for _ in range(60):      # the first URL's browser is started in the background
            if len(self.e.calls()) >= 2:
                break
            time.sleep(0.05)
        calls = sorted(c[1:] for c in self.e.calls())
        self.assertEqual(calls, [["--", "https://unknown.example/2"], ["--app=https://tracker.example/1"]])


class FakeHypr:
    """in-process stand-in for the Hypr wrapper: scripted clients, records dispatches"""

    def __init__(self, clients, after=None, focus_ok=True):
        self.ok, self.state, self.after, self.focus_ok = True, clients, after, focus_ok
        self.calls, self.launched = [], False

    def clients(self):
        return self.after if (self.launched and self.after is not None) else self.state

    def active(self):
        f = [c for c in self.calls if c.startswith("hl.dsp.focus")]
        return f[-1].split('address:')[1].split('"')[0] if (f and self.focus_ok) else "0xdead"

    def dispatch(self, lua):
        self.calls.append(lua)
        return True


def client(addr, cls, focus, grouped=(), mapped=True, initial=None):
    return {"address": addr, "class": cls, "initialClass": initial or cls, "focusHistoryID": focus,
            "grouped": list(grouped), "mapped": mapped, "workspace": {"id": 1}, "monitor": 0}


class Grouping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.e = Env()
        cls.apps = {a["slug"]: a for a in R.webapps(cls.e.data)}
        cls.cfg = dict(R.load_config(cls.e.conf), group={"design"})

    @classmethod
    def tearDownClass(cls):
        cls.e.close()

    def setUp(self):
        self.launches = []
        self._launch, R.launch = R.launch, self.launches.append

    def tearDown(self):
        R.launch = self._launch

    def run_group(self, h, clock_step=0.1):
        t = [0.0]

        def clock():
            t[0] += clock_step
            return t[0]
        orig = R.launch

        def launch(argv):
            h.launched = True
            orig(argv)
        R.launch = launch
        try:
            return R.group_launch(["brave", "--app=https://design.example/x"], self.apps["design"], self.cfg, h,
                                  sleep=lambda s: None, clock=clock)
        finally:
            R.launch = orig

    def test_config_and_class_parsing(self):
        self.assertTrue(R.group_enabled("design", self.cfg))
        self.assertFalse(R.group_enabled("tracker", self.cfg))
        self.assertFalse(R.group_enabled(None, dict(self.cfg, group={"*"})))
        self.assertTrue(R.group_enabled("tracker", dict(self.cfg, group={"*"})))
        e = Env(config="group = design tracker\n")
        try:
            self.assertEqual(R.load_config(e.conf)["group"], {"design", "tracker"})
        finally:
            e.close()
        self.assertEqual(R.window_host("brave-www.design.example__file_x-Default"), "design.example")
        self.assertEqual(R.window_host("chromium-design.example__-Profile_1"), "design.example")
        self.assertIsNone(R.window_host("brave-browser"))
        self.assertIsNone(R.window_host("kitty"))

    def test_window_selection(self):
        clients = [client("0x1", "brave-design.example__-Default", 3),
                   client("0x2", "brave-www.design.example__file_a-Default", 1),
                   client("0x3", "brave-evildesign.example__-Default", 0),                 # lookalike
                   client("0x4", "brave-design.example.evil.example__-Default", 0),        # lookalike
                   client("0x5", "brave-browser", 0),
                   client("0x6", "brave-design.example__-Default", 0, mapped=False),       # unmapped
                   client("0x7", "renamed", 2, initial="brave-design.example__-Default"),
                   client("0x8", "brave-help.design.example__-Default", 0)]               # sub-domain
        got = [c["address"] for c in R.app_windows(clients, self.apps["design"], self.cfg)]
        self.assertEqual(got, ["0x2", "0x7", "0x1"])
        self.assertEqual(R.app_windows(None, self.apps["design"], self.cfg), [])
        cfg = dict(self.cfg, alias={"design": ["*.design.example"]})
        self.assertIn("0x8", [c["address"] for c in R.app_windows(clients, self.apps["design"], cfg)])

    def test_no_window_plain_launch(self):
        h = FakeHypr([client("0x9", "kitty", 0)])
        self.assertEqual(self.run_group(h), "no-window")
        self.assertEqual(h.calls, [])
        self.assertEqual(self.launches, [["brave", "--app=https://design.example/x"]])

    def test_ungrouped_window_is_grouped_and_joined(self):
        before = [client("0x1", "brave-design.example__-Default", 0)]
        after = [client("0x1", "brave-design.example__-Default", 1, grouped=["0x1", "0x2"]),
                 client("0x2", "brave-design.example__x-Default", 0, grouped=["0x1", "0x2"])]
        h = FakeHypr(before, after)
        self.assertEqual(self.run_group(h), "joined")
        self.assertEqual(h.calls, ['hl.dsp.focus({window="address:0x1"})', "hl.dsp.group.toggle()"])
        self.assertEqual(len(self.launches), 1)

    def test_already_grouped_no_toggle_and_newest_candidate(self):
        before = [client("0x1", "brave-design.example__-Default", 4, grouped=["0x1", "0xa"]),
                  client("0x3", "brave-design.example__b-Default", 2)]
        h = FakeHypr(before, before)               # the new window never shows up
        self.assertEqual(self.run_group(h), "timeout")
        self.assertEqual(h.calls, ['hl.dsp.focus({window="address:0x3"})', "hl.dsp.group.toggle()"])
        h = FakeHypr([client("0x1", "brave-design.example__-Default", 0, grouped=["0x1", "0xa"])])
        self.run_group(h)
        self.assertEqual(h.calls, ['hl.dsp.focus({window="address:0x1"})'])

    def test_new_window_outside_group_is_added(self):
        before = [client("0x1", "brave-design.example__-Default", 0)]
        after = [client("0x1", "brave-design.example__-Default", 1, grouped=["0x1"]),
                 client("0x2", "brave-design.example__x-Default", 0)]
        h = FakeHypr(before, after)
        self.assertEqual(self.run_group(h), "added")
        self.assertIn('hl.get_window("address:0x1")', h.calls[-1])
        self.assertIn('t.group:add(w)', h.calls[-1])
        self.assertIn('not t.group.locked', h.calls[-1])

    def test_focus_failure_launches_without_grouping(self):
        h = FakeHypr([client("0x1", "brave-design.example__-Default", 0)], focus_ok=False)
        self.assertEqual(self.run_group(h), "not-focused")
        self.assertNotIn("hl.dsp.group.toggle()", h.calls)
        self.assertEqual(len(self.launches), 1)

    def test_errors_still_launch(self):
        class Broken(FakeHypr):
            def clients(self):
                raise RuntimeError("boom")
        with self.assertRaises(RuntimeError):
            self.run_group(Broken([]))
        self.assertEqual(len(self.launches), 1)


HYPRCTL_STUB = r"""#!/usr/bin/env -S python3 -I
# stub hyprctl: answers from $HSTATE (clients JSON), logs every call to $HLOG
import json, os, sys
a = sys.argv[1:]
open(os.environ["HLOG"], "a").write(json.dumps(a) + "\n")
st = json.load(open(os.environ["HSTATE"]))
if a == ["-j", "clients"]:
    print(json.dumps(st))
elif a == ["-j", "activewindow"]:
    log = [json.loads(l) for l in open(os.environ["HLOG"])]
    f = [x[1] for x in log if x[0] == "dispatch" and x[1].startswith("hl.dsp.focus")]
    print(json.dumps({"address": f[-1].split("address:")[1].split('"')[0]} if f else {}))
else:
    print("ok")
"""

BRAVE_GROUP_STUB = r"""#!/usr/bin/env -S python3 -I
# stub brave: logs argv and 'opens' a window that joined the focused group (what auto_group does)
import json, os, sys
open(os.environ["STUB_LOG"], "a").write(json.dumps(sys.argv[1:]) + "\n")
st = json.load(open(os.environ["HSTATE"]))
g = ["0x1", "0x2"]
for c in st:
    c["grouped"] = g
st.append({"address": "0x2", "class": "brave-design.example__x-Default", "initialClass": "", "grouped": g,
           "mapped": True, "focusHistoryID": 0})
json.dump(st, open(os.environ["HSTATE"], "w"))
"""


class GroupingIntegration(unittest.TestCase):
    def test_router_detaches_and_groups_with_stub_hyprctl(self):
        e = Env(config="group = design\n")
        try:
            for name, text in (("hyprctl", HYPRCTL_STUB), ("brave", BRAVE_GROUP_STUB)):
                with open(os.path.join(e.bin, name), "w") as f:
                    f.write(text)
                os.chmod(os.path.join(e.bin, name), 0o755)
            hstate, hlog = os.path.join(e.root, "hstate.json"), os.path.join(e.root, "hlog")
            with open(hstate, "w") as f:
                json.dump([{"address": "0x1", "class": "brave-design.example__-Default", "grouped": [],
                            "mapped": True, "focusHistoryID": 0, "title": "never read"}], f)
            errlog = os.path.join(e.root, "router.err")
            t0 = time.time()
            with open(errlog, "w") as err:      # a file, not a pipe: the detached child keeps its stderr
                p = subprocess.Popen([sys.executable, "-I", ROUTER, "https://design.example/x"], stderr=err,
                                     env=e.env(HYPRLAND_INSTANCE_SIGNATURE="test", HSTATE=hstate, HLOG=hlog))
                self.assertEqual(p.wait(timeout=10), 0)
            self.assertLess(time.time() - t0, 1.0)          # the caller is not held while the child works
            for _ in range(100):
                with open(errlog) as f:
                    if "group design:" in f.read():
                        break
                time.sleep(0.05)
            with open(errlog) as f:
                self.assertIn("group design: joined", f.read())
            with open(hlog) as f:
                calls = [json.loads(l) for l in f]
            dispatches = [c[1] for c in calls if c[0] == "dispatch"]
            self.assertEqual(dispatches, ['hl.dsp.focus({window="address:0x1"})', "hl.dsp.group.toggle()"])
            self.assertEqual(e.calls(), [["--app=https://design.example/x"]])
        finally:
            e.close()

    def test_no_hyprland_signature_plain_exec(self):
        e = Env(config="group = design\n")
        try:
            r = e.run("https://design.example/x", HYPRLAND_INSTANCE_SIGNATURE="")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(e.calls()[0][1:], ["--app=https://design.example/x"])
        finally:
            e.close()


@unittest.skipUnless(shutil.which("xdg-open") and shutil.which("xdg-mime"), "xdg-utils not installed")
class XdgResolution(unittest.TestCase):
    """the documented apply step (desktop entry + xdg-mime default) in a scratch XDG environment"""

    def setUp(self):
        self.e = Env()
        with open(TEMPLATE) as f:
            text = f.read().replace("@ROUTER@", ROUTER)
        with open(os.path.join(self.e.data, "applications", "url-router.desktop"), "w") as f:
            f.write(text)
        for t in ("x-scheme-handler/http", "x-scheme-handler/https"):
            subprocess.run(["xdg-mime", "default", "url-router.desktop", t], env=self.e.env(), check=True, timeout=20)

    def tearDown(self):
        self.e.close()

    def test_default_registered(self):
        for t in ("x-scheme-handler/http", "x-scheme-handler/https"):
            r = subprocess.run(["xdg-mime", "query", "default", t], env=self.e.env(), capture_output=True, text=True)
            self.assertEqual(r.stdout.strip(), "url-router.desktop")
        with open(os.path.join(self.e.conf, "mimeapps.list")) as f:
            self.assertIn("x-scheme-handler/https=url-router.desktop", f.read())

    def test_xdg_open_reaches_router(self):
        env = self.e.env(WAYLAND_DISPLAY="url-router-test-none")   # xdg-open only asks xdg-mime with a "display"
        subprocess.run(["xdg-open", "https://www.tracker.example/x?y=1#z"], env=env, timeout=20, capture_output=True)
        subprocess.run(["xdg-open", "https://webapp.example/x"], env=env, timeout=20, capture_output=True)
        for _ in range(60):
            if len(self.e.calls()) >= 2:
                break
            time.sleep(0.05)
        calls = self.e.calls()
        self.assertEqual([c[0] for c in calls], [os.path.join(self.e.bin, "brave")] * 2)   # never leak-browser
        self.assertEqual([c[1:] for c in calls], [["--app=https://www.tracker.example/x?y=1#z"],
                                                  ["--", "https://webapp.example/x"]])


if __name__ == "__main__":
    unittest.main()
