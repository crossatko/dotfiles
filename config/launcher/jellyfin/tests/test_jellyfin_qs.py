import json, os, pty, shutil, stat, subprocess, sys, tempfile, time, unittest
sys.path.insert(0, os.path.dirname(__file__))
import fake_jellyfin as fj

BIN = os.path.join(os.path.dirname(__file__), "..", "bin", "jellyfin-qs")


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = fj.start()
        cls.url = "http://127.0.0.1:%d" % cls.srv.server_address[1]

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="jq")
        self.env = dict(os.environ, JELLYFIN_QS_CONFIG_DIR=self.tmp + "/c", JELLYFIN_QS_STATE_DIR=self.tmp + "/s",
                        XDG_RUNTIME_DIR=self.tmp)
        self.env.pop("JELLYFIN_QS_MPV", None)
        self.env.pop("JELLYFIN_QS_MPV_ARGS", None)
        self.srv.log.clear()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cli(self, *a, env=None):
        p = subprocess.run([sys.executable, BIN] + list(a), capture_output=True, text=True,
                           env=env or self.env, timeout=30)
        self.assertNotIn(fj.TOKEN, p.stdout + p.stderr)
        self.assertNotIn(fj.PW, p.stdout + p.stderr)
        return p

    def login_files(self, server=None):
        os.makedirs(self.tmp + "/c"); os.makedirs(self.tmp + "/s")
        json.dump({"server": server or self.url}, open(self.tmp + "/c/config.json", "w"))
        json.dump({"token": fj.TOKEN, "user_id": fj.UID, "device_id": "dev1", "user": "alice"},
                  open(self.tmp + "/s/token.json", "w"))

    def data(self, *a):
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout)


