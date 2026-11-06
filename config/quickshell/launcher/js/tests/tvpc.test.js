const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const P = load("TvPc.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));

const YT = "dQw4w9WgXcQ";
const JF = "0123456789abcdef0123456789abcdef";
const NOW = 1000000;
const env = { twitchApp: "/opt/twitch-qs-mpv", jellyfin: ["sh", "-c", "exec jellyfin-qs \"$@\"", "sh"] };
const sent = (o) => Object.assign({ sent: true, title: "Video", subtitle: "", tvTitle: "", position: -1, positionAt: 0, duration: -1, playing: true }, o);

test("sent YouTube: the TV's position (extrapolated while playing), back to the player it came from", () => {
    const t = P.resolve(sent({ kind: "youtube", ref: YT, origin: "browser", position: 100, positionAt: NOW - 5000, duration: 300 }), NOW);
    eq([t.state, t.kind, t.ref, t.start, t.how], ["ready", "youtube", YT, 105, "exact"]);
    eq(P.command(t, env), { argv: ["xdg-open", "https://www.youtube.com/watch?v=" + YT + "&t=105s"], player: "browser" });
    const m = P.resolve(sent({ kind: "youtube", ref: YT, origin: "mpv", position: 100, positionAt: NOW - 5000, playing: false }), NOW);
    eq(m.start, 100);                                                // paused: no extrapolation
    eq(P.command(m, env).argv, ["mpv", "--start=100", "--", "https://www.youtube.com/watch?v=" + YT + "&t=100s"]);
    // no position from the TV: from the start, said so
    const z = P.resolve(sent({ kind: "youtube", ref: YT }), NOW);
    eq([z.start, z.how], [0, "start"]);
    // clamped to the length
    eq(P.resolve(sent({ kind: "youtube", ref: YT, position: 299, positionAt: NOW - 60000, duration: 300 }), NOW).start, 300);
});

test("sent YouTube, but the TV moved on to another video: an exact title search", () => {
    const t = P.resolve(sent({ kind: "youtube", ref: YT, title: "First", tvTitle: "Second one", subtitle: "Sent chan", tvArtist: "Chan", position: 10, positionAt: NOW, duration: 200 }), NOW);
    eq([t.state, t.lookup, t.want], ["lookup", "youtube", { title: "Second one", artist: "Chan", duration: 200 }]);   // the TV's channel, not the sent one
    // the same title as the browser showed it is the same video
    eq(P.resolve(sent({ kind: "youtube", ref: YT, title: "(3) First - YouTube", tvTitle: "First" }), NOW).state, "ready");
    eq(P.settle(t, "AAAAAAAAAAA"), { state: "ready", kind: "youtube", ref: "AAAAAAAAAAA", start: 10, how: "exact", lookup: "", want: null, origin: "", reason: "" });
    eq([P.settle(t, "").state, P.settle(t, "").ref], ["ready", YT]);           // no match: the video we sent
    const a = P.resolve({ sent: false, appId: "2C6A6E3D", app: "YouTube", title: "Me", subtitle: "x", position: -1 }, NOW);
    eq(P.settle(a, "").state, "none");
});

test("sent Twitch: live joins live; a past broadcast at the TV's position (else the account's); a clip from 0", () => {
    const live = P.resolve(sent({ kind: "twitch", ref: "streamer", origin: "twitch-app", position: 50, positionAt: NOW }), NOW);
    eq([live.state, live.start, live.how], ["ready", -1, "live"]);
    eq(P.command(live, env).argv, ["env", "TWITCH_QS_FONT=Paper Mono", "/opt/twitch-qs-mpv", "watch", "streamer"]);
    eq(P.command(live, Object.assign({}, env, { font: "Obel Mono" })).argv, ["env", "TWITCH_QS_FONT=Obel Mono", "/opt/twitch-qs-mpv", "watch", "streamer"]);
    eq(P.command(Object.assign({}, live, { origin: "browser" }), env).argv, ["xdg-open", "https://www.twitch.tv/streamer"]);
    eq(P.command(live, { twitchApp: "" }).argv, ["xdg-open", "https://www.twitch.tv/streamer"]);
    const vod = P.resolve(sent({ kind: "twitch-vod", ref: "1234567890", origin: "browser", position: 21400, positionAt: NOW }), NOW);
    eq(P.command(vod, env).argv, ["xdg-open", "https://www.twitch.tv/videos/1234567890?t=5h56m40s"]);
    const acc = P.resolve(sent({ kind: "twitch-vod", ref: "1" }), NOW);
    eq([acc.how, P.command(acc, env).argv], ["account", ["xdg-open", "https://www.twitch.tv/videos/1"]]);
    eq(P.command(P.resolve(sent({ kind: "twitch-clip", ref: "Slug-1" }), NOW), env).argv, ["xdg-open", "https://clips.twitch.tv/Slug-1"]);
    eq(P.hms(59), "59s"); eq(P.hms(60), "1m0s"); eq(P.hms(3600), "1h0m0s");
});

test("sent Jellyfin: the TV's position, else the server's resume point", () => {
    const t = P.resolve(sent({ kind: "jellyfin", ref: JF, position: 61.9, positionAt: NOW, playing: false }), NOW);
    eq(P.command(t, env).argv, env.jellyfin.concat(["play", JF, "--start", "61"]));
    eq(P.command(P.resolve(sent({ kind: "jellyfin", ref: JF }), NOW), env).argv, env.jellyfin.concat(["play", JF, "--resume"]));
    eq(P.command(t, {}), null);                                       // no jellyfin-qs
});

test("auto-detected: YouTube by exact search, Jellyfin by the server's session, Twitch / others cannot", () => {
    const y = P.resolve({ sent: false, appId: "2C6A6E3D", app: "YouTube", title: "Me at the zoo", subtitle: "jawed", position: 6, positionAt: NOW, duration: 19, playing: true }, NOW);
    eq([y.state, y.lookup, y.want], ["lookup", "youtube", { title: "Me at the zoo", artist: "jawed", duration: 19 }]);
    eq(P.resolve({ sent: false, appId: "2C6A6E3D", app: "YouTube", title: "YouTube", position: -1 }, NOW).state, "none");
    const j = P.resolve({ sent: false, appId: "com.github.damontecres.wholphin", app: "Wholphin", title: "Ep 2", position: -1 }, NOW);
    eq([j.state, j.lookup], ["lookup", "jellyfin"]);
    eq(P.settle(j, { id: JF, position: 81 }).start, 81);
    eq(P.settle(j, null).state, "none");
    const tw = P.resolve({ sent: false, appId: "tv.twitch.android.app", app: "Twitch", title: "Twitch", position: 120 }, NOW);
    eq(tw.state, "none");
    assert.match(P.describe(tw), /Twitch's TV app does not say/);
    eq(P.resolve({ sent: false, appId: "com.netflix.ninja", app: "Netflix", title: "Show" }, NOW).reason, "Netflix cannot play on this PC");
    eq(P.resolve(null, NOW).state, "none");
});

test("matchYoutube: only an exact title + channel (+ length) match, never a near miss", () => {
    const r = [{ id: "RD_Jwka9NaY", title: "[ Me at the zoo ] where is Jawed", channel: "Info-Beast", duration: 213 },
               { id: "jNQXAC9IVRw", title: "Me at the zoo", channel: "jawed", duration: 19 }];
    eq(P.matchYoutube(r, { title: "me at  the zoo", artist: "Jawed", duration: 19.021 }), "jNQXAC9IVRw");
    eq(P.matchYoutube(r, { title: "Me at the zoo", artist: "someone", duration: 19 }), "");
    eq(P.matchYoutube(r, { title: "Me at the zoo", artist: "jawed", duration: 60 }), "");
    eq(P.matchYoutube(r, { title: "Me at the zoo", artist: "", duration: -1 }), "jNQXAC9IVRw");
    eq(P.matchYoutube([{ id: "bad", title: "Me at the zoo" }], { title: "Me at the zoo" }), "");
    eq(P.matchYoutube(r, null), "");
});

test("pickJellyfin: the TV client, then the title the TV shows", () => {
    const rows = [{ id: "a".repeat(32), name: "Other", title: "Other", position_s: 5, client: "Jellyfin Web" },
                  { id: "b".repeat(32), name: "Second", title: "Show S01E02 - Second", position_s: 81, client: "Wholphin" }];
    eq(P.pickJellyfin(rows, { title: "" }), { id: "b".repeat(32), position: 81 });
    eq(P.pickJellyfin([rows[0]], { title: "" }), null);                                  // only another client: not the TV
    eq(P.pickJellyfin([rows[0]], { title: "Other" }), { id: "a".repeat(32), position: 5 });   // ... unless it shows the TV's title
    eq(P.pickJellyfin([{ id: "c".repeat(32), name: "X", client: "Wholphin", position_s: null }], {}), { id: "c".repeat(32), position: -1 });
    eq(P.pickJellyfin([], {}), null);
    eq(P.pickJellyfin([{ id: "x", client: "Wholphin" }], {}), null);
});

test("describe: what the button says", () => {
    eq(P.describe({ state: "ready", how: "exact", start: 3723 }), "Play on this PC at 1:02:03");
    eq(P.describe({ state: "ready", how: "exact", start: 65 }), "Play on this PC at 1:05");
    eq(P.describe({ state: "ready", how: "account", start: -1 }), "Play on this PC (resumes where your Twitch account left off)");
    eq(P.describe({ state: "ready", how: "live", start: -1 }), "Play on this PC (live)");
});
