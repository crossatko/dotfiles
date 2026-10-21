"""Tests for bin/webapp-install against a local stub HTTP server (127.0.0.1 only, throwaway XDG_DATA_HOME).

Run: python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import http.server
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zlib

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "webapp-install")


def png(size, rgb=(200, 40, 40)):
    row = b"\x00" + bytes(rgb + (255,)) * size
    raw = zlib.compress(row * size)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def ico(size):
    p = png(size)
    return struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(p), 22) + p


SVG = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#2a6"/></svg>'

ROUTES = {}          # path -> (status, content type, body | callable, extra headers)
BROWSER_ONLY = set() # paths that answer 400 unless the User-Agent looks like a browser (seen on a real messaging site)


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        r = ROUTES.get(self.path.split("?")[0])
        if r is None:
            self.send_response(404)
            self.end_headers()
            return
        status, typ, body, hdrs = r
        if self.path.split("?")[0] in BROWSER_ONLY and "Chrome/" not in (self.headers.get("User-Agent") or ""):
            status, typ, body, hdrs = 400, "text/html", b"<html><title>Error 400</title></html>", {}
        if callable(body):
            body = body()
        self.send_response(status)
        self.send_header("Content-Type", typ)
        for k, v in hdrs.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass


def read(p):
    with open(p) as f:
        return f.read()


def page(head, title="Example App - Home"):
    return ("<!doctype html><html><head><title>%s</title>%s</head><body>hi</body></html>" % (title, head)).encode()


class WebappTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        cls.srv.daemon_threads = True
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_address[1]

        cls.cdn = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)   # a second origin = a static-asset host
        threading.Thread(target=cls.cdn.serve_forever, daemon=True).start()
        cls.cdn_host = "127.0.0.1:%d" % cls.cdn.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.cdn.shutdown()

    def setUp(self):
        ROUTES.clear()
        BROWSER_ONLY.clear()
        self.tmp = tempfile.TemporaryDirectory()
        self.data = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        env = dict(os.environ, XDG_DATA_HOME=self.data, WEBAPP_TIMEOUT="1.5", HOME=self.data)
        r = subprocess.run([sys.executable, "-I", HELPER] + list(args), capture_output=True, text=True, env=env, timeout=60)
        return r.returncode, json.loads(r.stdout or "{}")

    def install(self, path="/", name="Example"):
        rc, out = self.run_helper("install", self.base + path, "--name", name)
        self.assertEqual(rc, 0, out)
        return out

    def icon_file(self, out):
        self.assertTrue(out["iconFiles"], out)
        return out["iconFiles"][0]

    def test_manifest_icon_and_name(self):
        ROUTES["/"] = (200, "text/html", page('<link rel="manifest" href="/app.webmanifest"><link rel="icon" href="/small.png" sizes="16x16">'), {})
        ROUTES["/app.webmanifest"] = (200, "application/manifest+json", json.dumps(
            {"name": "Example Application", "short_name": "ExApp", "icons": [{"src": "/i192.png", "sizes": "192x192"}, {"src": "/i512.png", "sizes": "512x512"}]}).encode(), {})
        ROUTES["/i192.png"] = (200, "image/png", png(192), {})
        ROUTES["/i512.png"] = (200, "image/png", png(512), {})
        ROUTES["/small.png"] = (200, "image/png", png(16), {})
        rc, p = self.run_helper("probe", self.base + "/")
        self.assertEqual(rc, 0)
        self.assertEqual(p["name"], "ExApp")
        self.assertTrue(p["reachable"])
        out = self.install(name="ExApp")
        self.assertTrue(out["iconSource"].endswith("/i512.png"), out)
        self.assertIn("X-Webapp-Icon-Source=%s/i512.png\n" % self.base, read(out["desktop"]))
        self.assertRegex(self.icon_file(out), r"/512x512/apps/webapp-exapp\.[0-9a-f]{8}\.png$")
        d = read(out["desktop"])
        self.assertIn("Icon=%s\n" % self.icon_file(out), d)              # absolute path, no theme lookup
        self.assertIn('Exec=brave --app="%s/"' % self.base, d)
        self.assertIn("StartupWMClass=brave-127.0.0.1__-Default", d)
        self.assertTrue(out["desktop"].endswith("/applications/webapp_exapp.desktop"))
        self.assertEqual(out["warnings"], [])

    def test_apple_touch_icon_only(self):
        ROUTES["/app/"] = (200, "text/html", page('<link rel="apple-touch-icon" href="touch.png">', "Inbox | Example Mail"), {})
        ROUTES["/app/touch.png"] = (200, "image/png", png(180), {})
        rc, p = self.run_helper("probe", self.base + "/app/")
        self.assertEqual(p["name"], "Inbox")
        out = self.install("/app/", "Example Mail")
        self.assertRegex(self.icon_file(out), r"/128x128/apps/webapp-example_mail\.[0-9a-f]{8}\.png$")
        self.assertEqual(out["wmClass"], "brave-127.0.0.1__app_-Default")

    def test_favicon_ico_only(self):
        ROUTES["/"] = (200, "text/html", page(""), {})
        ROUTES["/favicon.ico"] = (200, "image/x-icon", ico(64), {})
        out = self.install()
        self.assertTrue(out["iconSource"].endswith("/favicon.ico"), out)
        self.assertIn("/64x64/apps/", self.icon_file(out))

    def test_nothing_gives_letter_tile(self):
        ROUTES["/"] = (200, "text/html", page(""), {})
        out = self.install(name="Zeta")
        self.assertEqual(out["iconSource"], "letter tile")
        files = out["iconFiles"]
        self.assertTrue(any(re.search(r"/scalable/apps/webapp-zeta\.[0-9a-f]{8}\.svg$", f) for f in files), files)
        self.assertIn(">Z</text>", read([f for f in files if f.endswith(".svg")][0]))

    def test_svg_icon(self):
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" type="image/svg+xml" href="/logo.svg"><link rel="icon" href="/f32.png" sizes="32x32">'), {})
        ROUTES["/logo.svg"] = (200, "image/svg+xml", SVG, {})
        ROUTES["/f32.png"] = (200, "image/png", png(32), {})
        out = self.install()
        self.assertTrue(out["iconSource"].endswith("/logo.svg"), out)
        self.assertTrue(any(re.search(r"/scalable/apps/webapp-example\.[0-9a-f]{8}\.svg$", f) for f in out["iconFiles"]))

    def test_oversized_icon_is_skipped(self):
        big = png(64) + b"\0" * (5 << 20)
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" href="/huge.png" sizes="512x512"><link rel="icon" href="/ok.png" sizes="96x96">'), {})
        ROUTES["/huge.png"] = (200, "image/png", big, {})
        ROUTES["/ok.png"] = (200, "image/png", png(96), {})
        out = self.install()
        self.assertTrue(out["iconSource"].endswith("/ok.png"), out)

    def test_redirect_loop(self):
        ROUTES["/"] = (302, "text/html", b"", {"Location": "/loop"})
        ROUTES["/loop"] = (302, "text/html", b"", {"Location": "/"})
        rc, p = self.run_helper("probe", self.base + "/")
        self.assertEqual(rc, 0)
        self.assertFalse(p["reachable"])
        self.assertIn("redirect", p["error"])
        out = self.install(name="Loop")
        self.assertEqual(out["iconSource"], "letter tile")
        self.assertTrue(out["warnings"])

    def test_redirect_to_file_scheme_refused(self):
        ROUTES["/"] = (302, "text/html", b"", {"Location": "file:///etc/passwd"})
        rc, p = self.run_helper("probe", self.base + "/")
        self.assertFalse(p["reachable"])

    def test_timeout(self):
        ROUTES["/"] = (200, "text/html", lambda: (time.sleep(3), page(""))[1], {})
        t = time.time()
        rc, p = self.run_helper("probe", self.base + "/")
        self.assertLess(time.time() - t, 6)
        self.assertFalse(p["reachable"])
        self.assertIn("timed out", p["error"])

    def test_reinstall_replaces_entry_and_icon(self):
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" href="/a.png" sizes="256x256">'), {})
        ROUTES["/a.png"] = (200, "image/png", png(256), {})
        first = self.install(name="Same")
        ROUTES["/a.png"] = (200, "image/png", png(64), {})
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" href="/a.png" sizes="64x64">'), {})
        second = self.install(name="Same")
        self.assertEqual(first["desktop"], second["desktop"])
        self.assertFalse(os.path.exists(first["iconFiles"][0]))      # the old 256 px file is gone
        self.assertIn("/64x64/", second["iconFiles"][0])

    def test_bad_input(self):
        for u in ("javascript:alert(1)", "file:///etc/passwd", "not a url", ""):
            rc, out = self.run_helper("probe", u)
            self.assertEqual(rc, 1, u)
            self.assertTrue(out.get("error"))
        rc, out = self.run_helper("install", self.base + "/", "--name", "!!!")
        self.assertEqual(rc, 1)

    def test_exec_quoting(self):
        ROUTES["/q"] = (200, "text/html", page(""), {})
        rc, out = self.run_helper("install", self.base + "/q?a=1&b=%20x", "--name", "Quote")
        self.assertEqual(rc, 0, out)
        d = read(out["desktop"])
        self.assertIn('Exec=brave --app="%s/q?a=1&b=%%%%20x"' % self.base, d)

    # ---- real-world icon causes (2026-10-21; placeholders) ---------------------------------------------------------
    def test_browser_only_page_with_cross_origin_manifest_icons(self):
        # page rejects a non-browser UA (400), declares a manifest whose icons are protocol-relative on another host,
        # the origin has no /favicon.ico: before the fix only the letter tile was left
        ROUTES["/web/"] = (200, "text/html", page('<link rel="manifest" href="/web/manifest.json"><link rel="icon" sizes="96x96" href="//%s/img/i96.png">' % self.cdn_host, "Example Messages"), {})
        BROWSER_ONLY.add("/web/")
        ROUTES["/web/manifest.json"] = (200, "application/json", json.dumps({"name": "Example Messages", "icons": [
            {"src": "//%s/img/round_192.png" % self.cdn_host, "sizes": "192x192", "type": "image/png"},
            {"src": "//%s/img/round_512.png" % self.cdn_host, "sizes": "512x512", "type": "image/png"}]}).encode(), {})
        ROUTES["/img/round_512.png"] = (200, "image/png", png(512), {})
        ROUTES["/img/round_192.png"] = (200, "image/png", png(192), {})
        ROUTES["/img/i96.png"] = (200, "image/png", png(96), {})
        rc, p = self.run_helper("probe", self.base + "/web/")
        self.assertTrue(p["reachable"], p)
        out = self.install("/web/", "Messages")
        self.assertEqual(out["iconSource"], "http://%s/img/round_512.png" % self.cdn_host)

    def test_any_beats_maskable_at_same_size(self):
        # manifest lists maskable icons first (full-bleed squares), then plain ones of the same sizes
        ROUTES["/"] = (200, "text/html", page('<link rel="manifest" href="//%s/pwa.webmanifest">' % self.cdn_host), {})
        ROUTES["/pwa.webmanifest"] = (200, "application/manifest+json", json.dumps({"icons": [
            {"purpose": "maskable", "src": "/m512.png", "sizes": "512x512"}, {"src": "/a512.png", "sizes": "512x512"},
            {"purpose": "maskable", "src": "/m192.png", "sizes": "192x192"}]}).encode(), {})
        ROUTES["/m512.png"] = (200, "image/png", png(512, (10, 10, 10)), {})
        ROUTES["/a512.png"] = (200, "image/png", png(512, (30, 30, 200)), {})
        ROUTES["/m192.png"] = (200, "image/png", png(192), {})
        out = self.install()
        self.assertTrue(out["iconSource"].endswith("/a512.png"), out)

    def test_full_bleed_icon_gets_rounded_corners(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("no PIL")
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" href="/sq.png" sizes="256x256">'), {})
        ROUTES["/sq.png"] = (200, "image/png", png(256, (0, 0, 0)), {})
        out = self.install()
        im = Image.open(self.icon_file(out)).convert("RGBA")
        self.assertEqual(im.getpixel((0, 0))[3], 0)                  # corner now transparent
        self.assertEqual(im.getpixel((128, 128))[3], 255)

    def test_maskable_only_is_still_used(self):
        ROUTES["/"] = (200, "text/html", page('<link rel="manifest" href="/m.json">'), {})
        ROUTES["/m.json"] = (200, "application/json", json.dumps({"icons": [{"purpose": "maskable", "src": "/m.png", "sizes": "512x512"}]}).encode(), {})
        ROUTES["/m.png"] = (200, "image/png", png(512), {})
        out = self.install()
        self.assertTrue(out["iconSource"].endswith("/m.png"), out)

    def test_reinstall_new_icon_path_and_old_style_files_removed(self):
        hic = os.path.join(self.data, "icons", "hicolor")
        for d in ("256x256", "scalable"):                            # files of an install before the hashed names
            os.makedirs(os.path.join(hic, d, "apps"))
        old = [os.path.join(hic, "256x256", "apps", "webapp-same.png"), os.path.join(hic, "scalable", "apps", "webapp-same.svg")]
        other = os.path.join(hic, "256x256", "apps", "webapp-samething.png")
        for f in old + [other]:
            with open(f, "wb") as fh:
                fh.write(png(8))
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" href="/a.png" sizes="256x256">'), {})
        ROUTES["/a.png"] = (200, "image/png", png(256, (1, 2, 3)), {})
        first = self.install(name="Same")
        self.assertFalse(any(os.path.exists(f) for f in old))
        self.assertTrue(os.path.exists(other))                       # another app's icon
        ROUTES["/a.png"] = (200, "image/png", png(256, (200, 2, 3)), {})
        second = self.install(name="Same")
        self.assertNotEqual(first["icon"], second["icon"])          # new path = new cache key in running shells
        self.assertFalse(os.path.exists(first["icon"]))
        self.assertIn("Icon=%s\n" % second["icon"], read(second["desktop"]))

    # ---- name is used exactly (bug 2026-10-21: the manifest name replaced the typed one in the launcher) ----------
    def test_typed_name_wins_over_manifest_and_overwrites_same_slug(self):
        ROUTES["/chat/"] = (200, "text/html", page('<link rel="manifest" href="/chat/m.json">', "Example Chat Web"), {})
        ROUTES["/chat/m.json"] = (200, "application/json", json.dumps({"name": "Example Chat Web"}).encode(), {})
        apps = os.path.join(self.data, "applications")
        os.makedirs(apps)
        old = os.path.join(apps, "webapp_examplechat.desktop")      # an entry from the old shell function, same slug
        with open(old, "w") as f:
            f.write('[Desktop Entry]\nName=ExampleChat\nExec=brave --app="https://chat.example.com/"\nType=Application\nIcon=brave\n')
        rc, p = self.run_helper("probe", self.base + "/chat/")
        self.assertEqual(p["name"], "Example Chat Web")             # only a suggestion
        out = self.install("/chat/", "ExampleChat")
        self.assertEqual(out["desktop"], old)                        # same file replaced, no second entry
        d = read(old)
        self.assertIn("Name=ExampleChat\n", d)
        self.assertRegex(d, r"\nIcon=/.*/webapp-examplechat\.[0-9a-f]{8}\.png\n")
        self.assertIn("X-Webapp-Installer=1", d)
        self.assertEqual([f for f in os.listdir(apps) if f.endswith(".desktop")], ["webapp_examplechat.desktop"])

    def test_name_case_and_spaces(self):
        ROUTES["/"] = (200, "text/html", page(""), {})
        out = self.install(name="  Example  Chat ")
        self.assertTrue(out["desktop"].endswith("/webapp_example_chat.desktop"), out)
        self.assertIn("Name=Example Chat\n", read(out["desktop"]))

    # ---- uninstall ---------------------------------------------------------------------------------------------
    def test_uninstall_removes_entry_and_icons_only(self):
        ROUTES["/"] = (200, "text/html", page('<link rel="icon" type="image/svg+xml" href="/logo.svg">'), {})
        ROUTES["/logo.svg"] = (200, "image/svg+xml", SVG, {})
        out = self.install(name="Gone")
        keep = self.install(name="Kept")
        other = os.path.join(self.data, "applications", "firefox.desktop")
        with open(other, "w") as f:
            f.write("[Desktop Entry]\nName=Firefox\nExec=firefox\nType=Application\n")
        stray = os.path.join(self.data, "icons", "hicolor", "256x256", "apps", "webapp-gone-extra.png")
        with open(stray, "wb") as f:
            f.write(png(8))
        rc, r = self.run_helper("uninstall", "gone")
        self.assertEqual(rc, 0, r)
        self.assertIn(out["desktop"], r["removed"])
        for f in out["iconFiles"]:
            self.assertFalse(os.path.exists(f), f)
            self.assertIn(f, r["removed"])
        self.assertTrue(os.path.exists(keep["desktop"]))
        self.assertTrue(all(os.path.exists(f) for f in keep["iconFiles"]))
        self.assertTrue(os.path.exists(other))
        self.assertTrue(os.path.exists(stray))                       # only the exact icon name goes
        rc, r = self.run_helper("uninstall", "gone")
        self.assertEqual(rc, 4)                                      # missing entry

    def test_uninstall_old_shell_function_entry(self):
        apps = os.path.join(self.data, "applications")
        os.makedirs(apps)
        old = os.path.join(apps, "webapp_oldchat.desktop")
        with open(old, "w") as f:
            f.write('[Desktop Entry]\nName=OldChat\nExec=brave --app="https://chat.example.com/"\nIcon=brave\nType=Application\n')
        rc, r = self.run_helper("uninstall", "oldchat")
        self.assertEqual(rc, 0, r)
        self.assertFalse(os.path.exists(old))

    def test_uninstall_rejects_bad_slugs_and_non_webapps(self):
        apps = os.path.join(self.data, "applications")
        os.makedirs(apps)
        outside = os.path.join(self.data, "secret.desktop")
        with open(outside, "w") as f:
            f.write('[Desktop Entry]\nExec=brave --app="https://x.example/"\n')
        for bad in ("../secret", "..", "a/b", "", "Upper", "-x", "a" * 80):
            rc, r = self.run_helper("uninstall", bad)
            self.assertEqual(rc, 1, bad)
        self.assertTrue(os.path.exists(outside))
        plain = os.path.join(apps, "webapp_plain.desktop")           # webapp_ name but not a browser --app entry
        with open(plain, "w") as f:
            f.write("[Desktop Entry]\nName=Plain\nExec=plain-tool\nType=Application\n")
        rc, r = self.run_helper("uninstall", "plain")
        self.assertEqual(rc, 1)
        self.assertTrue(os.path.exists(plain))
        os.symlink(outside, os.path.join(apps, "webapp_link.desktop"))  # symlink pointing outside
        rc, r = self.run_helper("uninstall", "link")
        self.assertEqual(rc, 1)
        self.assertTrue(os.path.exists(outside))


if __name__ == "__main__":
    unittest.main()
