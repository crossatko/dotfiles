.pragma library

// Send to TV: what is playing (identify) and the Home Assistant calls that open it on the TV (plan). Pure functions, used
// by TvCast.qml (the flow: wake, wait, launch, verify, pause here) and tests/tvcast.test.js. Nothing here talks to HA.
//
// identify(d) -> { kind: "youtube" | "twitch" | "twitch-vod" | "twitch-clip" | "jellyfin", ref, startSeconds, title } | { kind: "pending" } (a browser
// whose tab URL was not looked up yet) | { kind: "unsupported" }. d = { source: "mpris" | "twitch", identity,
// desktopEntry, url (xesam:url), artUrl, tabUrl (bin/browser-tab-url: undefined = not asked, "" = none found), channel
// (Twitch app), position (s), length (s, 0 = unknown), title }. Order: the Twitch app's channel; the player's own URL (mpv: a YouTube / Twitch URL,
// a Jellyfin stream /Videos/<id>/stream); the cover URL (Firefox: i.ytimg.com/vi/<id>/, Twitch live_user_<login>-);
// a Chromium-family browser: the URL of the tab with this title from the browser's session file. Never a guess.
//
// APPS: the TV app and deep link per kind. ADAPTERS: per HA integration (config entry domain of the picked entity) the
// calls: `launch` (and `launchWakes`: the launch call itself powers the TV on), `wake` (a separate power-on call),
// `verify` (the entity attribute that names the foreground app), `after` (a call once the entity reaches a state).
//
// One TV = one entry (tvGroups): HA lists a TV as several entities on one or more devices (Android TV Remote: a remote.*
// and a media_player.* on one device; Cast: another device). Devices merge into one TV when they share a MAC, or when
// their names (backend words like "- Remote" / "- Google Cast" stripped) or original names + model match, and only while
// that leaves each adapter (entity domain + integration) at most once (two identical TVs stay apart). The adapter is chosen per send
// (pickMember): the first member, in ORDER, whose entity is not unavailable / unknown.

var APPS = {
    youtube: {
        package: "com.google.android.youtube.tv",
        castApp: "233637DE",
        start: "exact",                       // the TV app honours &t= (checked on a device)
        link: function (m) { return "https://www.youtube.com/watch?v=" + m.ref + (m.startSeconds > 0 ? "&t=" + m.startSeconds + "s" : "") }
    },
    twitch: {                                 // live: the TV joins at the live edge
        package: "tv.twitch.android.app",
        start: "live",
        link: function (m) { return "twitch://stream/" + m.ref }
    },
    // past broadcast: the TV app (scheme twitch, authority video) plays even VODs its own lists hide. It ignores every
    // start parameter (?t=600s / 1h0m0s / timestamp= / start= / position=, checked on a device): it resumes from the
    // Twitch account's synced watch progress (the PC's browser, when logged in to the same account, keeps that close to
    // where it was), else from 0. Never Cast: Twitch's cast receiver seeks by downloading from the start.
    "twitch-vod": {
        package: "tv.twitch.android.app",
        start: "account",
        link: function (m) { return "twitch://video/" + m.ref }
    },
    "twitch-clip": {                          // a clip (authority clip, registered by the app; plays from 0)
        package: "tv.twitch.android.app",
        start: "none",
        link: function (m) { return "twitch://clip/" + m.ref }
    },
    // Wholphin (Jellyfin client for Android TV), its Intents.md + services/IntentService.kt: the action decides, the URI
    // host only counts without one. A VIEW intent (all Android TV Remote can send: remote.turn_on activity / play_media
    // url) opens the item's details page; only action com.github.damontecres.wholphin.PLAYBACK plays (ADB can send it,
    // with position=<ms>). So after a VIEW, `afterOpen` presses OK once the page is up: the details page focuses its
    // first play button (Resume when the server has a position, which jellyfin-qs reports while mpv plays; else Play):
    // EpisodeDetails RequestOrRestoreFocus + ExpandablePlayButtons' first item (read from the source; movies assumed
    // alike). Never pressed twice: playback cannot be observed and a second OK would pause it.
    jellyfin: {
        package: "com.github.damontecres.wholphin",
        start: "exact",
        adbAction: "com.github.damontecres.wholphin.PLAYBACK",
        afterOpen: { keys: ["DPAD_CENTER"], delayMs: 2500 },
        link: function (m) { return "wholphin://play?itemId=" + m.ref + (m.startSeconds > 0 ? "&position=" + (m.startSeconds * 1000) : "") }
    }
}
// APPS[kind].start: where the TV starts: "exact" (the link carries startSeconds), "live" (the live edge), "account" (the
// app's own synced resume point, startSeconds is ignored), "none" (from the beginning).
// APPS[kind].afterOpen = { keys: [Android key names], delayMs }: pressed (adapter `keys`) once the app is in front and
// delayMs passed, for apps whose link opens a page instead of playing (YouTube / Twitch links play: none)
// the harmless test: open the YouTube app's home screen
var TEST = { kind: "youtube-home", link: "https://www.youtube.com", package: "com.google.android.youtube.tv" }

