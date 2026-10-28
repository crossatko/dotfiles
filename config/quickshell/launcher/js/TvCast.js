.pragma library

// Send to TV: what is playing (identify) and the Home Assistant calls that open it on the TV (plan). Pure functions, used
// by TvCast.qml (the flow: wake, wait, launch, verify, pause here) and tests/tvcast.test.js. Nothing here talks to HA.
//
// identify(d) -> { kind: "youtube" | "twitch" | "jellyfin", ref, startSeconds, title } | { kind: "pending" } (a browser
// whose tab URL was not looked up yet) | { kind: "unsupported" }. d = { source: "mpris" | "twitch", identity,
// desktopEntry, url (xesam:url), artUrl, tabUrl (bin/browser-tab-url: undefined = not asked, "" = none found), channel
// (Twitch app), position (s), title }. Order: the Twitch app's channel; the player's own URL (mpv: a YouTube / Twitch URL,
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
        link: function (m) { return "https://www.youtube.com/watch?v=" + m.ref + (m.startSeconds > 0 ? "&t=" + m.startSeconds + "s" : "") }
    },
    twitch: {
        package: "tv.twitch.android.app",
        link: function (m) { return "twitch://stream/" + m.ref }
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
        adbAction: "com.github.damontecres.wholphin.PLAYBACK",
        afterOpen: { keys: ["DPAD_CENTER"], delayMs: 2500 },
        link: function (m) { return "wholphin://play?itemId=" + m.ref + (m.startSeconds > 0 ? "&position=" + (m.startSeconds * 1000) : "") }
    }
}
// APPS[kind].afterOpen = { keys: [Android key names], delayMs }: pressed (adapter `keys`) once the app is in front and
// delayMs passed, for apps whose link opens a page instead of playing (YouTube / Twitch links play: none)
// the harmless test: open the YouTube app's home screen
var TEST = { kind: "youtube-home", link: "https://www.youtube.com", package: "com.google.android.youtube.tv" }

var ADAPTERS = {
    // Android TV Remote (androidtv_remote), remote entity: remote.turn_on {activity} sends POWER when off, then the link
    remote_androidtv_remote: {
        label: "Android TV Remote",
        kinds: ["youtube", "twitch", "jellyfin"],
        launchWakes: true,
        wake: null,
        launch: function (id, link) { return [{ domain: "remote", service: "turn_on", data: { entity_id: id, activity: link } }] },
        keys: function (id, keys) { return { domain: "remote", service: "send_command", data: { entity_id: id, command: keys } } },
        verify: "current_activity"
    },
    // Android TV Remote, media_player entity: play_media type url = the same launch command, no power on
    media_player_androidtv_remote: {
        label: "Android TV Remote",
        kinds: ["youtube", "twitch", "jellyfin"],
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
        kinds: ["youtube", "twitch", "jellyfin"],
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

// a URL -> { kind, ref } or null
function parseUrl(u) {
    u = String(u || "")
    var m = /^https?:\/\/(?:www\.|m\.|music\.)?youtube\.com\/watch\?(?:[^#]*&)?v=([A-Za-z0-9_-]{11})(?:[&#]|$)/.exec(u)
        || /^https?:\/\/(?:www\.|m\.)?youtube\.com\/(?:live|shorts|embed)\/([A-Za-z0-9_-]{11})(?:[?&#\/]|$)/.exec(u)
        || /^https?:\/\/youtu\.be\/([A-Za-z0-9_-]{11})(?:[?&#\/]|$)/.exec(u)
    if (m) return { kind: "youtube", ref: m[1] }
    m = /^https?:\/\/(?:www\.|m\.)?twitch\.tv\/([A-Za-z0-9_]{1,25})\/?(?:[?#]|$)/.exec(u)
    if (m && TW_RESERVED.indexOf(m[1].toLowerCase()) < 0) return { kind: "twitch", ref: m[1].toLowerCase() }
    m = JF_ITEM.exec(u)
    if (m && /^https?:\/\//.test(u)) return { kind: "jellyfin", ref: m[1].replace(/-/g, "").toLowerCase() }
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

function startOf(kind, position) {
    if (kind === "twitch") return 0                              // live: the TV joins at the live edge
    var p = Math.floor(Number(position) || 0)
    return p > 0 ? p : 0
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
    return { kind: hit.kind, ref: hit.ref, startSeconds: startOf(hit.kind, d.position), title: title }
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