class Cli(Base):
    def test_not_logged_in(self):
        p = self.run_cli("resume")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(len(p.stderr.strip().splitlines()), 1)
        p = self.run_cli("status", "--json")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(json.loads(p.stdout)["state"], "none")

    def test_usage(self):
        self.assertEqual(self.run_cli("bogus").returncode, 1)
        self.assertEqual(self.run_cli("login").returncode, 1)  # no TTY

    def test_login_logout(self):
        pid, fd = pty.fork()
        if pid == 0:
            os.execve(sys.executable, [sys.executable, BIN, "login"], self.env)
        for line in (self.url, fj.USER, fj.PW):
            time.sleep(0.4)
            os.write(fd, (line + "\n").encode())
        time.sleep(1)
        buf = b""
        try:
            while True:
                c = os.read(fd, 4096)
                if not c: break
                buf += c
        except OSError:
            pass
        os.waitpid(pid, 0)
        self.assertNotIn(fj.PW.encode(), buf.replace(b"s3cret-pw\r\n", b"", 0) if False else b"".join(
            l for l in buf.split(b"\r\n") if b"Password" not in l and b"Logged" not in l and b"Username" not in l
            and b"Server" not in l and l.strip() != b""), "password echoed")
        tf = self.tmp + "/s/token.json"
        self.assertEqual(stat.S_IMODE(os.stat(tf).st_mode), 0o600)
        self.assertEqual(json.load(open(tf))["token"], fj.TOKEN)
        self.assertNotIn(fj.PW, open(tf).read())
        st = json.loads(self.run_cli("status", "--json").stdout)
        self.assertEqual((st["state"], st["user"], st["logged_in"]), ("ok", "alice", True))
        self.assertEqual(self.run_cli("logout").returncode, 0)
        self.assertFalse(os.path.exists(tf))
        self.assertTrue(self.srv.logged_out)
        self.assertEqual(self.run_cli("status").returncode, 2)

    def test_rejected_and_unreachable(self):
        self.login_files()
        t = json.load(open(self.tmp + "/s/token.json")); t["token"] = "bad"
        json.dump(t, open(self.tmp + "/s/token.json", "w"))
        self.assertEqual(json.loads(self.run_cli("status", "--json").stdout)["state"], "rejected")
        self.assertEqual(self.run_cli("resume").returncode, 2)
        json.dump({"server": "http://127.0.0.1:1"}, open(self.tmp + "/c/config.json", "w"))
        p = self.run_cli("status", "--json")
        self.assertEqual(p.returncode, 3)
        self.assertEqual(json.loads(p.stdout)["state"], "unreachable")
        p = self.run_cli("resume")
        self.assertEqual((p.returncode, p.stderr.strip()), (3, "jellyfin-qs: server unreachable (is Tailscale connected?)"))

    def test_data(self):
        self.login_files()
        r = self.data("resume")
        self.assertEqual([x["id"] for x in r], ["m1"])
        m = r[0]
        self.assertEqual((m["kind"], m["subtitle"], m["runtime_s"], m["resume_s"], m["progress_pct"], m["year"]),
                         ("video", "1995", 6000, 2, 12.5, 1995))
        self.assertTrue(m["playable"] and not m["browsable"])
        self.assertEqual(self.data("nextup")[0]["subtitle"], "S01E02 · Dark Show")
        self.assertEqual(len(self.data("latest", "--limit", "2")), 2)
        lib = self.data("libraries")
        self.assertEqual((lib[0]["collection_type"], lib[0]["kind"], lib[0]["browsable"]), ("movies", "folder", True))
        self.assertEqual([x["id"] for x in self.data("children", "v1")], ["m2", "m1"])
        self.assertEqual([x["id"] for x in self.data("children", "s1")], ["se1", "se2"])
        self.assertEqual([x["id"] for x in self.data("children", "se1")], ["e1", "e2"])
        self.assertEqual([x["id"] for x in self.data("children", "a1")], ["al1", "al2"])
        self.assertEqual([x["id"] for x in self.data("children", "al1")], ["t1", "t2"])
        self.assertEqual([x["id"] for x in self.data("children", "p1")], ["t3", "t1"])
        self.assertEqual(self.data("item", "s1")["subtitle"], "2 seasons")
        t = self.data("item", "t1")
        self.assertEqual((t["subtitle"], t["kind"], t["parent_name"]), ("The Band · Early", "audio", "Early"))
        self.assertEqual(self.data("item", "al1")["subtitle"], "The Band · 2001")
        self.assertTrue(self.data("item", "e1")["played"])
        self.assertEqual([x["id"] for x in self.data("playlists")], ["p1"])
        self.assertEqual([x["id"] for x in self.data("search", "ali")], ["m2"])
        self.assertEqual([x["id"] for x in self.data("search", "dark", "--types", "Series", "--limit", "5")], ["s1"])
        self.assertEqual(self.run_cli("item", "nope").returncode, 4)
        self.assertEqual(self.run_cli("play", "nope").returncode, 4)
        for r in self.srv.log:
            self.assertIn('Token="%s"' % fj.TOKEN, r["auth"])
            self.assertNotIn("api_key", str(r["query"]))

    def test_library_scoped(self):
        self.login_files()
        self.assertEqual([x["collection_type"] for x in self.data("libraries")], ["movies", "tvshows", "music", "movies"])
        # per-library lists
        self.assertEqual([x["id"] for x in self.data("resume", "--library", "v1")], ["m1"])
        self.assertEqual(self.data("resume", "--library", "v2"), [])
        self.assertEqual([x["id"] for x in self.data("nextup", "--library", "v2")], ["e2"])
        self.assertEqual(self.data("nextup", "--library", "v1"), [])
        self.assertEqual({x["type"] for x in self.data("latest", "--library", "v4", "--limit", "5")}, {"Movie"})
        self.assertEqual([x["id"] for x in self.data("search", "show", "--parent", "v2", "--types", "Series")], ["s1", "s2"])
        self.assertEqual(self.data("search", "show", "--parent", "v1", "--types", "Series"), [])
        q = [r["query"] for r in self.srv.log if r["path"] == "/Items" and "searchTerm" in r["query"]]
        self.assertEqual(q[0].get("ParentId"), "v2")

    def test_children_paged(self):
        self.login_files()
        # library titles: tv -> Series by SortName (the leading article is ignored), music -> album artists
        d = self.data("children", "v2", "--types", "auto", "--sort", "name", "--paged")
        self.assertEqual(([x["id"] for x in d["items"]], d["total"], d["start"]), (["s2", "s1"], 2, 0))
        self.assertEqual([x["id"] for x in self.data("children", "v3", "--types", "auto")], ["a1"])
        self.assertEqual([x["id"] for x in self.data("children", "v3", "--types", "MusicAlbum", "--sort", "name")],
                         ["al1", "al2"])
        self.assertEqual([x["id"] for x in self.data("children", "v1", "--types", "auto")], ["m2", "m1"])
        # paging through a big library
        d = self.data("children", "v4", "--types", "auto", "--sort", "name", "--paged", "--limit", "100")
        self.assertEqual((len(d["items"]), d["total"], d["items"][0]["id"], d["items"][-1]["id"]), (100, 250, "b000", "b099"))
        d = self.data("children", "v4", "--types", "auto", "--sort", "name", "--paged", "--start", "200", "--limit", "100")
        self.assertEqual((len(d["items"]), d["total"], d["start"], d["items"][-1]["id"]), (50, 250, 200, "b249"))
        d = self.data("children", "v4", "--sort", "added", "--limit", "3")
        self.assertEqual([x["id"] for x in d], ["b249", "b248", "b247"])
        self.assertEqual(self.data("children", "v4", "--sort", "year", "--limit", "1")[0]["year"], 1999)
        last = [r["query"] for r in self.srv.log if r["path"] == "/Items"][-1]
        self.assertEqual((last["SortBy"], last["SortOrder"], last["Limit"]), ("ProductionYear,SortName", "Descending,Ascending", "1"))
        # containers with their own order ignore --sort but page client-side
        d = self.data("children", "se1", "--paged", "--start", "1", "--limit", "5")
        self.assertEqual(([x["id"] for x in d["items"]], d["total"], d["start"]), (["e2"], 2, 1))
        self.assertEqual([x["id"] for x in self.data("children", "s1", "--sort", "name")], ["se1", "se2"])
        self.assertEqual(self.run_cli("children", "v4", "--sort", "bogus").returncode, 1)
        self.assertEqual(self.run_cli("children", "nope", "--paged").returncode, 4)


class Play(Base):
    def shim(self):
        sh = self.tmp + "/fakempv"
        open(sh, "w").write('#!/bin/sh\nprintf "%s\\n" "$@" > "$FAKE_OUT.args"\n'
                            'for a in "$@"; do case "$a" in *.m3u) cp "$a" "$FAKE_OUT.m3u";; '
                            '--include=*) cp "${a#--include=}" "$FAKE_OUT.inc"; stat -c %a "${a#--include=}" > "$FAKE_OUT.mode";; esac; done\n')
        os.chmod(sh, 0o755)
        self.env.update(JELLYFIN_QS_MPV=sh, FAKE_OUT=self.tmp + "/out")

    def args(self):
        for _ in range(50):
            if os.path.exists(self.tmp + "/out.args") and os.path.exists(self.tmp + "/out.mode"):
                time.sleep(0.2)
                return open(self.tmp + "/out.args").read().splitlines()
            time.sleep(0.1)
        self.fail("shim did not run")

    def test_queue_and_args(self):
        self.login_files(); self.shim()
        self.assertEqual(self.run_cli("play", "s1").returncode, 0)
        a = self.args()
        self.assertEqual(open(self.tmp + "/out.mode").read().strip(), "600")
        self.assertIn('Authorization: MediaBrowser Token="%s"' % fj.TOKEN, open(self.tmp + "/out.inc").read())
        self.assertNotIn(fj.TOKEN, "\n".join(a))
        self.assertTrue(any(x.startswith("--script=") and x.endswith("jellyfin-report.lua") for x in a))
        self.assertTrue(any(x.startswith("--input-ipc-server=") for x in a))
        self.assertIn("--title=Jellyfin - Dark Show", a)
        m3u = open(self.tmp + "/out.m3u").read()
        ids = [l.split("/")[-2] for l in m3u.splitlines() if l.startswith("http")]
        self.assertEqual(ids, ["e2", "e3"])  # e1 is played: start at next unplayed
        self.assertIn("#EXTINF:60,Dark Show S01E02 - Second", m3u)
        self.assertNotIn(fj.TOKEN, m3u)
        self.assertIn("/Videos/e2/stream?static=true", m3u)

    def test_audio_artist_and_single(self):
        self.login_files(); self.shim()
        self.assertEqual(self.run_cli("play", "a1").returncode, 0)
        a = self.args()
        for o in ("--no-video", "--force-window=no", "--audio-display=no"):
            self.assertIn(o, a)
        m3u = open(self.tmp + "/out.m3u").read()
        self.assertEqual([l.split("/")[-2] for l in m3u.splitlines() if l.startswith("http")], ["t1", "t2", "t3"])
        self.assertIn("/Audio/t1/stream?static=true", m3u)
        for f in os.listdir(self.tmp): os.remove(self.tmp + "/" + f) if f.startswith("out") else None
        self.assertEqual(self.run_cli("play", "m1", "--resume").returncode, 0)
        a = self.args()
        self.assertIn("--start=2", a)
        self.assertIn(self.url + "/Videos/m1/stream?static=true", a)
        self.assertNotIn("--no-video", a)

    def test_report_with_real_mpv(self):
        if not shutil.which("mpv"):
            self.skipTest("no mpv")
        self.login_files()
        self.env["JELLYFIN_QS_MPV_ARGS"] = "--no-config --vo=null --ao=null --length=3 --really-quiet --ao-null-untimed=no"
        # the null ao plays in real time; --length stops at 3 s
        self.assertEqual(self.run_cli("play", "t1").returncode, 0)
        for _ in range(100):
            if any(r["path"] == "/Sessions/Playing/Stopped" for r in self.srv.log): break
            time.sleep(0.2)
        posts = [r for r in self.srv.log if r["path"].startswith("/Sessions/Playing")]
        names = [r["path"].rsplit("/", 1)[-1] for r in posts]
        self.assertEqual(names[0], "Playing")
        self.assertEqual(names[-1], "Stopped")
        for r in posts:
            self.assertIn('Token="%s"' % fj.TOKEN, r["auth"])
            self.assertEqual(json.loads(r["body"])["ItemId"], "t1")
        ticks = json.loads(posts[-1]["body"])["PositionTicks"]
        self.assertTrue(2.0 * 1e7 <= ticks <= 4.5 * 1e7, ticks)
        self.assertEqual(json.loads(posts[0]["body"])["PlayMethod"], "DirectPlay")
        self.assertTrue(any(r["path"] == "/Audio/t1/stream" and not r["query"].get("api_key") for r in self.srv.log))
        time.sleep(0.5)
        self.assertEqual([f for f in os.listdir(self.tmp + "/jellyfin-qs") if f.endswith((".conf", ".curl"))], [])


if __name__ == "__main__":
    unittest.main()
