"""Tests for bin/browser-tab-url (Chromium session file -> the playing tab's YouTube / Twitch URL).

python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import os
import sqlite3
import struct
import subprocess
import sys
import tempfile
import unittest

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "browser-tab-url")


def pstr(s, wide=False):
    raw = s.encode("utf-16-le" if wide else "utf-8")
    n = len(s.encode("utf-16-le")) // 2 if wide else len(raw)
    return struct.pack("<i", n) + raw + b"\0" * (((len(raw) + 3) & ~3) - len(raw))


def record(cid, payload):
    return struct.pack("<HB", len(payload) + 1, cid) + payload


def nav(tab, idx, url, title):
    body = struct.pack("<ii", tab, idx) + pstr(url) + pstr(title, True) + pstr("") + struct.pack("<i", 0)
    return record(6, struct.pack("<i", len(body)) + body)


def snss(records):
    """A minimal Chromium session file (SNSS v3): header + commands (also used by the nested Send-to-TV test)."""
    return b"SNSS" + struct.pack("<i", 3) + b"".join(records)


def write_profile(config, records, browser_dir="BraveSoftware/Brave-Browser", profile="Default"):
    d = os.path.join(config, browser_dir, profile, "Sessions")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Session_13400000000000000"), "wb") as f:
        f.write(snss(records))


def write_history(config, rows, browser_dir="BraveSoftware/Brave-Browser", profile="Default"):
    """A Chromium History database with the `urls` columns the helper reads: rows = [(url, title, last_visit_time)]."""
    d = os.path.join(config, browser_dir, profile)
    os.makedirs(d, exist_ok=True)
    con = sqlite3.connect(os.path.join(d, "History"))
    con.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, "
                "typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
    con.executemany("INSERT INTO urls (url, title, last_visit_time) VALUES (?, ?, ?)", rows)
    con.commit()
    con.close()


class BrowserTabUrl(unittest.TestCase):
    def run_bin(self, config, *args):
        env = {"PATH": os.environ.get("PATH", ""), "HOME": config, "XDG_CONFIG_HOME": config}
        return subprocess.run([sys.executable, "-I", BIN] + list(args), env=env, capture_output=True, text=True, timeout=10).stdout.strip()

    def test_youtube_tab_by_title(self):
        with tempfile.TemporaryDirectory() as c:
            write_profile(c, [nav(1, 0, "https://www.youtube.com/", "YouTube"),
                              nav(1, 1, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5s", "(2) Never Gonna - YouTube"),
                              nav(2, 0, "https://example.org/", "Never Gonna notes")])
            self.assertEqual(self.run_bin(c, "brave", "Never Gonna"), "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5s")

    def test_selected_navigation_wins(self):
        with tempfile.TemporaryDirectory() as c:
            write_profile(c, [nav(1, 0, "https://www.youtube.com/watch?v=AAAAAAAAAAA", "Song - YouTube"),
                              nav(1, 1, "https://www.youtube.com/watch?v=BBBBBBBBBBB", "Song - YouTube"),
                              record(7, struct.pack("<ii", 1, 0))])
            self.assertEqual(self.run_bin(c, "brave", "Song"), "https://www.youtube.com/watch?v=AAAAAAAAAAA")

    def test_closed_tab_ignored_and_twitch_by_channel(self):
        with tempfile.TemporaryDirectory() as c:
            write_profile(c, [nav(1, 0, "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Gone - YouTube"),
                              record(16, struct.pack("<iq", 1, 0)),
                              nav(3, 0, "https://www.twitch.tv/streamer", "Streamer - Twitch")])
            self.assertEqual(self.run_bin(c, "brave", "Gone"), "")
            self.assertEqual(self.run_bin(c, "brave", "Stream title nobody has", "Streamer"), "https://www.twitch.tv/streamer")

    def test_only_allowed_urls_and_bad_input(self):
        with tempfile.TemporaryDirectory() as c:
            write_profile(c, [nav(1, 0, "https://private.example/watch", "Secret - Site")])
            self.assertEqual(self.run_bin(c, "brave", "Secret"), "")
            self.assertEqual(self.run_bin(c, "firefox", "Secret"), "")
            self.assertEqual(self.run_bin(c, "brave", ""), "")
        with tempfile.TemporaryDirectory() as c:
            d = os.path.join(c, "chromium", "Default", "Sessions")
            os.makedirs(d)
            with open(os.path.join(d, "Session_1"), "wb") as f:
                f.write(b"SNSS" + struct.pack("<i", 3) + b"\xff\xff\x06garbage")
            self.assertEqual(self.run_bin(c, "chromium", "x"), "")

    def test_stale_session_falls_back_to_history(self):
        # Brave's shape: the session file still has the previous video (in-page navigation not written yet), the MPRIS
        # title has an apostrophe and a "|", the artist has "&"; History already has the playing video
        title = "Rainy night but it's lofi beats | Mix"
        with tempfile.TemporaryDirectory() as c:
            write_profile(c, [nav(1, 0, "https://www.youtube.com/watch?v=AAAAAAAAAAA", "Snowy day but it's lofi beats | Mix - YouTube")])
            write_history(c, [("https://www.youtube.com/watch?v=AAAAAAAAAAA", "Snowy day but it's lofi beats | Mix - YouTube", 100),
                              ("https://www.youtube.com/watch?v=BBBBBBBBBBB&list=RD1", title + " - YouTube", 200),
                              ("https://www.youtube.com/watch?v=CCCCCCCCCCC", title + " - YouTube", 150),
                              ("https://private.example/" + title, title, 300)])
            self.assertEqual(self.run_bin(c, "brave", title, "beats & bits"), "https://www.youtube.com/watch?v=BBBBBBBBBBB&list=RD1")
            # the open tab wins over History when the session file has it
            write_profile(c, [nav(1, 0, "https://www.youtube.com/watch?v=DDDDDDDDDDD", title + " - YouTube")])
            self.assertEqual(self.run_bin(c, "brave", title, "beats & bits"), "https://www.youtube.com/watch?v=DDDDDDDDDDD")

    def test_history_non_ascii_and_unreadable(self):
        with tempfile.TemporaryDirectory() as c:
            write_history(c, [("https://www.youtube.com/watch?v=EEEEEEEEEEE", "ÉTÉ — 夏の歌 «live» - YouTube", 1)])
            self.assertEqual(self.run_bin(c, "brave", "été — 夏の歌 «LIVE»"), "https://www.youtube.com/watch?v=EEEEEEEEEEE")
        with tempfile.TemporaryDirectory() as c:
            d = os.path.join(c, "BraveSoftware/Brave-Browser", "Default")
            os.makedirs(d)
            with open(os.path.join(d, "History"), "wb") as f:
                f.write(b"not a database")
            self.assertEqual(self.run_bin(c, "brave", "x"), "")


if __name__ == "__main__":
    unittest.main()
