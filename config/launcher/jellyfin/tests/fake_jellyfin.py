"""Minimal fake Jellyfin server for the jellyfin-qs tests."""
import io, json, threading, wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

TOKEN = "tok-test-0123456789abcdef"  # privacy-ok: fake test token
USER, PW, UID = "alice", "s3cret-pw", "u1"
T = 10000000


def it(i, name, typ, **kw):
    d = {"Id": i, "Name": name, "Type": typ, "UserData": {"Played": False}}
    d.update(kw)
    return d


ITEMS = [
    it("v1", "Movies", "CollectionFolder", CollectionType="movies"),
    it("m1", "Heat", "Movie", ProductionYear=1995, RunTimeTicks=6000 * T, ParentId="v1",
       UserData={"Played": False, "PlaybackPositionTicks": 2 * T, "PlayedPercentage": 12.5}),
    it("m2", "Alien", "Movie", ProductionYear=1979, RunTimeTicks=7000 * T, ParentId="v1"),
    it("s1", "Dark Show", "Series", ProductionYear=2017, ChildCount=2),
    it("se2", "Season 2", "Season", IndexNumber=2, SeriesName="Dark Show", ParentId="s1"),
    it("se1", "Season 1", "Season", IndexNumber=1, SeriesName="Dark Show", ParentId="s1"),
    it("e3", "Third", "Episode", IndexNumber=1, ParentIndexNumber=2, SeriesName="Dark Show", ParentId="se2",
       RunTimeTicks=60 * T),
    it("e2", "Second", "Episode", IndexNumber=2, ParentIndexNumber=1, SeriesName="Dark Show", ParentId="se1",
       RunTimeTicks=60 * T),
    it("e1", "First", "Episode", IndexNumber=1, ParentIndexNumber=1, SeriesName="Dark Show", ParentId="se1",
       RunTimeTicks=60 * T, UserData={"Played": True}),
    it("a1", "The Band", "MusicArtist"),
    it("al2", "Later", "MusicAlbum", ProductionYear=2005, AlbumArtist="The Band", AlbumArtistIds=["a1"]),
    it("al1", "Early", "MusicAlbum", ProductionYear=2001, AlbumArtist="The Band", AlbumArtistIds=["a1"]),
    it("t3", "Gamma", "Audio", Album="Later", Artists=["The Band"], IndexNumber=1, ParentIndexNumber=1,
       ParentId="al2", RunTimeTicks=5 * T),
    it("t2", "Beta", "Audio", Album="Early", Artists=["The Band"], IndexNumber=2, ParentIndexNumber=1,
       ParentId="al1", RunTimeTicks=5 * T),
    it("t1", "Alpha", "Audio", Album="Early", Artists=["The Band"], IndexNumber=1, ParentIndexNumber=1,
       ParentId="al1", RunTimeTicks=5 * T),
    it("p1", "Mix", "Playlist", MediaType="Audio", ChildCount=2),
]
PLAYLIST = {"p1": ["t3", "t1"]}
BY = {x["Id"]: x for x in ITEMS}


def wav_bytes():
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
        w.writeframes(b"\0\0" * 8000 * 8)
    return b.getvalue()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def reply(self, code, obj=None, raw=None, extra=None):
        body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b"")
        self.send_response(code)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self, method):
        u = urlsplit(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        srv = self.server
        srv.log.append({"method": method, "path": u.path, "query": q, "auth": self.headers.get("Authorization", ""),
                        "body": body.decode(errors="replace")})
        p = u.path
        if p == "/System/Info/Public":
            return self.reply(200, {"ServerName": "fake", "Version": "0"})
        if p == "/Users/AuthenticateByName":
            d = json.loads(body or b"{}")
            if d.get("Username") == USER and d.get("Pw") == PW:
                return self.reply(200, {"AccessToken": TOKEN, "User": {"Id": UID, "Name": USER}})
            return self.reply(401, {})
        if ("Token=\"%s\"" % srv.token) not in self.headers.get("Authorization", ""):
            return self.reply(401, {})
        if p == "/Users/Me":
            return self.reply(200, {"Id": UID, "Name": USER})
        if p == "/Sessions/Logout":
            srv.logged_out = True
            return self.reply(204)
        if p.startswith("/Sessions/Playing"):
            return self.reply(204)
        if p.startswith(("/Videos/", "/Audio/")):
            data = wav_bytes()
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                a, _, b = rng[6:].partition("-")
                a = int(a); b = int(b) if b else len(data) - 1
                return self.reply(206, raw=data[a:b + 1], extra={
                    "Content-Type": "audio/wav", "Content-Range": "bytes %d-%d/%d" % (a, b, len(data)),
                    "Accept-Ranges": "bytes"})
            return self.reply(200, raw=data, extra={"Content-Type": "audio/wav", "Accept-Ranges": "bytes"})
        if p in ("/UserItems/Resume",):
            return self.reply(200, {"Items": [x for x in ITEMS if (x["UserData"].get("PlaybackPositionTicks"))]})
        if p == "/Shows/NextUp":
            return self.reply(200, {"Items": [BY["e2"]]})
        if p == "/Items/Latest":
            return self.reply(200, [x for x in ITEMS if x["Type"] in ("Movie", "Episode")][:int(q.get("Limit", 9))])
        if p == "/UserViews":
            return self.reply(200, {"Items": [BY["v1"]]})
        if p.startswith("/Shows/") and p.endswith("/Seasons"):
            sid = p.split("/")[2]
            return self.reply(200, {"Items": [x for x in ITEMS if x.get("ParentId") == sid and x["Type"] == "Season"]})
        if p.startswith("/Playlists/") and p.endswith("/Items"):
            return self.reply(200, {"Items": [BY[i] for i in PLAYLIST[p.split("/")[2]]]})
        if p == "/Items":
            r = ITEMS
            if "Ids" in q: r = [x for x in r if x["Id"] in q["Ids"].split(",")]
            if "ParentId" in q: r = [x for x in r if x.get("ParentId") == q["ParentId"]]
            if "AlbumArtistIds" in q: r = [x for x in r if q["AlbumArtistIds"] in x.get("AlbumArtistIds", [])]
            if "IncludeItemTypes" in q: r = [x for x in r if x["Type"] in q["IncludeItemTypes"].split(",")]
            if "searchTerm" in q: r = [x for x in r if q["searchTerm"].lower() in x["Name"].lower()]
            return self.reply(200, {"Items": r[:int(q.get("Limit", 1000))], "TotalRecordCount": len(r)})
        return self.reply(404, {})

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")


def start():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    srv.log, srv.token, srv.logged_out = [], TOKEN, False
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv
