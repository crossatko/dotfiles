.pragma library
.import "TvCast.js" as Cast

// Play on PC (the reverse of Send to TV): what the TV plays -> the PC command that plays it here, at the TV's position.
// Pure functions (tests/tvpc.test.js), used by TvPc.qml (the flow: resolve, look up, launch, pause the TV). Nothing here
// talks to HA or starts a process.
//
// resolve(o, now) -> { state: "ready" | "lookup" | "none", kind, ref, start (s, -1 = unknown), how, lookup, want, origin,
// reason }. o = the TV card's facts: { sent (a session sent from here: kind / ref known), kind, ref, origin (the PC player
// it came from), title (what we sent / the TV's), subtitle, tvTitle / tvArtist (the TV's own: Cast or its mirror, "" = none),
// appId (package or Cast app id in front), app (its name), position (s at positionAt ms, -1 = unknown), positionAt,
// duration (s, -1), playing }.
// how = where the PC starts: "exact" (the TV's position), "account" (Twitch's synced watch progress: the browser resumes
// there when logged in), "server" (Jellyfin's resume point, which the TV app reports), "live" (the live edge), "start".
// lookup = "youtube" (yt-dlp search: exact title + channel (+ length) only) | "jellyfin" (`jellyfin-qs playing`: the
// user's other client playing an item) | "". reason = why it cannot (state "none"), a short sentence for the tooltip.
//
// What each TV app tells (Home Assistant: Android TV Remote = power + app in front; Cast = a cast session, or its mirror of
// a native app's media session: state, position, length, title where the app sets one, never a content id):
//   YouTube (TV app): title, channel, position, length; no video id -> a yt-dlp search that must match exactly.
//   Twitch (TV app): position only (no title, no channel, no video id) -> only what was sent from here.
//   Wholphin / Jellyfin: the item is on the Jellyfin server (its session) -> `jellyfin-qs playing`.

var YT_APPS = ["com.google.android.youtube.tv", "233637DE", "2C6A6E3D"]
var JF_APPS = ["com.github.damontecres.wholphin", "org.jellyfin.androidtv"]
var TW_APPS = ["tv.twitch.android.app"]

function norm(s) { return String(s || "").replace(/\s+/g, " ").trim().toLowerCase() }
// the TV's position now: extrapolated while playing, clamped to the length; -1 = unknown
function positionNow(o, now) {
    if (!o || typeof o.position !== "number" || !isFinite(o.position) || o.position < 0) return -1
    var p = o.position + (o.playing && o.positionAt > 0 && now > o.positionAt ? (now - o.positionAt) / 1000 : 0)
    if (o.duration > 0) p = Math.min(o.duration, p)
    return Math.floor(p)
}
// the same video's title as two players show it ("(2) Title - YouTube" vs "Title"): one contains the other
function sameTitle(a, b) {
    var x = norm(a).replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+youtube$/, ""), y = norm(b).replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+youtube$/, "")
    return x !== "" && y !== "" && (x.indexOf(y) >= 0 || y.indexOf(x) >= 0)
}
function none(reason) { return { state: "none", kind: "", ref: "", start: -1, how: "", lookup: "", want: null, origin: "", reason: reason } }
function ready(kind, ref, start, how, origin) { return { state: "ready", kind: kind, ref: ref, start: start, how: how, lookup: "", want: null, origin: origin || "", reason: "" } }
function lookupOf(kind, start, want, origin) { return { state: "lookup", kind: kind, ref: "", start: start, how: start >= 0 ? "exact" : "start", lookup: kind, want: want, origin: origin || "", reason: "" } }

function resolve(o, now) {
    if (!o) return none("Nothing plays on the TV")
    var pos = positionNow(o, now || 0)
    if (o.sent && Cast.APPS[o.kind] && o.ref) {
        // the TV moved on to another YouTube video (its title differs from what we sent): find that one
        if (o.kind === "youtube" && o.tvTitle && !sameTitle(o.tvTitle, o.title))
            return Object.assign(lookupOf("youtube", pos, { title: o.tvTitle, artist: o.tvArtist || "", duration: o.duration }, o.origin),
                                 { fallbackRef: o.ref })   // no exact match (a translated title?): the video we sent
        if (o.kind === "twitch") return ready("twitch", o.ref, -1, "live", o.origin)
        if (o.kind === "twitch-clip") return ready("twitch-clip", o.ref, 0, "start", o.origin)
        if (o.kind === "twitch-vod") return ready("twitch-vod", o.ref, pos, pos >= 0 ? "exact" : "account", o.origin)
        if (o.kind === "jellyfin") return ready("jellyfin", o.ref, pos, pos >= 0 ? "exact" : "server", o.origin)
        return ready(o.kind, o.ref, pos >= 0 ? pos : 0, pos >= 0 ? "exact" : "start", o.origin)
    }
    var app = String(o.appId || "")
    var name = String(o.app || "")
    if (YT_APPS.indexOf(app) >= 0 || (!app && name === "YouTube")) {
        var t = o.tvTitle || o.title
        if (!t || norm(t) === "youtube") return none("YouTube on the TV does not say which video it plays")
        return lookupOf("youtube", pos, { title: t, artist: o.subtitle || "", duration: o.duration }, "")
    }
    if (JF_APPS.indexOf(app) >= 0 || name === "Wholphin" || name === "Jellyfin")
        return lookupOf("jellyfin", pos, { title: o.tvTitle || o.title || "", duration: o.duration }, "")
    if (TW_APPS.indexOf(app) >= 0 || name === "Twitch")
        return none("Twitch's TV app does not say what it plays; only a stream sent from here can move back")
    return none((name || "This app") + " cannot play on this PC")
}

