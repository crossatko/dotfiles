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
    it("v2", "Shows", "CollectionFolder", CollectionType="tvshows"),
    it("v3", "Music", "CollectionFolder", CollectionType="music"),
    it("s1", "Dark Show", "Series", ProductionYear=2017, ChildCount=2, ParentId="v2"),
    it("s2", "A Calm Show", "Series", SortName="Calm Show", ProductionYear=2020, ParentId="v2"),
    it("se2", "Season 2", "Season", IndexNumber=2, SeriesName="Dark Show", ParentId="s1"),
    it("se1", "Season 1", "Season", IndexNumber=1, SeriesName="Dark Show", ParentId="s1"),
    it("e3", "Third", "Episode", IndexNumber=1, ParentIndexNumber=2, SeriesName="Dark Show", ParentId="se2",
       RunTimeTicks=60 * T),
    it("e2", "Second", "Episode", IndexNumber=2, ParentIndexNumber=1, SeriesName="Dark Show", ParentId="se1",
       RunTimeTicks=60 * T),
    it("e1", "First", "Episode", IndexNumber=1, ParentIndexNumber=1, SeriesName="Dark Show", ParentId="se1",
       RunTimeTicks=60 * T, UserData={"Played": True}),
    it("a1", "The Band", "MusicArtist"),
    it("al2", "Later", "MusicAlbum", ProductionYear=2005, AlbumArtist="The Band", AlbumArtistIds=["a1"], ParentId="v3"),
    it("al1", "Early", "MusicAlbum", ProductionYear=2001, AlbumArtist="The Band", AlbumArtistIds=["a1"], ParentId="v3"),
    it("t3", "Gamma", "Audio", Album="Later", Artists=["The Band"], IndexNumber=1, ParentIndexNumber=1,
       ParentId="al2", RunTimeTicks=5 * T),
    it("t2", "Beta", "Audio", Album="Early", Artists=["The Band"], IndexNumber=2, ParentIndexNumber=1,
       ParentId="al1", RunTimeTicks=5 * T),
    it("t1", "Alpha", "Audio", Album="Early", Artists=["The Band"], IndexNumber=1, ParentIndexNumber=1,
       ParentId="al1", RunTimeTicks=5 * T),
    it("p1", "Mix", "Playlist", MediaType="Audio", ChildCount=2),
]
# a big movie library for paging: 250 movies, created in reverse name order
BIG = 250
ITEMS += [it("v4", "Big", "CollectionFolder", CollectionType="movies")] + [
    it("b%03d" % i, "Film %03d" % i, "Movie", ParentId="v4", ProductionYear=1900 + i % 100, DateCreated="2020-01-01T00:00:%03d" % i)
    for i in range(BIG - 1, -1, -1)]
PLAYLIST = {"p1": ["t3", "t1"]}
BY = {x["Id"]: x for x in ITEMS}
VIEWS = ["v1", "v2", "v3", "v4"]


def under(x, pid):
    """x is a descendant of pid"""
    while x.get("ParentId"):
        if x["ParentId"] == pid:
            return True
        x = BY.get(x["ParentId"], {})
    return False


def scoped(r, q):
    return [x for x in r if under(x, q["ParentId"])] if q.get("ParentId") else r


def page(r, q):
    """SortBy / SortOrder (first order applies to the first key, the rest ascending), StartIndex, Limit"""
    if "SortBy" in q:
        keys = q["SortBy"].split(",")
        desc = q.get("SortOrder", "").split(",")[0] == "Descending"
        def k(x, f):
            return ((x.get("SortName") or x["Name"]).lower() if f == "SortName" else x.get(f) or 0)
        r = sorted(r, key=lambda x: tuple(k(x, f) for f in keys[1:]))
        r = sorted(r, key=lambda x: k(x, keys[0]), reverse=desc)
    st = int(q.get("StartIndex", 0))
    return {"Items": r[st:st + int(q.get("Limit", 100000))], "TotalRecordCount": len(r)}


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
            return self.reply(200, {"Items": scoped([x for x in ITEMS if (x["UserData"].get("PlaybackPositionTicks"))], q)})
        if p == "/Shows/NextUp":
            return self.reply(200, {"Items": scoped([BY["e2"]], q)})
        if p == "/Items/Latest":
            return self.reply(200, scoped([x for x in ITEMS if x["Type"] in ("Movie", "Episode")], q)[:int(q.get("Limit", 9))])
        if p == "/UserViews":
            return self.reply(200, {"Items": [BY[v] for v in VIEWS]})
        if p == "/Artists/AlbumArtists":
            albums = scoped([x for x in ITEMS if x["Type"] == "MusicAlbum"], q)
            ids = {a for x in albums for a in x.get("AlbumArtistIds", [])}
            return self.reply(200, page([x for x in ITEMS if x["Id"] in ids], q))
        if p.startswith("/Shows/") and p.endswith("/Seasons"):
            sid = p.split("/")[2]
            return self.reply(200, {"Items": [x for x in ITEMS if x.get("ParentId") == sid and x["Type"] == "Season"]})
        if p.startswith("/Playlists/") and p.endswith("/Items"):
            return self.reply(200, {"Items": [BY[i] for i in PLAYLIST[p.split("/")[2]]]})
        if p == "/Items":
            r = ITEMS
            if "Ids" in q: r = [x for x in r if x["Id"] in q["Ids"].split(",")]
            if "ParentId" in q:
                r = scoped(r, q) if q.get("Recursive") == "true" else [x for x in r if x.get("ParentId") == q["ParentId"]]
            if "AlbumArtistIds" in q: r = [x for x in r if q["AlbumArtistIds"] in x.get("AlbumArtistIds", [])]
            if "IncludeItemTypes" in q: r = [x for x in r if x["Type"] in q["IncludeItemTypes"].split(",")]
            if "searchTerm" in q: r = [x for x in r if q["searchTerm"].lower() in x["Name"].lower()]
            return self.reply(200, page(r, q))
        return self.reply(404, {})

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")


def start():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    srv.log, srv.token, srv.logged_out = [], TOKEN, False
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv
