const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const T = load("TvCast.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));

const YT = "dQw4w9WgXcQ";
const JF = "0123456789abcdef0123456789abcdef";
const brave = { source: "mpris", identity: "Brave", desktopEntry: "brave-browser", artUrl: "file:///tmp/.org.chromium.Chromium.abc", title: "Some video" };

test("YouTube in a Chromium browser: pending until the tab is looked up, then the tab URL", () => {
    eq(T.identify(brave), { kind: "pending" });
    eq(T.identify(Object.assign({}, brave, { tabUrl: "https://www.youtube.com/watch?v=" + YT + "&list=PL1&t=30s", position: 754.8 })),
        { kind: "youtube", ref: YT, startSeconds: 754, title: "Some video" });
    eq(T.identify(Object.assign({}, brave, { tabUrl: "" })), { kind: "unsupported" });
    eq(T.identify(Object.assign({}, brave, { tabUrl: "https://example.org/x" })), { kind: "unsupported" });
});

test("YouTube from a cover URL (Firefox) and from mpv's own URL", () => {
    eq(T.identify({ source: "mpris", identity: "Mozilla Firefox", artUrl: "https://i.ytimg.com/vi/" + YT + "/maxresdefault.jpg", position: 12, title: "t" }),
        { kind: "youtube", ref: YT, startSeconds: 12, title: "t" });
    eq(T.identify({ source: "mpris", identity: "mpv", url: "https://youtu.be/" + YT + "?si=x", position: 0, title: "t" }).ref, YT);
    eq(T.identify({ source: "mpris", identity: "mpv", url: "https://www.youtube.com/shorts/" + YT, title: "t" }).kind, "youtube");
});

test("Twitch: the app's channel, a browser tab, a live preview cover", () => {
    eq(T.identify({ source: "twitch", channel: "Some_Streamer", title: "Stream" }), { kind: "twitch", ref: "some_streamer", startSeconds: 0, title: "Stream" });
    eq(T.identify({ source: "twitch", channel: "bad name" }), { kind: "unsupported" });
    eq(T.identify(Object.assign({}, brave, { tabUrl: "https://www.twitch.tv/streamer?referrer=raid", position: 999 })).ref, "streamer");
    eq(T.identify(Object.assign({}, brave, { tabUrl: "https://www.twitch.tv/videos/123456" })), { kind: "unsupported" });
    eq(T.identify(Object.assign({}, brave, { tabUrl: "https://www.twitch.tv/directory" })), { kind: "unsupported" });
    eq(T.identify({ source: "mpris", identity: "Firefox", artUrl: "https://static-cdn.jtvnw.net/previews-ttv/live_user_streamer-1280x720.jpg", title: "x" }).ref, "streamer");
});

test("Jellyfin: mpv's stream URL carries the item id; the position is kept", () => {
    eq(T.identify({ source: "mpris", identity: "mpv", url: "http://jellyfin.example:8096/Videos/" + JF + "/stream?static=true", position: 61.5, title: "Ep" }),
        { kind: "jellyfin", ref: JF, startSeconds: 61, title: "Ep" });
    eq(T.identify({ source: "mpris", identity: "mpv", url: "http://jellyfin.example/Audio/" + JF + "/stream?static=true" }), { kind: "unsupported" });
    // a browser tab on the Jellyfin web UI is not the mpv player
    eq(T.identify(Object.assign({}, brave, { tabUrl: "http://jellyfin.example/Videos/" + JF + "/stream" })), { kind: "unsupported" });
});

test("anything else is unsupported (Spotify, a local file, no title)", () => {
    eq(T.identify({ source: "mpris", identity: "Spotify", artUrl: "https://i.scdn.co/image/x", title: "Song" }), { kind: "unsupported" });
    eq(T.identify({ source: "mpris", identity: "mpv", url: "file:///home/u/v.mkv", title: "v" }), { kind: "unsupported" });
    eq(T.identify(Object.assign({}, brave, { title: "" })), { kind: "unsupported" });
    eq(T.identify({ source: "mpris", identity: "Mozilla Firefox", title: "x" }), { kind: "unsupported" });   // no session reader for Firefox
    eq(T.identify(null), { kind: "unsupported" });
});

test("adapter by entity domain + integration", () => {
    eq(T.adapterFor("remote.tv", "androidtv_remote"), "remote_androidtv_remote");
    eq(T.adapterFor("media_player.tv", "androidtv_remote"), "media_player_androidtv_remote");
    eq(T.adapterFor("media_player.tv", "androidtv"), "media_player_androidtv");
    eq(T.adapterFor("media_player.tv", "cast"), "media_player_cast");
    eq(T.adapterFor("media_player.tv", "webostv"), "");
    assert.ok(T.supports("media_player_cast", "youtube"));
    assert.ok(!T.supports("media_player_cast", "twitch"));
});

test("payloads: Android TV Remote remote entity (wake + launch in one call)", () => {
    const p = T.plan("remote_androidtv_remote", "remote.tv", { kind: "youtube", ref: YT, startSeconds: 754 });
    eq(p.launch, [{ domain: "remote", service: "turn_on", data: { entity_id: "remote.tv", activity: "https://www.youtube.com/watch?v=" + YT + "&t=754s" } }]);
    assert.strictEqual(p.launchWakes, true);
    assert.strictEqual(p.wake, null);
    eq(p.verify, { attr: "current_activity", value: "com.google.android.youtube.tv" });
    eq(T.plan("remote_androidtv_remote", "remote.tv", { kind: "twitch", ref: "streamer", startSeconds: 0 }).launch[0].data.activity, "twitch://stream/streamer");
    eq(T.plan("remote_androidtv_remote", "remote.tv", { kind: "jellyfin", ref: JF, startSeconds: 61 }).launch[0].data.activity,
        "wholphin://play?itemId=" + JF + "&position=61000");
    eq(T.plan("remote_androidtv_remote", "remote.tv", { kind: "youtube", ref: YT, startSeconds: 0 }).link, "https://www.youtube.com/watch?v=" + YT);
});

test("payloads: Android TV Remote media_player, ADB, Cast", () => {
    const m = T.plan("media_player_androidtv_remote", "media_player.tv", { kind: "jellyfin", ref: JF, startSeconds: 0 });
    eq(m.wake, { domain: "media_player", service: "turn_on", data: { entity_id: "media_player.tv" } });
    eq(m.launch, [{ domain: "media_player", service: "play_media", data: { entity_id: "media_player.tv", media_content_type: "url", media_content_id: "wholphin://play?itemId=" + JF } }]);
    const a = T.plan("media_player_androidtv", "media_player.tv", { kind: "twitch", ref: "streamer", startSeconds: 0 });
    eq(a.launch[0], { domain: "androidtv", service: "adb_command", data: { entity_id: "media_player.tv", command: "am start -a android.intent.action.VIEW -d 'twitch://stream/streamer' tv.twitch.android.app" } });
    const c = T.plan("media_player_cast", "media_player.tv", { kind: "youtube", ref: YT, startSeconds: 90 });
    eq(c.launch, [{ domain: "media_player", service: "play_media", data: { entity_id: "media_player.tv", media_content_type: "cast", media_content_id: '{"app_name":"youtube","media_id":"' + YT + '"}' } }]);
    eq(c.after, [{ state: "playing", call: { domain: "media_player", service: "media_seek", data: { entity_id: "media_player.tv", seek_position: 90 } } }]);
    eq(c.verify, { attr: "app_id", value: "233637DE" });
    assert.strictEqual(T.plan("media_player_cast", "media_player.tv", { kind: "twitch", ref: "s", startSeconds: 0 }), null);
    assert.strictEqual(T.plan("media_player_cast", "media_player.tv", T.TEST), null);
});

test("test plan opens the YouTube app home", () => {
    eq(T.plan("remote_androidtv_remote", "remote.tv", T.TEST).launch[0].data, { entity_id: "remote.tv", activity: "https://www.youtube.com" });
});

test("states and the opened check", () => {
    assert.ok(T.isMissing(null) && T.isMissing({ state: "unavailable" }) && T.isMissing({ state: "unknown" }));
    assert.ok(T.isOff({ state: "off" }) && T.isOff({ state: "standby" }) && !T.isOff({ state: "idle" }));
    assert.ok(T.isReady({ state: "on" }) && T.isReady({ state: "playing" }) && !T.isReady({ state: "off" }));
    const v = { attr: "current_activity", value: "tv.twitch.android.app" };
    assert.strictEqual(T.opened({ state: "on", attributes: { current_activity: "tv.twitch.android.app" } }, v), true);
    assert.strictEqual(T.opened({ state: "on", attributes: { current_activity: "com.google.android.tvlauncher" } }, v), false);
    assert.strictEqual(T.opened({ state: "on", attributes: {} }, v), null);
});

test("shown: only when it would work (TV off still shows)", () => {
    const base = { configured: true, haOk: true, entity: "remote.tv", adapter: "remote_androidtv_remote", state: { state: "off" }, media: { kind: "youtube" } };
    assert.ok(T.shown(base));
    assert.ok(!T.shown(Object.assign({}, base, { state: { state: "unavailable" } })));
    assert.ok(!T.shown(Object.assign({}, base, { state: null })));
    assert.ok(!T.shown(Object.assign({}, base, { haOk: false })));
    assert.ok(!T.shown(Object.assign({}, base, { configured: false })));
    assert.ok(!T.shown(Object.assign({}, base, { entity: "" })));
    assert.ok(!T.shown(Object.assign({}, base, { media: { kind: "unsupported" } })));
    assert.ok(!T.shown(Object.assign({}, base, { media: { kind: "pending" } })));
    assert.ok(!T.shown(Object.assign({}, base, { adapter: "media_player_cast", media: { kind: "jellyfin" } })));
});

test("Brave's exact MPRIS shape (paused, apostrophe + '|' title, '&' artist, temp cover, no URL): pending, then the tab", () => {
    const d = { source: "mpris", identity: "Brave", desktopEntry: "", url: "", artUrl: "file:///tmp/.org.chromium.Chromium.Ab12Cd",
                title: "Rainy night but it's lofi beats | Mix", artist: "beats & bits", position: 1508.7 };
    eq(T.browserKey(d.identity, d.desktopEntry), "brave");
    eq(T.browserKey("brave.instance12345", ""), "brave");               // the bus-name shape some builds report as identity
    eq(T.identify(d), { kind: "pending" });
    eq(T.identify(Object.assign({}, d, { tabUrl: "" })), { kind: "unsupported" });
    eq(T.identify(Object.assign({}, d, { tabUrl: "https://www.youtube.com/watch?v=" + YT + "&list=RD1" })),
        { kind: "youtube", ref: YT, startSeconds: 1508, title: d.title });
});

// HA candidates the way TvCast.loadCandidates reads them (device registry via the template endpoint)
const ent = (id, platform, device, o) => Object.assign({ id, platform, device, state: "off", deviceName: "", nameByUser: "", manufacturer: "", model: "", macs: [], friendly: "" }, o || {});

test("one TV from an Android TV Remote device + a Cast device renamed '<TV> - Remote' / '<TV> - Google Cast'", () => {
    const g = T.tvGroups([
        ent("media_player.den_cast", "cast", "dc", { deviceName: "Den Smart TV", nameByUser: "Den TV - Google Cast", manufacturer: "Acme", model: "Model X" }),
        ent("remote.den", "androidtv_remote", "dr", { deviceName: "Den Smart TV", nameByUser: "Den TV - Remote", manufacturer: "Acme", model: "Model X", macs: ["aa:bb"] }),
        ent("media_player.den", "androidtv_remote", "dr", { deviceName: "Den Smart TV", nameByUser: "Den TV - Remote", manufacturer: "Acme", model: "Model X", macs: ["aa:bb"] }),
        ent("media_player.webos", "webostv", "dw", { deviceName: "Kitchen" }),
        ent("light.x", "hue", "dl")]);
    eq(g.length, 1);
    eq(g[0].name, "Den TV");
    eq(g[0].model, "Acme Model X");
    eq(g[0].members, [{ id: "remote.den", adapter: "remote_androidtv_remote" }, { id: "media_player.den", adapter: "media_player_androidtv_remote" },
                      { id: "media_player.den_cast", adapter: "media_player_cast" }]);
    eq(g[0].state, "off");
});

test("merge by MAC, by original name + model; two identical TVs stay apart; a Cast-only TV is its own entry", () => {
    const byMac = T.tvGroups([ent("media_player.a", "androidtv", "d1", { nameByUser: "Bedroom", macs: ["AA:BB"] }),
                              ent("media_player.b", "cast", "d2", { nameByUser: "Something else", macs: ["aa:bb"] })]);
    eq(byMac.length, 1); eq(byMac[0].name, "Bedroom");
    const twins = T.tvGroups([ent("remote.t1", "androidtv_remote", "d1", { deviceName: "Smart TV", model: "M" }),
                              ent("remote.t2", "androidtv_remote", "d2", { deviceName: "Smart TV", model: "M" }),
                              ent("media_player.c1", "cast", "d3", { deviceName: "Smart TV", model: "M" })]);
    eq(twins.length, 2);                                                  // the Cast joins the first; the second remote stays apart
    const castOnly = T.tvGroups([ent("media_player.office", "cast", "d9", { nameByUser: "Office TV", state: "unavailable" })]);
    eq(castOnly, [{ key: "d:d9", name: "Office TV", model: "", state: "unavailable", members: [{ id: "media_player.office", adapter: "media_player_cast" }] }]);
    eq(T.tvGroups([ent("media_player.x", "androidtv_remote", "", { friendly: "Loft TV", state: "on" })])[0].state, "on");
    // no device registry (template error): the same-named remote + media_player of one integration still make one TV
    const flat = T.tvGroups([ent("remote.loft", "androidtv_remote", "", { friendly: "Loft TV" }), ent("media_player.loft", "androidtv_remote", "", { friendly: "Loft TV" }),
                             ent("media_player.loft2", "cast", "", { friendly: "Loft" })]);
    eq(flat.map(g => [g.name, g.members.length]), [["Loft", 1], ["Loft TV", 2]]);
});

test("pickMember: the preferred member unless its entity is unavailable / unknown / missing", () => {
    const m = [{ id: "remote.den", adapter: "remote_androidtv_remote" }, { id: "media_player.den_cast", adapter: "media_player_cast" }];
    eq(T.pickMember(m, {}).id, "remote.den");
    eq(T.pickMember(m, { "remote.den": { state: "off" } }).id, "remote.den");
    eq(T.pickMember(m, { "remote.den": { state: "unavailable" }, "media_player.den_cast": { state: "off" } }).id, "media_player.den_cast");
    eq(T.pickMember(m, { "remote.den": null, "media_player.den_cast": { state: "idle" } }).id, "media_player.den_cast");
    eq(T.pickMember(m, { "remote.den": { state: "unknown" }, "media_player.den_cast": { state: "unavailable" } }).id, "remote.den");
    eq(T.pickMember([{ id: "media_player.w", adapter: "media_player_webostv" }], {}), null);
});

test("shown: every available TV state shows (on / off / standby / idle / playing), unavailable / unknown / none hide", () => {
    const base = { configured: true, haOk: true, entity: "remote.den", adapter: "remote_androidtv_remote", media: { kind: "youtube", ref: YT } };
    for (const s of ["on", "off", "standby", "idle", "playing"]) eq(T.shown(Object.assign({}, base, { state: { state: s } })), true);
    for (const s of ["unavailable", "unknown"]) eq(T.shown(Object.assign({}, base, { state: { state: s } })), false);
    eq(T.shown(Object.assign({}, base, { state: null })), false);
    eq(T.shown(Object.assign({}, base, { state: { state: "on" }, media: { kind: "pending" } })), false);
});

test("Wholphin: VIEW opens details, so OK is pressed once it is up; ADB sends the PLAYBACK action instead", () => {
    const JF2 = "0123456789abcdef0123456789abcdef";
    const m = { kind: "jellyfin", ref: JF2, startSeconds: 61 };
    const r = T.plan("remote_androidtv_remote", "remote.tv", m);
    eq(r.afterOpen, { delayMs: 2500, call: { domain: "remote", service: "send_command", data: { entity_id: "remote.tv", command: ["DPAD_CENTER"] } } });
    const mp = T.plan("media_player_androidtv_remote", "media_player.tv", m, { keyEntity: "remote.tv" });
    eq(mp.afterOpen.call.data.entity_id, "remote.tv");
    assert.strictEqual(T.plan("media_player_androidtv_remote", "media_player.tv", m).afterOpen, null);   // no remote: no keys
    const adb = T.plan("media_player_androidtv", "media_player.tv", m);
    eq(adb.launch[0].data.command, "am start -a com.github.damontecres.wholphin.PLAYBACK -d 'wholphin://play?itemId=" + JF2 + "&position=61000' com.github.damontecres.wholphin");
    assert.strictEqual(adb.afterOpen, null);
    // YouTube / Twitch links play by themselves
    assert.strictEqual(T.plan("remote_androidtv_remote", "remote.tv", { kind: "youtube", ref: "dQw4w9WgXcQ", startSeconds: 0 }).afterOpen, null);
    assert.strictEqual(T.plan("remote_androidtv_remote", "remote.tv", T.TEST).afterOpen, null);
});
