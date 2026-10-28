.pragma library
.import "TvCast.js" as Cast

// Send to TV, after the send: the TV session ("playing on TV") that TvSession.qml keeps and TvSource.qml shows as a media
// source. Pure functions (tests/tvsession.test.js); nothing here talks to HA.
//
// session = { v: 1, name (the TV), kind, ref, title, subtitle, artUrl, startSeconds, startedAt (ms), pkg (the TV app),
// castApp (Cast app id, "" = none), members: [{ id, adapter }] (the TV's entities), sentVia (adapter of the send),
// playing / muted (our last known, optimistic), volume (-1 = unknown), pend: { playing?, muted?, volume?, until } (a
// control's expected result, shown until `until`, then the TV's own state wins where it reports one), badSince /
// awaySince (ms, 0 = no: see judge) }.
// states = { entityId: HA state object | null (missing) } (unread entities absent).
//
// Who answers what (roles): power + foreground app = the Android TV Remote remote.* (current_activity), else its
// media_player.* / ADB (app_id), else Cast; metadata (title, position, volume) = Cast while its session is our app
// (castActive), else the Android TV Remote / ADB media_player. Controls (route, per control): Cast services while
// castActive and Cast's supported_features has that control, else Android key codes on the remote.* (remote.send_command),
// else ADB (input keyevent), else the Android TV Remote media_player's services (where its supported_features allow).
// Cast reports a native Android TV app (Twitch, Wholphin, Netflix, ...) as app_id "AndroidNativeApp": it only mirrors that
// app's state, HA accepts media commands to it (200) and the TV ignores them, so that is never castActive.

var KEYS = {      // control -> Android key code (remote.send_command / adb input keyevent KEYCODE_<x>)
    toggle: "MEDIA_PLAY_PAUSE", previous: "MEDIA_PREVIOUS", next: "MEDIA_NEXT", back: "MEDIA_REWIND",
    forward: "MEDIA_FAST_FORWARD", volup: "VOLUME_UP", voldown: "VOLUME_DOWN", mute: "VOLUME_MUTE", stop: "BACK"   // stop = BACK: MEDIA_STOP is accepted (200) and ignored by native TV apps (Twitch); BACK leaves the player (a live stream may keep audio on its page); never HOME / force-stop / power off
}
var SEEK_S = 10                     // seek back / forward step (Cast: media_seek; keys: whatever the app's REWIND does)
var VOL_STEP = 0.05                 // Cast volume_set step
var PLAYERISH = ["playing", "paused", "buffering"]
var CAST_NATIVE = "AndroidNativeApp"   // Cast's app id for a native app it only mirrors (no Cast receiver: commands are ignored)
// HA MediaPlayerEntityFeature bits a control needs (HA rejects a service the entity does not support)
var F = { PAUSE: 1, SEEK: 2, VOLUME_SET: 4, VOLUME_MUTE: 8, PREVIOUS: 16, NEXT: 32, VOLUME_STEP: 1024, STOP: 4096, PLAY: 16384 }
var NEEDS = { toggle: F.PLAY | F.PAUSE, previous: F.PREVIOUS, next: F.NEXT, stop: F.STOP, back: F.SEEK, forward: F.SEEK,
              mute: F.VOLUME_MUTE, unmute: F.VOLUME_MUTE, volume: F.VOLUME_SET }

function roleOf(members, adapter) {
    var m = (members || []).filter(function (x) { return x.adapter === adapter })[0]
    return m ? m.id : ""
}
function roles(members) {
    var r = {
        keys: roleOf(members, "remote_androidtv_remote"),
        atv: roleOf(members, "media_player_androidtv_remote"),
        adb: roleOf(members, "media_player_androidtv"),
        cast: roleOf(members, "media_player_cast")
    }
    r.power = r.keys || r.atv || r.adb || r.cast
    return r
}

