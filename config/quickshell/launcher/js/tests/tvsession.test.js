const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const S = load("TvSession.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));

const ATV = [{ id: "remote.tv", adapter: "remote_androidtv_remote" }, { id: "media_player.tv", adapter: "media_player_androidtv_remote" },
             { id: "media_player.tv_cast", adapter: "media_player_cast" }];
const st = (state, a) => ({ state: state, attributes: a || {} });
const sess = (kind, members, sentVia) => S.start({ name: "Den TV", kind: kind, ref: "x", title: "Sent title", subtitle: "Chan", members: members || ATV,
                                                    sentVia: sentVia || "remote_androidtv_remote", now: 1000 });

test("start: app package, cast app, members", () => {
    const s = sess("youtube");
    eq([s.pkg, s.castApp, s.playing, s.members.length, s.name], ["com.google.android.youtube.tv", "233637DE", true, 3, "Den TV"]);
    eq(sess("jellyfin").pkg, "com.github.damontecres.wholphin");
    eq(sess("jellyfin").castApp, "");
});

test("controls: Android TV Remote keys on the remote entity", () => {
    const s = sess("jellyfin");
    const c = S.control(s, {}, "toggle", 0);
    eq(c.calls, [{ domain: "remote", service: "send_command", data: { entity_id: "remote.tv", command: "MEDIA_PLAY_PAUSE" } }]);
    eq(c.expect, { playing: false });
    eq(S.control(s, {}, "back", 0).calls[0].data.command, "MEDIA_REWIND");
    eq(S.control(s, {}, "forward", 0).calls[0].data.command, "MEDIA_FAST_FORWARD");
    eq(S.control(s, {}, "volup", 0).calls[0].data.command, "VOLUME_UP");
    eq(S.control(s, {}, "voldown", 0).calls[0].data.command, "VOLUME_DOWN");
    eq(S.control(s, {}, "mute", 0).calls[0].data.command, "VOLUME_MUTE");
    eq(S.control(s, {}, "next", 0).calls[0].data.command, "MEDIA_NEXT");
    eq(S.control(s, {}, "previous", 0).calls[0].data.command, "MEDIA_PREVIOUS");
    const stop = S.control(s, {}, "stop", 0);
    eq([stop.calls[0].data.command, stop.ends], ["BACK", true]);
    assert.strictEqual(S.control(s, {}, "volume:50", 0), null);
    eq(S.caps(s, {}), { toggle: true, prevNext: true, seek: true, volumeStep: true, volumeSet: false, mute: true, stop: true });
});

test("controls: ADB keyevents, Android TV Remote media_player services", () => {
    const adb = sess("twitch", [{ id: "media_player.adb", adapter: "media_player_androidtv" }], "media_player_androidtv");
    eq(S.control(adb, {}, "toggle", 0).calls, [{ domain: "androidtv", service: "adb_command", data: { entity_id: "media_player.adb", command: "input keyevent KEYCODE_MEDIA_PLAY_PAUSE" } }]);
    const mp = sess("twitch", [{ id: "media_player.tv", adapter: "media_player_androidtv_remote" }], "media_player_androidtv_remote");
    eq(S.control(mp, {}, "toggle", 0).calls[0], { domain: "media_player", service: "media_play_pause", data: { entity_id: "media_player.tv" } });
    eq(S.control(mp, {}, "volup", 0).calls[0].service, "volume_up");
    eq(S.control(mp, {}, "mute", 0).calls[0], { domain: "media_player", service: "volume_mute", data: { entity_id: "media_player.tv", is_volume_muted: true } });
    assert.strictEqual(S.control(mp, {}, "back", 0), null);
    assert.strictEqual(S.caps(mp, {}).seek, false);
});

test("controls: Cast while it plays our app: services with real position / volume", () => {
    const s = sess("youtube");
    const states = { "media_player.tv_cast": st("playing", { app_id: "233637DE", media_title: "Real title", media_position: 100, media_duration: 105, volume_level: 0.4, is_volume_muted: false }) };
    eq(S.view(s, states, 0).via, "cast");
    eq(S.view(s, states, 0).title, "Real title");
    eq(S.control(s, states, "forward", 0).calls[0], { domain: "media_player", service: "media_seek", data: { entity_id: "media_player.tv_cast", seek_position: 105 } });
    eq(S.control(s, states, "back", 0).calls[0].data.seek_position, 90);
    eq(S.control(s, states, "volup", 0).calls[0], { domain: "media_player", service: "volume_set", data: { entity_id: "media_player.tv_cast", volume_level: 0.45 } });
    eq(S.control(s, states, "volume:20", 0).expect, { volume: 0.2 });
    eq(S.control(s, states, "toggle", 0).calls[0].service, "media_play_pause");
    // Cast idle / another cast app: back to keys on the remote
    eq(S.view(s, { "media_player.tv_cast": st("idle") }, 0).via, "keys");
    eq(S.view(s, { "media_player.tv_cast": st("playing", { app_id: "OTHER" }) }, 0).via, "keys");
});

test("view: optimistic pend wins until it expires, then the TV's state", () => {
    const s = sess("youtube");
    s.pend = { playing: false, until: 5000 };
    const states = { "media_player.tv_cast": st("playing", { app_id: "233637DE" }) };
    eq(S.view(s, states, 4000).playing, false);
    eq(S.view(s, states, 6000).playing, true);
    // no metadata at all (Android TV Remote only): our last known state
    const k = sess("jellyfin", [ATV[0]]);
    k.playing = false;
    eq(S.view(k, {}, 0).playing, false);
    eq(S.view(k, {}, 0).title, "Sent title");
});

test("judge: TV off / unavailable for offMs ends it; a short blip does not", () => {
    const s = sess("jellyfin");
    let j = S.judge(s, { "remote.tv": st("off") }, 10000, 25000, 20000);
    eq([j.end, j.badSince], ["", 10000]);
    s.badSince = j.badSince;
    eq(S.judge(s, { "remote.tv": st("off") }, 30000, 25000, 20000).end, "");
    eq(S.judge(s, { "remote.tv": st("unavailable") }, 35000, 25000, 20000).end, "off");
    eq(S.judge(s, { "remote.tv": st("on", { current_activity: "com.github.damontecres.wholphin" }) }, 36000, 25000, 20000), { end: "", badSince: 0, awaySince: 0 });
    eq(S.judge(s, {}, 99999, 25000, 20000).end, "off");   // unread: timers kept (badSince still 10000)
});

test("judge: another app in front for awayMs ends it", () => {
    const s = sess("twitch");
    const away = { "remote.tv": st("on", { current_activity: "com.netflix.ninja" }) };
    let j = S.judge(s, away, 1000, 25000, 20000);
    eq([j.end, j.awaySince], ["", 1000]);
    s.awaySince = j.awaySince;
    eq(S.judge(s, away, 21000, 25000, 20000).end, "away");
    eq(S.judge(s, { "remote.tv": st("on", { current_activity: "tv.twitch.android.app" }) }, 21000, 25000, 20000).awaySince, 0);
    // a Cast send: Cast idle = over, another cast app = away
    const c = sess("youtube", ATV, "media_player_cast");
    eq(S.judge(c, { "media_player.tv_cast": st("idle") }, 5000, 25000, 20000).badSince, 5000);
    eq(S.judge(c, { "media_player.tv_cast": st("playing", { app_id: "OTHER" }) }, 5000, 25000, 20000).awaySince, 5000);
});

test("parse / artFor", () => {
    const s = sess("youtube");
    eq(S.parse(JSON.stringify(s)).title, "Sent title");
    assert.strictEqual(S.parse("{}"), null);
    assert.strictEqual(S.parse("nope"), null);
    assert.strictEqual(S.parse(JSON.stringify(Object.assign({}, s, { members: [{ id: "light.x", adapter: "remote_androidtv_remote" }] }))), null);
    eq(S.artFor("youtube", "dQw4w9WgXcQ", "file:///tmp/.org.chromium.x"), "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg");
    eq(S.artFor("twitch", "x", "file:///home/u/.cache/a.png"), "file:///home/u/.cache/a.png");
    eq(S.artFor("jellyfin", "x", ""), "");
});

// ---- auto-detect ----
const ON_YT = { "remote.tv": st("on", { current_activity: "com.google.android.youtube.tv" }), "media_player.tv": st("on", { app_id: "com.google.android.youtube.tv" }) };
const withCast = (state, a) => Object.assign({}, ON_YT, { "media_player.tv_cast": st(state, a) });

test("detect: Cast playing the TV's app: title, app, art, position", () => {
    const d = S.detect(ATV, withCast("playing", { app_id: "233637DE", app_name: "YouTube", media_title: "Clip", media_artist: "Chan",
        media_position: 30, media_position_updated_at: "2026-01-01T00:00:00+00:00", media_duration: 120, entity_picture: "/api/media_player_proxy/x?token=t",
        volume_level: 0.3, is_volume_muted: false }));
    eq([d.id, d.title, d.subtitle, d.app, d.playing, d.position, d.duration, d.volume, d.castApp], ["media_player.tv_cast", "Clip", "Chan", "YouTube", true, 30, 120, 0.3, "233637DE"]);
    eq(d.positionAt, Date.parse("2026-01-01T00:00:00Z"));
    eq(S.positionAt(d, d.positionAt + 10000), 40);
    eq(S.positionAt(d, d.positionAt + 999000), 120);
    eq(S.positionAt(Object.assign({}, d, { playing: false }), d.positionAt + 10000), 30);
    eq(S.pictureUrl("http://ha.example:8123/", d.picture), "http://ha.example:8123/api/media_player_proxy/x?token=t");
    eq(S.pictureUrl("http://ha.example:8123", "https://img.example/a.jpg"), "https://img.example/a.jpg");
    eq(S.pictureUrl("http://ha.example:8123", ""), "");
    eq(S.detect(ATV, withCast("paused", { app_id: "233637DE", media_title: "Clip" })).playing, false);
});

test("detect: hidden when off / standby / unread / idle / home screen / unknown app without title", () => {
    const cast = { app_id: "233637DE", media_title: "Clip" };
    assert.strictEqual(S.detect(ATV, {}), null);
    assert.strictEqual(S.detect(ATV, Object.assign(withCast("playing", cast), { "remote.tv": st("off") })), null);
    assert.strictEqual(S.detect(ATV, Object.assign(withCast("playing", cast), { "remote.tv": st("standby") })), null);
    assert.strictEqual(S.detect(ATV, Object.assign(withCast("playing", cast), { "remote.tv": st("unavailable") })), null);
    assert.strictEqual(S.detect(ATV, withCast("idle", cast)), null);
    assert.strictEqual(S.detect(ATV, ON_YT), null);                                                        // on, no playback reported
    const home = Object.assign(withCast("playing", cast), { "remote.tv": st("on", { current_activity: "com.google.android.apps.tv.launcherx" }) });
    assert.strictEqual(S.detect(ATV, home), null);
    assert.strictEqual(S.detect(ATV, withCast("playing", { app_id: "E8C28D3C", app_name: "Backdrop" })), null);   // ambient mode
    const unknown = { "remote.tv": st("on", { current_activity: "com.example.player" }), "media_player.tv_cast": st("playing", { app_id: "ABCDEF01" }) };
    assert.strictEqual(S.detect(ATV, unknown), null);
    // a known app without a title: its name
    const named = { "remote.tv": st("on", { current_activity: "com.netflix.ninja" }), "media_player.tv_cast": st("playing", { app_id: "CA5E8412", app_name: "Netflix" }) };
    eq([S.detect(ATV, named).title, S.detect(ATV, named).subtitle], ["Netflix", ""]);
    // a paused cast session behind another app in front
    const behind = Object.assign(withCast("paused", cast), { "remote.tv": st("on", { current_activity: "com.netflix.ninja" }) });
    assert.strictEqual(S.detect(ATV, behind), null);
});

test("detect: ADB player (package name, no app_name) and a Cast-only TV", () => {
    const adb = [{ id: "media_player.adb", adapter: "media_player_androidtv" }];
    const d = S.detect(adb, { "media_player.adb": st("playing", { app_id: "org.jellyfin.androidtv", app_name: "org.jellyfin.androidtv", media_title: "Ep 1", media_series_title: "Show" }) });
    eq([d.title, d.subtitle, d.app, d.castApp], ["Ep 1", "Show", "Jellyfin", ""]);
    assert.strictEqual(S.detect(adb, { "media_player.adb": st("standby", { media_title: "x" }) }), null);
    const cast = [{ id: "media_player.c", adapter: "media_player_cast" }];
    eq(S.detect(cast, { "media_player.c": st("playing", { app_id: "233637DE", media_title: "Clip" }) }).title, "Clip");
    assert.strictEqual(S.detect(cast, { "media_player.c": st("idle", { app_id: "233637DE" }) }), null);
});

test("autoSession: controls drive the TV like a sent session (Cast while it reports, else keys)", () => {
    const states = withCast("playing", { app_id: "233637DE", media_title: "Clip", media_position: 50, media_duration: 100 });
    const d = S.detect(ATV, states);
    const s = S.autoSession("Den TV", ATV, d);
    eq(S.via(s, states), "cast");
    eq(S.control(s, states, "toggle", 0).calls[0], { domain: "media_player", service: "media_play_pause", data: { entity_id: "media_player.tv_cast" } });
    eq(S.control(s, states, "forward", 0).calls[0].data.seek_position, 60);
    // an ADB-reported app on an Android TV Remote TV: keys on the remote
    const adbTv = ATV.concat([{ id: "media_player.adb", adapter: "media_player_androidtv" }]);
    const st2 = Object.assign({}, ON_YT, { "media_player.adb": st("paused", { app_id: "com.netflix.ninja", media_title: "Film" }) });
    const s2 = S.autoSession("Den TV", adbTv, S.detect(adbTv, st2));
    eq(S.control(s2, st2, "toggle", 0).calls[0], { domain: "remote", service: "send_command", data: { entity_id: "remote.tv", command: "MEDIA_PLAY_PAUSE" } });
    eq(S.control(s2, st2, "toggle", 0).expect, { playing: true });
    eq(S.withPend(S.detect(adbTv, st2), { playing: true, until: 10 }, 5).playing, true);
    eq(S.withPend(S.detect(adbTv, st2), { playing: true, until: 10 }, 11).playing, false);
});

// ---- routes with real-shaped supported_features (HA MediaPlayerEntityFeature bits) ----
const CAST_F = 152463;   // Cast: PAUSE SEEK VOLUME_SET VOLUME_MUTE TURN_ON/OFF PLAY_MEDIA STOP PLAY BROWSE (no PREVIOUS / NEXT)
const ATV_F = 153529;    // Android TV Remote media_player: PAUSE MUTE PREVIOUS NEXT TURN_ON/OFF PLAY_MEDIA VOLUME_STEP STOP PLAY BROWSE
const NATIVE = {
    "remote.tv": st("on", { current_activity: "tv.twitch.android.app", supported_features: 4 }),
    "media_player.tv": st("on", { app_id: "tv.twitch.android.app", app_name: "tv.twitch.android.app", supported_features: ATV_F }),
    "media_player.tv_cast": st("playing", { app_id: "AndroidNativeApp", app_name: "Twitch", media_position: 3000, volume_level: 0.3,
                                            is_volume_muted: false, supported_features: CAST_F })
};

test("routes: a native app Cast only mirrors (AndroidNativeApp) is driven by remote keys, never Cast", () => {
    const d = S.detect(ATV, NATIVE);
    eq([d.id, d.title, d.castApp], ["media_player.tv_cast", "Twitch", "AndroidNativeApp"]);
    const s = S.autoSession("Den TV", ATV, d);
    eq(S.via(s, NATIVE), "keys");
    const want = { toggle: "MEDIA_PLAY_PAUSE", previous: "MEDIA_PREVIOUS", next: "MEDIA_NEXT", back: "MEDIA_REWIND", forward: "MEDIA_FAST_FORWARD",
                   stop: "BACK", volup: "VOLUME_UP", voldown: "VOLUME_DOWN", mute: "VOLUME_MUTE" };
    for (const w in want) eq(S.control(s, NATIVE, w, 0).calls, [{ domain: "remote", service: "send_command", data: { entity_id: "remote.tv", command: want[w] } }]);
    eq(S.caps(s, NATIVE), { toggle: true, prevNext: true, seek: true, volumeStep: true, volumeSet: false, mute: true, stop: true });
    eq(S.control(s, NATIVE, "toggle", 0).expect, { playing: false });
    assert.strictEqual(S.control(s, NATIVE, "volume:40", 0), null);
    // a Cast-only TV showing a native app: nothing can drive it (no controls rather than ignored calls)
    const castOnly = [ATV[2]];
    const s2 = S.autoSession("Den TV", castOnly, S.detect(castOnly, NATIVE));
    eq(S.caps(s2, NATIVE), { toggle: false, prevNext: false, seek: false, volumeStep: false, volumeSet: false, mute: false, stop: false });
    // ADB beside it: keyevents
    const adbTv = [ATV[2], { id: "media_player.adb", adapter: "media_player_androidtv" }];
    const st3 = Object.assign({ "media_player.adb": st("playing", { app_id: "tv.twitch.android.app" }) }, NATIVE);
    eq(S.control(S.autoSession("Den TV", adbTv, S.detect(adbTv, st3)), st3, "toggle", 0).calls[0].service, "adb_command");
});

test("routes: a real Cast receiver uses Cast where its supported_features allow, keys for the rest", () => {
    const states = Object.assign({}, NATIVE, { "remote.tv": st("on", { current_activity: "com.google.android.youtube.tv" }), "media_player.tv_cast": st("playing", { app_id: "233637DE", app_name: "YouTube", media_title: "Clip",
        media_position: 50, media_duration: 100, volume_level: 0.3, is_volume_muted: false, supported_features: CAST_F }) });
    const s = S.autoSession("Den TV", ATV, S.detect(ATV, states));
    eq(S.control(s, states, "toggle", 0).calls[0], { domain: "media_player", service: "media_play_pause", data: { entity_id: "media_player.tv_cast" } });
    eq(S.control(s, states, "stop", 0).calls[0].service, "media_stop");
    eq(S.control(s, states, "forward", 0).calls[0].data.seek_position, 60);
    eq(S.control(s, states, "volume:20", 0).calls[0].service, "volume_set");
    // Cast cannot skip here: the remote's keys
    eq(S.control(s, states, "next", 0).calls[0], { domain: "remote", service: "send_command", data: { entity_id: "remote.tv", command: "MEDIA_NEXT" } });
    eq(S.control(s, states, "previous", 0).calls[0].data.command, "MEDIA_PREVIOUS");
    // Cast with no PLAY / PAUSE / position: keys for play / pause and the seek steps
    const lim = Object.assign({}, states, { "media_player.tv_cast": st("playing", { app_id: "233637DE", media_title: "Clip", supported_features: 4 }) });
    eq(S.control(s, lim, "toggle", 0).calls[0].data.command, "MEDIA_PLAY_PAUSE");
    eq(S.control(s, lim, "back", 0).calls[0].data.command, "MEDIA_REWIND");
    eq(S.control(s, lim, "volume:20", 0).calls[0].service, "volume_set");
});

test("routes: Android TV Remote media_player services only where supported_features allow", () => {
    const mp = sess("twitch", [{ id: "media_player.tv", adapter: "media_player_androidtv_remote" }], "media_player_androidtv_remote");
    const ok = { "media_player.tv": st("on", { supported_features: ATV_F }) };
    eq(S.control(mp, ok, "toggle", 0).calls[0].service, "media_play_pause");
    eq(S.control(mp, ok, "next", 0).calls[0].service, "media_next_track");
    eq(S.control(mp, ok, "volup", 0).calls[0].service, "volume_up");
    assert.strictEqual(S.control(mp, ok, "back", 0), null);
    const bare = { "media_player.tv": st("on", { supported_features: 128 | 256 }) };   // on / off only
    eq(S.caps(mp, bare), { toggle: false, prevNext: false, seek: false, volumeStep: false, volumeSet: false, mute: false, stop: false });
    assert.strictEqual(S.control(mp, bare, "toggle", 0), null);
});