// yt-dlp search results [{ id, title, channel, uploader, duration }] -> the video id that is exactly the TV's (same
// title, same channel when the TV names one, length within 3 s when both have one), "" = none (never a near miss)
function matchYoutube(results, want) {
    if (!want || !want.title) return ""
    var t = norm(want.title), a = norm(want.artist)
    var hit = (results || []).filter(function (r) {
        if (!r || !/^[A-Za-z0-9_-]{11}$/.test(String(r.id || ""))) return false
        if (norm(r.title) !== t) return false
        if (a && norm(r.channel || r.uploader) !== a) return false
        return !(want.duration > 0 && r.duration > 0 && Math.abs(r.duration - want.duration) > 3)
    })
    return hit.length > 0 ? String(hit[0].id) : ""
}

// `jellyfin-qs playing --json` rows (newest first) -> { id, position } of the TV's Jellyfin client, null = none. Prefers
// a TV client (Wholphin / Jellyfin for Android TV), then the row whose title the TV shows; no TV client and no title match =
// null.
function pickJellyfin(rows, want) {
    rows = (rows || []).filter(function (r) { return r && /^[0-9a-fA-F-]{32,36}$/.test(String(r.id || "")) })
    if (rows.length === 0) return null
    var tv = rows.filter(function (r) { return /wholphin|android ?tv|jellyfin.*tv/i.test(String(r.client || "")) })
    var pool = tv.length > 0 ? tv : rows
    var t = want ? norm(want.title) : ""
    var named = t ? pool.filter(function (r) { var n = norm(r.name), f = norm(r.title); return (n && t.indexOf(n) >= 0) || (f && (f === t || f.indexOf(t) >= 0)) }) : []
    if (tv.length === 0 && named.length === 0) return null       // only another client (a phone) with another item: not the TV
    var r = named[0] || pool[0]
    return { id: String(r.id).replace(/-/g, "").toLowerCase(), position: typeof r.position_s === "number" && r.position_s >= 0 ? r.position_s : -1 }
}

// a lookup's answer -> resolve's result made ready (or none with a reason)
function settle(t, answer) {
    if (!t || t.state !== "lookup") return t
    if (t.lookup === "youtube") {
        var id = typeof answer === "string" ? answer : ""
        if (!id && t.fallbackRef) id = t.fallbackRef
        return id ? ready("youtube", id, t.start >= 0 ? t.start : 0, t.start >= 0 ? "exact" : "start", t.origin)
                  : none("No YouTube video matches the TV's title exactly")
    }
    if (t.lookup === "jellyfin") {
        if (!answer || !answer.id) return none("The Jellyfin server has no session playing on the TV")
        var p = t.start >= 0 ? t.start : answer.position
        return ready("jellyfin", answer.id, p, p >= 0 ? "exact" : "server", "")
    }
    return none("Nothing to look up")
}

function hms(s) {
    s = Math.max(0, Math.floor(s))
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
    return (h > 0 ? h + "h" : "") + (h > 0 || m > 0 ? m + "m" : "") + x + "s"
}
// the PC's URL for a target (what the browser / mpv opens)
function urlOf(t) {
    var s = t.start > 0 ? t.start : 0
    if (t.kind === "youtube") return "https://www.youtube.com/watch?v=" + t.ref + (s > 0 ? "&t=" + s + "s" : "")
    if (t.kind === "twitch") return "https://www.twitch.tv/" + t.ref
    if (t.kind === "twitch-vod") return "https://www.twitch.tv/videos/" + t.ref + (s > 0 ? "?t=" + hms(s) : "")
    if (t.kind === "twitch-clip") return "https://clips.twitch.tv/" + t.ref
    return ""
}
// a ready target -> { argv, player } | null. env = { twitchApp (twitch-qs-mpv path, "" = none), font (UI font family), jellyfin (argv prefix that
// runs jellyfin-qs) }. Players follow the repo's own: YouTube back to where it came from (mpv, else the default browser);
// Twitch live = twitch-qs-mpv watch (as the launcher), the browser when it came from one; a past broadcast / clip = the
// browser (twitch-qs-mpv takes no start position; Twitch's site resumes from the account); Jellyfin = jellyfin-qs play.
function command(t, env) {
    if (!t || t.state !== "ready" || !t.ref) return null
    env = env || {}
    var url = urlOf(t)
    if (t.kind === "youtube") {
        if (t.origin === "mpv") return { argv: ["mpv"].concat(t.start > 0 ? ["--start=" + t.start] : [], ["--", url]), player: "mpv" }
        return { argv: ["xdg-open", url], player: "browser" }
    }
    if (t.kind === "twitch") {
        if (t.origin !== "browser" && env.twitchApp) return { argv: ["env", "TWITCH_QS_FONT=" + (env.font || "Paper Mono"), env.twitchApp, "watch", t.ref], player: "Twitch app" }
        return { argv: ["xdg-open", url], player: "browser" }
    }
    if (t.kind === "twitch-vod" || t.kind === "twitch-clip") return { argv: ["xdg-open", url], player: "browser" }
    if (t.kind === "jellyfin") {
        if (!env.jellyfin || env.jellyfin.length === 0) return null
        return { argv: env.jellyfin.concat(["play", t.ref], t.start >= 0 ? ["--start", String(t.start)] : ["--resume"]), player: "mpv" }
    }
    return null
}

// the button's hover text for a target: where it plays and from where
function describe(t) {
    if (!t) return ""
    if (t.state === "none") return t.reason
    var at = t.how === "exact" && t.start > 0 ? " at " + clock(t.start)
        : t.how === "account" ? " (resumes where your Twitch account left off)"
        : t.how === "server" ? " (from Jellyfin's resume point)"
        : t.how === "live" ? " (live)" : ""
    return "Play on this PC" + at
}
function clock(s) {
    s = Math.floor(s)
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x
}