function attr(st, k) { return st && st.attributes ? st.attributes[k] : undefined }
// the entity's supported_features has all of `bits` (not reported = assume it does)
function supports(st, bits) { var n = attr(st, "supported_features"); return typeof n !== "number" || (n & bits) === bits }
// Cast reports our app's playback (YouTube sent by Cast, or the TV's YouTube app that Cast sees); a native app it only
// mirrors (AndroidNativeApp) never counts
function castActive(s, states) {
    var r = roles(s.members)
    if (!r.cast || !s.castApp || s.castApp === CAST_NATIVE) return false
    var st = states[r.cast]
    return !!st && PLAYERISH.indexOf(st.state) >= 0 && attr(st, "app_id") === s.castApp
}
// the main route (what the card says it drives): cast | keys | adb | atv | ""
function via(s, states) {
    var r = roles(s.members)
    if (castActive(s, states)) return "cast"
    if (r.keys) return "keys"
    if (r.adb) return "adb"
    if (r.atv) return "atv"
    if (r.cast && s.sentVia === "media_player_cast") return "cast"
    return ""
}
// can this media_player do `name` with its services (supported_features; Cast seeks / steps from a known position / level)
function playerCan(st, name, cast) {
    if (name === "volup" || name === "voldown")
        return cast ? supports(st, F.VOLUME_SET) && typeof attr(st, "volume_level") === "number" : supports(st, F.VOLUME_SET) || supports(st, F.VOLUME_STEP)
    if (name === "back" || name === "forward") return cast && supports(st, F.SEEK) && typeof attr(st, "media_position") === "number"
    return !!NEEDS[name] && supports(st, NEEDS[name])
}
// a control's route: { via, id } | null (none can do it). what as in control().
function route(s, states, what) {
    var r = roles(s.members)
    var name = what.indexOf("volume:") === 0 ? "volume" : what
    var castSent = r.cast && s.sentVia === "media_player_cast"
    if (castActive(s, states) && playerCan(states[r.cast], name, true)) return { via: "cast", id: r.cast }
    if (name === "volume" || !KEYS[name === "unmute" ? "mute" : name]) return null
    if (r.keys) return { via: "keys", id: r.keys }
    if (r.adb) return { via: "adb", id: r.adb }
    if (r.atv && playerCan(states[r.atv], name, false)) return { via: "atv", id: r.atv }
    if (castSent && !castActive(s, states) && states[r.cast] === undefined && playerCan(undefined, name, true)) return { via: "cast", id: r.cast }
    return null
}
// what the card can offer now
function caps(s, states) {
    var has = function (w) { return route(s, states, w) !== null }
    return { toggle: has("toggle"), prevNext: has("next") || has("previous"), seek: has("forward"), volumeStep: has("volup"),
             volumeSet: has("volume:0"), mute: has("mute"), stop: has("stop") }
}

function metaState(s, states) {
    var r = roles(s.members)
    if (castActive(s, states)) return states[r.cast]
    return states[r.atv] || states[r.adb] || null
}
// what the card shows: { title, subtitle, playing, position, duration, volume, muted, via }
function view(s, states, now) {
    var meta = metaState(s, states)
    var cast = castActive(s, states)
    var p = s.pend && now < s.pend.until ? s.pend : {}
    var playing = p.playing !== undefined ? p.playing
        : meta && PLAYERISH.indexOf(meta.state) >= 0 ? meta.state !== "paused" : !!s.playing
    var vol = p.volume !== undefined ? p.volume : typeof attr(meta, "volume_level") === "number" ? attr(meta, "volume_level") : (s.volume !== undefined ? s.volume : -1)
    var muted = p.muted !== undefined ? p.muted : typeof attr(meta, "is_volume_muted") === "boolean" ? attr(meta, "is_volume_muted") : !!s.muted
    var title = cast && attr(meta, "media_title") ? String(attr(meta, "media_title")) : s.title
    return {
        title: title, subtitle: s.subtitle || "", playing: playing, volume: vol, muted: muted, via: via(s, states),
        position: cast && typeof attr(meta, "media_position") === "number" ? attr(meta, "media_position") : -1,
        duration: cast && typeof attr(meta, "media_duration") === "number" ? attr(meta, "media_duration") : -1
    }
}

// a control -> { calls: [{ domain, service, data }], expect: { playing?, muted?, volume? }, ends: bool, via } | null
// what: toggle | previous | next | back | forward | volup | voldown | mute | unmute | stop | volume:<0..100>
function control(s, states, what, now) {
    var rt = route(s, states, what)
    if (!rt) return null
    var cur = view(s, states, now || 0)
    var expect = {}
    if (what === "toggle") expect.playing = !cur.playing
    if (what === "mute" || what === "unmute") { expect.muted = what === "mute"; if (cur.muted === expect.muted) return { calls: [], expect: expect, ends: false, via: rt.via } }
    var key = KEYS[what === "unmute" ? "mute" : what]
    var calls = [], id = rt.id, e = { entity_id: id }
    if (rt.via === "keys") calls.push({ domain: "remote", service: "send_command", data: { entity_id: id, command: key } })
    else if (rt.via === "adb") calls.push({ domain: "androidtv", service: "adb_command", data: { entity_id: id, command: "input keyevent KEYCODE_" + key } })
    else if (what.indexOf("volume:") === 0) {
        var lv = Math.max(0, Math.min(100, parseInt(what.slice(7)) || 0)) / 100
        expect.volume = lv
        calls.push({ domain: "media_player", service: "volume_set", data: { entity_id: id, volume_level: lv } })
    }
    else if (what === "toggle") calls.push({ domain: "media_player", service: "media_play_pause", data: e })
    else if (what === "previous") calls.push({ domain: "media_player", service: "media_previous_track", data: e })
    else if (what === "next") calls.push({ domain: "media_player", service: "media_next_track", data: e })
    else if (what === "stop") calls.push({ domain: "media_player", service: "media_stop", data: e })
    else if (what === "mute" || what === "unmute") calls.push({ domain: "media_player", service: "volume_mute", data: { entity_id: id, is_volume_muted: what === "mute" } })
    else if (what === "back" || what === "forward") {
        var pos = rt.via === "cast" && cur.position >= 0 ? cur.position : attr(states[id], "media_position")
        if (typeof pos !== "number") return null
        var to = Math.max(0, pos + (what === "back" ? -SEEK_S : SEEK_S))
        var dur = cur.duration > 0 ? cur.duration : attr(states[id], "media_duration")
        if (typeof dur === "number" && dur > 0) to = Math.min(dur, to)
        calls.push({ domain: "media_player", service: "media_seek", data: { entity_id: id, seek_position: Math.round(to) } })
    } else if (what === "volup" || what === "voldown") {
        var v0 = rt.via === "cast" ? (cur.volume >= 0 ? cur.volume : attr(states[id], "volume_level")) : -1
        if (rt.via === "cast" && typeof v0 === "number" && v0 >= 0) {
            var nv = Math.round(Math.max(0, Math.min(1, v0 + (what === "volup" ? VOL_STEP : -VOL_STEP))) * 100) / 100
            expect.volume = nv
            calls.push({ domain: "media_player", service: "volume_set", data: { entity_id: id, volume_level: nv } })
        } else calls.push({ domain: "media_player", service: what === "volup" ? "volume_up" : "volume_down", data: e })
    } else return null
    return { calls: calls, expect: expect, ends: what === "stop", via: rt.via }
}

// lifetime: the session ends when the TV is off / unavailable / idle for offMs, or another app is in front for awayMs.
// -> { end: "" | "off" | "away", badSince, awaySince }. An entity not read yet keeps the timers as they are.
function judge(s, states, now, offMs, awayMs) {
    var r = roles(s.members)
    var out = { end: "", badSince: s.badSince || 0, awaySince: s.awaySince || 0 }
    var castSent = s.sentVia === "media_player_cast"
    var pid = castSent ? r.cast : r.power
    if (pid && states[pid] !== undefined) {
        var st = states[pid]
        var bad = Cast.isMissing(st) || Cast.isOff(st) || (castSent && st.state === "idle")
        out.badSince = bad ? (out.badSince || now) : 0
    }
    // the foreground app: the remote's current_activity, else a media_player's app_id (Cast: its app id)
    var fg = null, want = castSent ? s.castApp : s.pkg
    if (castSent) { if (r.cast && states[r.cast] !== undefined) fg = attr(states[r.cast], "app_id") }
    else for (var i = 0, ids = [r.keys, r.atv, r.adb]; i < ids.length; i++) {
        if (!ids[i] || states[ids[i]] === undefined) continue
        var a = attr(states[ids[i]], ids[i] === r.keys ? "current_activity" : "app_id")
        if (typeof a === "string" && a !== "") { fg = a; break }
    }
    if (typeof fg === "string" && fg !== "" && want) out.awaySince = fg !== want && !out.badSince ? (out.awaySince || now) : 0
    if (out.badSince && now - out.badSince >= offMs) out.end = "off"
    else if (out.awaySince && now - out.awaySince >= awayMs) out.end = "away"
    return out
}