// what a native-app launch (deep link) can open; Cast stays YouTube only
var NATIVE_KINDS = ["youtube", "twitch", "twitch-vod", "twitch-clip", "jellyfin"]

var ADAPTERS = {
    // Android TV Remote (androidtv_remote), remote entity: remote.turn_on {activity} sends POWER when off, then the link
    remote_androidtv_remote: {
        label: "Android TV Remote",
        kinds: NATIVE_KINDS,
        launchWakes: true,
        wake: null,
        launch: function (id, link) { return [{ domain: "remote", service: "turn_on", data: { entity_id: id, activity: link } }] },
        keys: function (id, keys) { return { domain: "remote", service: "send_command", data: { entity_id: id, command: keys } } },
        verify: "current_activity"
    },
    // Android TV Remote, media_player entity: play_media type url = the same launch command, no power on
    media_player_androidtv_remote: {
        label: "Android TV Remote",
        kinds: NATIVE_KINDS,
        launchWakes: false,
        wake: function (id) { return { domain: "media_player", service: "turn_on", data: { entity_id: id } } },
        launch: function (id, link) { return [{ domain: "media_player", service: "play_media", data: { entity_id: id, media_content_type: "url", media_content_id: link } }] },
        // keys go through the same TV's remote.* (opts.keyEntity); none = no key presses
        keys: function (id, keys, opts) { return opts && opts.keyEntity ? { domain: "remote", service: "send_command", data: { entity_id: opts.keyEntity, command: keys } } : null },
        verify: "app_id"
    },
    // Android TV over ADB (androidtv): a VIEW intent with the app's package (the only path that names the app)
    media_player_androidtv: {
        label: "Android TV (ADB)",
        kinds: NATIVE_KINDS,
        launchWakes: false,
        wake: function (id) { return { domain: "media_player", service: "turn_on", data: { entity_id: id } } },
        launch: function (id, link, pkg, m, app) {
            var action = app && app.adbAction ? app.adbAction : "android.intent.action.VIEW"
            return [{ domain: "androidtv", service: "adb_command", data: { entity_id: id, command: "am start -a " + action + " -d '" + link + "'" + (pkg ? " " + pkg : "") } }]
        },
        // an app with its own play action needs no key press
        keys: function (id, keys, opts, app) {
            return app && app.adbAction ? null : { domain: "androidtv", service: "adb_command", data: { entity_id: id, command: keys.map(function (k) { return "input keyevent KEYCODE_" + k }).join(" && ") } }
        },
        verify: "app_id"
    },
    // Google Cast: YouTube only (quick play has no start time: a media_seek once it plays); the cast powers the TV on (CEC)
    media_player_cast: {
        label: "Google Cast",
        kinds: ["youtube"],
        launchWakes: true,
        wake: null,
        launch: function (id, link, pkg, m) {
            return [{ domain: "media_player", service: "play_media", data: { entity_id: id, media_content_type: "cast", media_content_id: JSON.stringify({ app_name: "youtube", media_id: m.ref }) } }]
        },
        after: function (id, m) {
            return m.startSeconds > 0 ? [{ state: "playing", call: { domain: "media_player", service: "media_seek", data: { entity_id: id, seek_position: m.startSeconds } } }] : []
        },
        verify: "app_id",
        verifyValue: function (kind) { return APPS[kind] ? APPS[kind].castApp || "" : "" }
    }
}