// a new session from a successful send
function start(o) {
    return {
        v: 1, name: String(o.name || "TV"), kind: o.kind, ref: o.ref || "", title: String(o.title || ""), subtitle: String(o.subtitle || ""),
        artUrl: String(o.artUrl || ""), startSeconds: o.startSeconds || 0, startedAt: o.now || 0,
        pkg: Cast.APPS[o.kind] ? Cast.APPS[o.kind].package : "", castApp: Cast.APPS[o.kind] && Cast.APPS[o.kind].castApp ? Cast.APPS[o.kind].castApp : "",
        members: (o.members || []).map(function (m) { return { id: m.id, adapter: m.adapter } }), sentVia: o.sentVia || "",
        playing: true, muted: false, volume: -1, pend: null, badSince: 0, awaySince: 0
    }
}
// a stored session (tv-session.json) -> session or null
function parse(text) {
    var o
    try { o = JSON.parse(text) } catch (e) { return null }
    if (!o || o.v !== 1 || typeof o.kind !== "string" || !Array.isArray(o.members) || o.members.length === 0) return null
    if (!Cast.APPS[o.kind]) return null
    o.members = o.members.filter(function (m) { return m && typeof m.id === "string" && /^(remote|media_player)\.[a-z0-9_]+$/.test(m.id) && !!Cast.ADAPTERS[m.adapter] })
    return o.members.length > 0 ? o : null
}
// the art to keep: a YouTube thumbnail by id (the browser's cover is a temp file), else the source's own
function artFor(kind, ref, artUrl) {
    if (kind === "youtube" && /^[A-Za-z0-9_-]{11}$/.test(ref)) return "https://i.ytimg.com/vi/" + ref + "/hqdefault.jpg"
    return /^(https?|file):\/\//.test(String(artUrl || "")) ? String(artUrl) : ""
}

// ---- auto-detect: what the TV plays without a send from here (a remote, a phone's cast, the TV's own app) ---------------
// detect(members, states) -> null (nothing to show) | { id (the entity that reports it), title, subtitle, app, appId, playing,
// position (s, at positionAt ms; -1 = unknown), positionAt, duration (-1 = unknown), volume (-1), muted, picture (HA's
// entity_picture: a path on HA or an absolute URL, "" = none), castApp }. Shown only while: the TV's power entity is on
// (not off / standby / unavailable / unknown / unread), some media_player of the TV reports playing / paused / buffering
// (Cast, ADB; Android TV Remote reports only on / off), the app in front is not a home screen / screensaver, and there is a
// title or a known app name (an unrecognised app without a title shows nothing). Prefers the member with a title (Cast,
// ADB, Android TV Remote order); a Cast session left paused behind another app in front is skipped.
var HOME_APPS = /^(com\.google\.android\.(tvlauncher|leanbacklauncher|apps\.tv\.launcherx|apps\.tv\.dreamx|backdrop|tungsten\.setupwraith)|com\.android\.(systemui|tv\.settings|dreams\.[a-z.]+)|com\.amazon\.tv\.launcher|E8C28D3C)$/
var APP_NAMES = {
    "com.google.android.youtube.tv": "YouTube", "com.google.android.youtube.tvmusic": "YouTube Music",
    "com.google.android.youtube.tvunplugged": "YouTube TV", "tv.twitch.android.app": "Twitch",
    "com.github.damontecres.wholphin": "Wholphin", "org.jellyfin.androidtv": "Jellyfin", "com.netflix.ninja": "Netflix",
    "com.amazon.amazonvideo.livingroom": "Prime Video", "com.disney.disneyplus": "Disney+", "com.plexapp.android": "Plex",
    "org.xbmc.kodi": "Kodi", "com.spotify.tv.android": "Spotify", "com.google.android.videos": "Google TV",
    "com.apple.atve.androidtv.appletv": "Apple TV", "233637DE": "YouTube"
}
var CAST_PKG = { "233637DE": "com.google.android.youtube.tv" }     // Cast app id -> the TV app it runs as