// adapter preference within one TV: Android TV Remote's remote.* (wakes + opens in one call), its media_player.*, ADB, Cast
var ORDER = ["remote_androidtv_remote", "media_player_androidtv_remote", "media_player_androidtv", "media_player_cast"]

// states
function isMissing(st) { return !st || st.state === "unavailable" || st.state === "unknown" }
function isOff(st) { return !!st && (st.state === "off" || st.state === "standby") }
function isReady(st) { return !!st && !isMissing(st) && !isOff(st) }

// the adapter key for an entity id + its integration (config entry domain), "" = not supported
function adapterFor(entityId, platform) {
    var dom = String(entityId || "").split(".")[0]
    var k = dom + "_" + (platform || "")
    return ADAPTERS[k] ? k : ""
}
function supports(adapterKey, kind) {
    var a = ADAPTERS[adapterKey]
    return !!a && a.kinds.indexOf(kind) >= 0
}

// ---- identification ----------------------------------------------------------------------------------------------
var YT_ID = /^[A-Za-z0-9_-]{11}$/
var TW_LOGIN = /^[A-Za-z0-9_]{1,25}$/
var TW_RESERVED = ["directory", "videos", "settings", "p", "search", "downloads", "jobs", "turbo", "subscriptions",
                   "inventory", "wallet", "drops", "friends", "messages", "following", "popout", "moderator", "prime",
                   "login", "signup", "logout", "store", "bits", "embed", "clip", "clips", "u", "team", "event"]
var JF_ITEM = /\/Videos\/([0-9a-fA-F]{32}|[0-9a-fA-F-]{36})\/stream(?:[.?\/]|$)/

function isBrowser(identity, desktopEntry) {
    return /brave|chrom|vivaldi|edge|opera|firefox|librewolf|zen/i.test(String(identity || "") + " " + String(desktopEntry || ""))
}
// the session-file family bin/browser-tab-url can read ("" = none)
function browserKey(identity, desktopEntry) {
    var s = (String(identity || "") + " " + String(desktopEntry || "")).toLowerCase()
    if (s.indexOf("brave") >= 0) return "brave"
    if (s.indexOf("vivaldi") >= 0) return "vivaldi"
    if (s.indexOf("edge") >= 0) return "edge"
    if (s.indexOf("chromium") >= 0) return "chromium"
    if (s.indexOf("chrome") >= 0) return "chrome"
    return ""
}