function isPackage(s) { return /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/.test(s) || /^[0-9A-F]{8}$/.test(s) }
function appOf(st, key) {
    var id = String(attr(st, key || "app_id") || "")
    var n = String(attr(st, "app_name") || "")
    if (n === id || isPackage(n)) n = ""
    return { id: id, name: n || APP_NAMES[id] || "" }
}
function num(v) { return typeof v === "number" && isFinite(v) ? v : -1 }
// the TV's power entity reads on (anything but off / standby / unavailable / unknown; unread = not on)
function powered(members, states) {
    var p = roles(members).power
    var st = p ? states[p] : undefined
    return st !== undefined && !Cast.isMissing(st) && !Cast.isOff(st)
}
function detect(members, states) {
    var r = roles(members)
    if (!powered(members, states)) return null
    var fg = ""            // the app in front: the remote's current_activity, else a media_player's app_id
    if (r.keys && states[r.keys]) fg = String(attr(states[r.keys], "current_activity") || "")
    for (var i = 0, ids = [r.atv, r.adb]; !fg && i < ids.length; i++) if (ids[i] && states[ids[i]]) fg = String(attr(states[ids[i]], "app_id") || "")
    if (fg && HOME_APPS.test(fg)) return null
    var cands = [r.cast, r.adb, r.atv].filter(function (id) {
        var st = id ? states[id] : null
        if (!st || PLAYERISH.indexOf(st.state) < 0) return false
        var a = String(attr(st, "app_id") || "")
        if (a && HOME_APPS.test(a)) return false
        if (id === r.cast && fg && CAST_PKG[a] && CAST_PKG[a] !== fg) return false     // a cast session behind another app
        return true
    })
    if (cands.length === 0) return null
    var id = cands.filter(function (x) { return !!attr(states[x], "media_title") })[0] || cands[0]
    var st = states[id]
    var app = appOf(st)
    if (!app.name && fg) app = { id: app.id || fg, name: APP_NAMES[fg] || "" }
    var title = String(attr(st, "media_title") || "")
    if (!title && !app.name) return null
    var by = String(attr(st, "media_artist") || attr(st, "media_series_title") || attr(st, "media_album_artist") || "")
    var at = Date.parse(String(attr(st, "media_position_updated_at") || ""))
    return {
        id: id, title: title || app.name, subtitle: by || (title ? app.name : ""), app: app.name, appId: app.id,
        playing: st.state !== "paused", position: num(attr(st, "media_position")), positionAt: isFinite(at) ? at : 0,
        duration: num(attr(st, "media_duration")), volume: num(attr(st, "volume_level")),
        muted: attr(st, "is_volume_muted") === true, picture: String(attr(st, "entity_picture") || attr(st, "media_image_url") || ""),
        castApp: id === r.cast ? app.id : ""
    }
}
// a session-shaped object for caps / control of what detect found (controls drive the TV like a sent session's)
function autoSession(name, members, d) {
    return {
        v: 1, name: String(name || "TV"), kind: "auto", ref: "", title: d.title, subtitle: d.subtitle, artUrl: "", startSeconds: 0,
        startedAt: 0, pkg: "", castApp: d.castApp || "", members: (members || []).map(function (m) { return { id: m.id, adapter: m.adapter } }),
        sentVia: "", playing: d.playing, muted: d.muted, volume: d.volume, pend: null, badSince: 0, awaySince: 0
    }
}
// detect's result with a control's expectation over it (shown until pend.until, then the TV's state wins)
function withPend(d, pend, now) {
    if (!d) return null
    var p = pend && now < pend.until ? pend : {}
    var o = Object.assign({}, d)
    if (p.playing !== undefined) o.playing = p.playing
    if (p.muted !== undefined) o.muted = p.muted
    if (p.volume !== undefined) o.volume = p.volume
    return o
}
// HA's picture -> a URL the card can load (entity_picture is a path on HA with its own access token)
function pictureUrl(base, pic) {
    pic = String(pic || "")
    if (/^https?:\/\//.test(pic)) return pic
    return pic.charAt(0) === "/" && base ? String(base).replace(/\/+$/, "") + pic : ""
}
// what the card shows of a position: extrapolated while playing, clamped to the length
function positionAt(d, now) {
    if (!d || d.position < 0) return 0
    var p = d.position + (d.playing && d.positionAt > 0 ? Math.max(0, now - d.positionAt) / 1000 : 0)
    return d.duration > 0 ? Math.min(d.duration, p) : p
}