// a time parameter -> seconds (0 = none): "754", "754s", "1h2m3s", "12m", "1:02:03"
function timeOf(v) {
    v = decodeURIComponentSafe(String(v || "")).trim().toLowerCase()
    var m = /^(\d+)s?$/.exec(v)
    if (m) return parseInt(m[1], 10)
    m = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(v)
    if (m && (m[1] || m[2] || m[3])) return (parseInt(m[1] || 0, 10) * 3600) + (parseInt(m[2] || 0, 10) * 60) + parseInt(m[3] || 0, 10)
    m = /^(?:(\d+):)?(\d{1,2}):(\d{2})$/.exec(v)
    if (m) return (parseInt(m[1] || 0, 10) * 3600) + (parseInt(m[2], 10) * 60) + parseInt(m[3], 10)
    return 0
}
function decodeURIComponentSafe(s) { try { return decodeURIComponent(s) } catch (e) { return s } }
// the URL's query + fragment parameters: { name: value } (first wins; "#t=90" counts like "?t=90")
function paramsOf(u) {
    var out = {}
    var q = String(u || "").replace(/^[^?#]*/, "").replace(/^[?#]/, "")
    q.split(/[?&#]/).forEach(function (kv) {
        var i = kv.indexOf("="), k = i < 0 ? kv : kv.slice(0, i)
        if (k !== "" && out[k] === undefined) out[k] = i < 0 ? "" : kv.slice(i + 1)
    })
    return out
}
var TW_CLIP = /^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/
var TW_VOD = /^v?(\d{1,15})$/
var YT_HOST = /^https?:\/\/(?:(?:www|m|music)\.)?youtube(?:-nocookie)?\.com\//i
// a URL -> { kind, ref, t (seconds from the URL's time parameter, 0 = none) } or null. kind: youtube | twitch (live) |
// twitch-vod | twitch-clip | jellyfin
function parseUrl(u) {
    u = String(u || "").trim()
    if (!/^https?:\/\//i.test(u)) return null
    var q = paramsOf(u)
    var path = u.replace(/^https?:\/\/[^\/?#]+/i, "").replace(/[?#].*$/, "")
    var host = String((/^https?:\/\/([^\/?#]+)/i.exec(u) || [])[1] || "").toLowerCase().replace(/^[^@]*@/, "").replace(/:\d+$/, "")
    var m, id = ""
    if (YT_HOST.test(u)) {
        if (/^\/watch\/?$/.test(path)) id = q.v || ""
        else if ((m = /^\/(?:live|shorts|embed|v|e)\/([A-Za-z0-9_-]{11})(?:\/|$)/.exec(path))) id = m[1]
    } else if (host === "youtu.be") {
        if ((m = /^\/([A-Za-z0-9_-]{11})\/?$/.exec(path))) id = m[1]
    }
    if (id !== "") return YT_ID.test(id) ? { kind: "youtube", ref: id, t: timeOf(q.t || q.start || q.time_continue || "") } : null
    if (host === "clips.twitch.tv") {
        var slug = path === "/embed" ? decodeURIComponentSafe(q.clip || "") : path.replace(/^\/|\/$/g, "")
        return TW_CLIP.test(slug) && slug !== "embed" ? { kind: "twitch-clip", ref: slug, t: 0 } : null
    }
    if (host === "player.twitch.tv") {
        if (q.video && TW_VOD.test(q.video)) return { kind: "twitch-vod", ref: TW_VOD.exec(q.video)[1], t: timeOf(q.time || q.t || "") }
        if (q.clip && TW_CLIP.test(q.clip)) return { kind: "twitch-clip", ref: q.clip, t: 0 }
        if (q.channel && TW_LOGIN.test(q.channel)) return { kind: "twitch", ref: q.channel.toLowerCase(), t: 0 }
        return null
    }
    if (/^(?:www\.|m\.)?twitch\.tv$/.test(host)) {
        if ((m = /^\/videos\/(\d{1,15})\/?$/.exec(path)) || (m = /^\/[A-Za-z0-9_]{1,25}\/(?:v|video)\/(\d{1,15})\/?$/.exec(path)))
            return { kind: "twitch-vod", ref: m[1], t: timeOf(q.t || "") }
        if ((m = /^\/[A-Za-z0-9_]{1,25}\/clip\/([A-Za-z0-9][A-Za-z0-9_-]{0,99})\/?$/.exec(path)))
            return { kind: "twitch-clip", ref: m[1], t: 0 }
        if ((m = /^\/([A-Za-z0-9_]{1,25})\/?$/.exec(path)) && TW_RESERVED.indexOf(m[1].toLowerCase()) < 0)
            return { kind: "twitch", ref: m[1].toLowerCase(), t: 0 }
        return null
    }
    m = JF_ITEM.exec(u)
    if (m) return { kind: "jellyfin", ref: m[1].replace(/-/g, "").toLowerCase(), t: 0 }
    return null
}
// a cover URL -> { kind, ref } or null
function parseArt(u) {
    u = String(u || "")
    var m = /^https?:\/\/i\d?\.ytimg\.com\/(?:vi|vi_webp)\/([A-Za-z0-9_-]{11})\//.exec(u)
    if (m) return { kind: "youtube", ref: m[1] }
    m = /^https?:\/\/static-cdn\.jtvnw\.net\/previews-ttv\/live_user_([A-Za-z0-9_]{1,25})-/.exec(u)
    if (m) return { kind: "twitch", ref: m[1].toLowerCase() }
    return null
}

// where the TV should start, in whole seconds: the player's position (MPRIS: seconds), else the URL's time parameter;
// live = 0. A position past the known length (an ended video, a player reporting another unit) is dropped.
function startOf(kind, position, length, urlT) {
    if (kind === "twitch" || kind === "twitch-clip") return 0
    var p = Number(position)
    var len = Number(length)
    if (!isFinite(p) || p <= 0) p = 0
    if (p > 0 && isFinite(len) && len > 0 && p >= len) p = 0
    if (p <= 0) p = Number(urlT) > 0 ? Number(urlT) : 0
    return Math.floor(p)
}

function identify(d) {
    d = d || {}
    var title = String(d.title || "")
    if (d.source === "twitch") {
        var ch = String(d.channel || "")
        return TW_LOGIN.test(ch) ? { kind: "twitch", ref: ch.toLowerCase(), startSeconds: 0, title: title || ch } : { kind: "unsupported" }
    }
    if (d.source !== "mpris") return { kind: "unsupported" }
    var hit = parseUrl(d.url) || parseArt(d.artUrl)
    if (!hit && isBrowser(d.identity, d.desktopEntry) && browserKey(d.identity, d.desktopEntry) !== "" && title !== "") {
        if (d.tabUrl === undefined || d.tabUrl === null) return { kind: "pending" }
        hit = parseUrl(d.tabUrl)
        if (hit && hit.kind === "jellyfin") hit = null           // a browser tab never counts as the mpv Jellyfin player
    }
    if (!hit) return { kind: "unsupported" }
    return { kind: hit.kind, ref: hit.ref, startSeconds: startOf(hit.kind, d.position, d.length, hit.t), title: title }
}

// ---- the calls ---------------------------------------------------------------------------------------------------
// media (identify's result, or TEST) -> { adapter, link, launchWakes, wake: call | null, launch: [calls], verify:
// { attr, value } | null, after: [{ state, call }], afterOpen: { delayMs, call } | null } or null when this adapter
// cannot open it. opts: { keyEntity } = the same TV's remote.* (key presses for a media_player.* send)
function plan(adapterKey, entityId, media, opts) {
    var a = ADAPTERS[adapterKey]
    if (!a || !media || !entityId) return null
    var test = media.kind === "youtube-home"
    if (!test && a.kinds.indexOf(media.kind) < 0) return null
    if (test && adapterKey === "media_player_cast") return null   // cast has no "open the app" without a video
    var app = test ? null : APPS[media.kind]
    var link = test ? TEST.link : app.link(media)
    var pkg = test ? TEST.package : app.package
    var value = a.verifyValue ? a.verifyValue(test ? "youtube" : media.kind) : pkg
    return {
        adapter: adapterKey,
        link: link,
        launchWakes: a.launchWakes,
        wake: a.wake ? a.wake(entityId) : null,
        launch: a.launch(entityId, link, pkg, media, app),
        verify: a.verify && value ? { attr: a.verify, value: value } : null,
        after: a.after && !test ? a.after(entityId, media) : [],
        afterOpen: afterOpenOf(a, entityId, app, opts)
    }
}
function afterOpenOf(a, entityId, app, opts) {
    if (!app || !app.afterOpen || !a.keys) return null
    var call = a.keys(entityId, app.afterOpen.keys, opts, app)
    return call ? { delayMs: app.afterOpen.delayMs, call: call } : null
}
// did the TV open the app? true / false, or null when the entity does not say
function opened(st, verify) {
    if (!verify || !st || !st.attributes) return null
    var v = st.attributes[verify.attr]
    if (typeof v !== "string" || v === "") return null
    return v === verify.value
}

// ---- one entry per TV ----------------------------------------------------------------------------------------------
// a device / entity name without the integration word the user (or HA) put in it: "Den TV - Google Cast" -> "Den TV"
var BACKEND_WORDS = /(?:\s*[-\u2013\u2014\u00b7:|(\[]\s*|\s+)(?:android\s*tv\s*remote|android\s*tv\s*\(?adb\)?|google\s*cast|chromecast|cast|remote|adb)\s*[)\]]?\s*$/i
function baseName(s) {
    s = String(s || "").trim()
    var b = s.replace(BACKEND_WORDS, "").trim()
    return b !== "" ? b : s
}
function nameKey(s) { return baseName(s).toLowerCase().replace(/\s+/g, " ") }

// list: [{ id, state (HA state string), platform, device (device id, "" = none), deviceName, nameByUser, manufacturer,
// model, macs: [], friendly }] -> [{ key, name, model, state: "on" | "off" | "unavailable", members: [{ id, adapter }] }]
// (members in ORDER; entities with no adapter dropped; sorted by name)
function tvGroups(list) {
    var devs = [], byDev = {}
    ;(list || []).forEach(function (e) {
        var ad = adapterFor(e.id, e.platform)
        if (!ad) return
        var k = e.device ? "d:" + e.device : "e:" + e.id
        var d = byDev[k]
        if (!d) {
            d = byDev[k] = { key: k, name: baseName(e.nameByUser || e.deviceName || e.friendly || e.id),
                             orig: String(e.deviceName || "").trim().toLowerCase(), model: [e.manufacturer, e.model].filter(Boolean).join(" "),
                             macs: (e.macs || []).map(function (m) { return String(m).toLowerCase() }), platforms: {}, members: [], states: [] }
            devs.push(d)
        }
        d.platforms[ad] = true
        d.members.push({ id: e.id, adapter: ad })
        d.states.push(e.state)
    })
    // union-find over devices
    var parent = devs.map(function (_, i) { return i })
    function root(i) { while (parent[i] !== i) i = parent[i] = parent[parent[i]]; return i }
    function platformsOf(r) {
        var p = {}
        devs.forEach(function (d, i) { if (root(i) === r) for (var k in d.platforms) p[k] = (p[k] || 0) + 1 })
        return p
    }
    function canJoin(a, b) {   // no adapter twice in the merged TV (two identical TVs stay apart)
        var pa = platformsOf(a), pb = platformsOf(b)
        for (var k in pa) if (pb[k]) return false
        return true
    }
    function same(a, b) {
        if (a.macs.some(function (m) { return b.macs.indexOf(m) >= 0 })) return "mac"
        if (nameKey(a.name) === nameKey(b.name)) return "name"
        if (a.orig !== "" && a.orig === b.orig && a.model !== "" && a.model === b.model) return "name"
        return ""
    }
    for (var pass = 0; pass < 2; pass++)            // MAC matches first, then names
        for (var i = 0; i < devs.length; i++) for (var j = i + 1; j < devs.length; j++) {
            var how = same(devs[i], devs[j]), ri = root(i), rj = root(j)
            if (ri === rj || how === "" || (pass === 0 && how !== "mac")) continue
            if (how === "mac" || canJoin(ri, rj)) parent[rj] = ri
        }
    var groups = {}, out = []
    devs.forEach(function (d, i) {
        var r = root(i)
        var g = groups[r]
        if (!g) { g = groups[r] = { key: d.key, name: d.name, model: d.model, members: [], states: [], best: 99 }; out.push(g) }
        d.members.forEach(function (m, n) {
            var rank = ORDER.indexOf(m.adapter)
            if (rank < g.best) { g.best = rank; g.name = d.name; g.model = d.model || g.model; g.key = d.key }   // the preferred device names it
            g.members.push(m); g.states.push(d.states[n])
        })
    })
    return out.map(function (g) {
        var st = g.states.map(function (s) { return { state: s } })
        var state = st.some(isReady) ? "on" : st.some(isOff) ? "off" : "unavailable"
        var members = g.members.slice().sort(function (a, b) { return ORDER.indexOf(a.adapter) - ORDER.indexOf(b.adapter) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0) })
        return { key: g.key, name: g.name, model: g.model, state: state, members: members }
    }).sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0 })
}

// the member to use now: the first (in ORDER) whose entity is not unavailable / unknown / missing; with no state read
// yet the first; all missing: the first (its state says why). states: { entityId: state object | null | undefined }
function pickMember(members, states) {
    members = (members || []).filter(function (m) { return !!ADAPTERS[m.adapter] })
    if (members.length === 0) return null
    states = states || {}
    for (var i = 0; i < members.length; i++) {
        var s = states[members[i].id]
        if (s === undefined || !isMissing(s)) return members[i]
    }
    return members[0]
}

// the button: shown only when this would work (no disabled state)
function shown(o) {
    return !!o && o.configured === true && o.haOk === true && !!o.entity && !isMissing(o.state)
        && supports(o.adapter, o.media ? o.media.kind : "")
}
