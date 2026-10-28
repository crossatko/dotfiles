pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/TvCast.js" as Js

// Send to TV: opens what plays here (a MediaSources source) on the TV through Home Assistant (HomeAssistant.request: the
// same URL / token / transport), then pauses it here. What it is and the calls per HA integration: launcher/js/TvCast.js
// (identify / plan, node tests). Target and options: TvPrefs (Settings > TV). The TV = one physical TV (Js.tvGroups: its
// HA entities across devices); each send uses its preferred entity that is not unavailable (Js.pickMember: Android TV
// Remote remote.*, its media_player.*, ADB, Cast). The media popup's TvButton shows only when this would work (Js.shown):
// HA configured and answering, a TV set and that entity not unavailable / unknown (off / standby counts: waking it is
// the point), a recognised source with an identified id.
// Flow (send): read the TV state -> off/standby: wake (the launch itself where the integration powers on with it, else
// turn_on) -> poll until it is on (wakeMs) -> settle (graceMs) -> launch (again, unless the app is already up) -> check the foreground app where the entity
// reports it (verifyMs; one retry if another app is up) -> calls that wait for a state (Cast: seek once playing) ->
// an app's after-open key press (Js APPS afterOpen: OK on Wholphin's details page) -> pause here (TvPrefs.pauseAfter)
// -> the TV session (TvSession: the card shows and drives the TV). `phase`: "" | "waking" | "opening" | "sent" | "failed" (`error`); a click while busy
// cancels. Dry run (TvPrefs.dryRun) logs the plan instead of sending. Browsers export no URL over MPRIS: the tab's URL
// comes from bin/browser-tab-url (the browser's session file, then its History; YouTube / Twitch URLs only), asked when the
// card shows a title; a miss is asked again every tabRetryMs while the popup is open (tabTriesMax per title, reset when
// the popup reopens), a hit is kept.
// Polls the TV state only while the media popup is open (refreshMs) or a send runs; nothing at rest. Never logs ids,
// URLs or the host.
//   qs ipc call tvcast status | last | log | send | test | cancel | candidates
// Test hooks: QS_TVCAST_TIMES="wake,grace,verify,poll" ms, QS_BROWSER_TAB_URL (the helper).
Singleton {
    id: tc

    readonly property string helper: Quickshell.env("QS_BROWSER_TAB_URL") || (Quickshell.shellDir + "/bin/browser-tab-url")
    readonly property var times: {
        const t = String(Quickshell.env("QS_TVCAST_TIMES") || "").split(",").map(Number)
        return { wake: t[0] > 0 ? t[0] : 25000, grace: t[1] > 0 ? t[1] : 3000, verify: t[2] > 0 ? t[2] : 8000, poll: t[3] > 0 ? t[3] : 1000 }
    }
    readonly property int refreshMs: 10000        // TV state while the media popup is open
    readonly property int sentMs: 2500            // the check shows this long
    readonly property int failedMs: 8000          // the warning glyph (its tooltip says why)
    readonly property int afterMs: 15000          // a state-gated call (Cast seek) waits at most this long
    readonly property int tabRetryMs: 5000        // a browser tab not found yet: asked again this often (popup open)
    readonly property int tabTriesMax: 24         // ... at most this many times per title (2 min), reset on popup open
    readonly property int tabTimeoutMs: 5000      // the helper gets this long

    // the TV: TvPrefs.tv (one TV, its entities in preference order), or an older tv.json's single `entity`
    readonly property var members: {
        const e = TvPrefs.entity, t = TvPrefs.tv
        if (e === "") return []
        if (t && t.entities.some(m => m.id === e)) return t.entities.filter(m => Js.ADAPTERS[m.adapter] !== undefined)
        return [{ id: e, adapter: Js.adapterFor(e, platformFor === e ? platform : "") }]
    }
    readonly property string membersKey: members.map(m => m.id).join(",")
    property var states: ({})                     // member id -> last read state object (null = missing); unread = absent
    readonly property var chosen: Js.pickMember(members, states)
    readonly property string entity: chosen ? chosen.id : members.length > 0 ? members[0].id : ""
    readonly property string adapter: chosen ? chosen.adapter : ""
    // the TV's Android TV Remote remote.* (key presses after a media_player.* send, e.g. OK on Wholphin's page)
    readonly property string keyEntity: { const m = members.find(x => x.adapter === "remote_androidtv_remote"); return m ? m.id : "" }
    readonly property var tvState: entity !== "" && states[entity] ? states[entity] : null
    readonly property string tvName: TvPrefs.tvName || (tvState && tvState.attributes && tvState.attributes.friendly_name ? Js.baseName(tvState.attributes.friendly_name) : "TV")
    property string platform: ""                  // a single-entity (older) TV's integration (config entry domain), "" = unknown
    property string platformFor: ""               // the entity `platform` belongs to
    property bool reachable: false                // the last TV state read got an HTTP reply
    readonly property bool haOk: HomeAssistant.configured && reachable
    readonly property bool watching: Popups.name === "media" && members.length > 0 && HomeAssistant.configured

    property string phase: ""
    property string error: ""
    property string sourceKey: ""                 // the source the current / last flow is for
    readonly property bool busy: phase === "waking" || phase === "opening"
    property int run: 0                           // flow token: a cancel / new send bumps it, stale callbacks drop out
    property string flowEntity: ""                // the entity the running flow talks to (chosen at its start)
    property var log: []                          // last sends (dry or real): {at, dry, adapter, kind, plan, sent: [calls], result}
    property var candidates: []                   // Settings: Js.tvGroups entries [{key, name, model, state, members}]
    property bool candidatesBusy: false
    property var candidatesWaiters: []

    // ---- what plays ---------------------------------------------------------------------------------------------
    property var tabs: ({})                       // browser|title|artist -> the tab URL ("" = none found yet)
    property var tabTries: ({})                   // key -> lookups so far
    property var tabWanted: null                  // the source whose miss the retry timer asks again
    function tabKey(p) { return Js.browserKey(p.identity, p.desktopEntry) + "\t" + (p.trackTitle || "") + "\t" + (p.trackArtist || "") }
    function dataOf(src, tabsMap) {
        if (!src) return null
        if (src.kind === "twitch") return { source: "twitch", channel: src.channel, title: src.title }
        const p = src.mpris
        if (!p) return null
        const md = p.metadata || {}
        return { source: "mpris", identity: p.identity || "", desktopEntry: p.desktopEntry || "", url: String(md["xesam:url"] || ""),
                 artUrl: p.trackArtUrl || "", title: p.trackTitle || "", artist: p.trackArtist || "", position: p.position,
                 tabUrl: (tabsMap || tabs)[tabKey(p)] }
    }
    function identify(src) { return Js.identify(dataOf(src, tabs)) }
    // the button's rule (reactive: reads tvState, reachable, tabs, prefs)
    function shownFor(src) {
        return Js.shown({ configured: HomeAssistant.configured, haOk: haOk, entity: entity, adapter: adapter, state: tvState, media: identify(src) })
    }
    // a browser source whose tab URL is not known yet: ask the helper (one at a time, latest wins). Works for paused
    // players too (the card shows them); the arguments go as argv (no shell: quotes / non-ASCII are safe).
    function lookup(src) {
        if (!src || src.kind !== "mpris" || !src.mpris) return
        const d = dataOf(src, tabs)
        if (Js.identify(d).kind !== "pending") return
        const k = tabKey(src.mpris)
        if (tabProc.running) { if (tabProc.key !== k) tabProc.queued = src; return }
        const t = Object.assign({}, tabTries); t[k] = (t[k] || 0) + 1; tabTries = t
        tabWanted = src
        tabProc.key = k
        tabProc.command = [helper, Js.browserKey(d.identity, d.desktopEntry), d.title, d.artist]
        tabProc.running = true
        tabWatchdog.restart()
    }
    function tabDone(url) {
        tabWatchdog.stop()
        const m = Object.assign({}, tabs)
        const keys = Object.keys(m)
        if (keys.length > 40) delete m[keys[0]]
        m[tabProc.key] = url
        tabs = m
        const q = tabProc.queued
        tabProc.queued = null
        if (q) Qt.callLater(lookup, q)
    }
    // a miss is never final: drop it (the button's `pending` asks again) while the popup shows the source
    function retryMisses(all) {
        const m = Object.assign({}, tabs)
        let changed = false
        for (const k of Object.keys(m)) if (m[k] === "" && (all || (tabTries[k] || 0) < tabTriesMax)) { delete m[k]; changed = true }
        if (all) tabTries = ({})
        if (changed) tabs = m
    }
    readonly property bool tabMissing: {
        const w = tabWanted
        return w !== null && w.mpris !== null && tabs[tabKey(w.mpris)] === ""
    }
    Process {
        id: tabProc
        property string key: ""
        property var queued: null
        stdout: StdioCollector { onStreamFinished: tc.tabDone(text.trim().split("\n")[0] || "") }
    }
    Timer { id: tabWatchdog; interval: tc.tabTimeoutMs; onTriggered: if (tabProc.running) tabProc.running = false }   // stdout then finishes empty = a miss
    Timer {
        interval: tc.tabRetryMs; repeat: true
        running: Popups.name === "media" && tc.tabMissing
        onTriggered: tc.retryMisses(false)
    }
    Connections {
        target: Popups
        function onNameChanged() { if (Popups.name === "media") tc.retryMisses(true) }   // reopened: ask again for every miss
    }

    // ---- the TV's state -----------------------------------------------------------------------------------------
    function putState(id, o) { const m = Object.assign({}, states); m[id] = o; states = m }
    // one entity's state: cb(httpStatus, stateObject | null)
    function readOne(id, cb) {
        if (!HomeAssistant.configured || id === "") { if (cb) cb(0, null); return }
        const key = membersKey
        HomeAssistant.request("GET", "/api/states/" + id, null, (st, txt) => {
            if (key !== tc.membersKey) return
            let o = null
            if (st === 200) { try { o = JSON.parse(txt) } catch (e) { o = null } }
            tc.reachable = st !== 0 && (st < 300 || st === 404)
            if (st !== 0) tc.putState(id, o && o.entity_id === id ? o : null)
            if (cb) cb(st, o && o.entity_id === id ? o : null)
        })
    }
    // every entity of the TV (popup open, Settings, refresh)
    function readState() {
        if (!HomeAssistant.configured || members.length === 0) { states = ({}); reachable = false; return }
        for (const m of members) readOne(m.id)
        if (members.length === 1 && members[0].adapter === "" && platformFor !== members[0].id) detectPlatform(members[0].id)
        if (!migrated) migrate()
    }
    // an older tv.json (only `entity`): find the TV that entity belongs to and save it (same TV, all its entities)
    property bool migrated: false
    function migrate() {
        const e = TvPrefs.entity
        if (migrated || e === "" || (TvPrefs.tv && TvPrefs.tv.entities.some(m => m.id === e))) return
        migrated = true
        loadCandidates(() => {
            const g = tc.candidates.find(c => c.members.some(m => m.id === e))
            if (g && TvPrefs.entity === e) TvPrefs.setTv(g)
        })
    }
    // integration of an entity: the config entry's domain (a read-only template), else a guess for remote.* (only the
    // Android TV Remote integration makes remote entities that launch apps)
    function detectPlatform(id) {
        platformFor = id
        platform = ""
        platformsOf([id], m => { if (tc.platformFor === id) tc.platform = m[id] || "" })
    }
    function platformsOf(ids, cb) {
        const tpl = "{% for id in " + JSON.stringify(ids) + " %}{% set ce = config_entry_id(id) %}{{ id }}\t{{ config_entry_attr(ce, 'domain') if ce else '' }}\n{% endfor %}"
        HomeAssistant.request("POST", "/api/template", { template: tpl }, (st, txt) => {
            const m = {}
            if (st === 200) for (const line of String(txt).split("\n")) {
                const p = line.split("\t")
                if (p.length === 2 && p[1].trim() !== "") m[p[0].trim()] = p[1].trim()
            }
            for (const id of ids) if (!m[id] && id.indexOf("remote.") === 0 && st !== 200) m[id] = "androidtv_remote"
            cb(m)
        })
    }
    // another TV: forget the old one's states (deferred: `members` reads platformFor, set by readState)
    onMembersKeyChanged: Qt.callLater(resetTv)
    function resetTv() {
        states = ({})
        reachable = false
        if (members.length > 0 && HomeAssistant.configured) readState()
    }
    onWatchingChanged: if (watching) readState()
    Timer {
        interval: tc.refreshMs; repeat: true
        running: tc.watching && !tc.busy
        onTriggered: tc.readState()
    }
    Connections {
        target: HomeAssistant
        function onConfiguredChanged() { if (HomeAssistant.configured && tc.members.length > 0) Qt.callLater(tc.readState);   // after HomeAssistant set its base URL
            else { tc.states = ({}); tc.reachable = false } }
    }

    // Settings: one entry per TV (Js.tvGroups) from every remote.* / media_player.* with an integration this can drive and
    // its HA device (read-only template: device id, names, maker, model, MAC); cb() once loaded
    function loadCandidates(cb) {
        if (cb) candidatesWaiters = candidatesWaiters.concat([cb])
        if (!HomeAssistant.configured || candidatesBusy) return
        candidatesBusy = true
        const done = list => {
            tc.candidates = Js.tvGroups(list)
            tc.candidatesBusy = false
            const w = tc.candidatesWaiters
            tc.candidatesWaiters = []
            for (const f of w) f()
        }
        HomeAssistant.request("GET", "/api/states", null, (st, txt) => {
            let arr = []
            if (st === 200) { try { arr = JSON.parse(txt) } catch (e) { arr = [] } }
            const found = (Array.isArray(arr) ? arr : []).filter(s => s && /^(remote|media_player)\./.test(s.entity_id))
            if (found.length === 0) { done([]); return }
            const byId = {}
            for (const s of found) byId[s.entity_id] = s
            tc.devicesOf(found.map(s => s.entity_id), info => done(found.map(s => {
                const i = info[s.entity_id] || {}
                return { id: s.entity_id, state: s.state, friendly: (s.attributes && s.attributes.friendly_name) || "",
                         platform: i.platform || "", device: i.device || "", deviceName: i.deviceName || "", nameByUser: i.nameByUser || "",
                         manufacturer: i.manufacturer || "", model: i.model || "", macs: i.macs || [] }
            })))
        })
    }
    // ids -> { id: { platform, device, deviceName, nameByUser, manufacturer, model, macs } } (one read-only template);
    // a template error falls back to the integration only (each entity its own device)
    function devicesOf(ids, cb) {
        const tpl = "[{% for id in " + JSON.stringify(ids) + " %}{% set d = device_id(id) %}{% set ce = config_entry_id(id) %}"
            + "{\"id\": {{ id | tojson }}, \"platform\": {{ (config_entry_attr(ce, 'domain') if ce else '') | tojson }}, "
            + "\"device\": {{ (d or '') | tojson }}, \"deviceName\": {{ ((device_attr(d, 'name') or '') if d else '') | tojson }}, "
            + "\"nameByUser\": {{ ((device_attr(d, 'name_by_user') or '') if d else '') | tojson }}, "
            + "\"manufacturer\": {{ ((device_attr(d, 'manufacturer') or '') if d else '') | tojson }}, "
            + "\"model\": {{ ((device_attr(d, 'model') or '') if d else '') | tojson }}, "
            + "\"connections\": {{ ((device_attr(d, 'connections') or []) | list if d else []) | map('list') | list | tojson }}}"
            + "{{ ',' if not loop.last }}{% endfor %}]"
        HomeAssistant.request("POST", "/api/template", { template: tpl }, (st, txt) => {
            let arr = null
            if (st === 200) { try { arr = JSON.parse(txt) } catch (e) { arr = null } }
            if (!Array.isArray(arr)) {
                tc.platformsOf(ids, m => { const out = {}; for (const id of ids) out[id] = { platform: m[id] || "" }; cb(out) })
                return
            }
            const out = {}
            for (const e of arr) if (e && typeof e.id === "string")
                out[e.id] = { platform: e.platform || "", device: e.device || "", deviceName: e.deviceName || "", nameByUser: e.nameByUser || "",
                              manufacturer: e.manufacturer || "", model: e.model || "",
                              macs: (Array.isArray(e.connections) ? e.connections : []).filter(c => Array.isArray(c) && c[0] === "mac").map(c => String(c[1])) }
            cb(out)
        }, 15000)
    }
    function stateOf(c) {   // a candidate's live state where it is the picked TV, else as listed
        return c.members.some(m => m.id === tc.entity) && tc.tvState ? (Js.isReady(tc.tvState) ? "on" : Js.isOff(tc.tvState) ? "off" : "unavailable") : c.state
    }

    // ---- sending ------------------------------------------------------------------------------------------------
    Timer { id: waitT; property var fn: null; onTriggered: { const f = fn; fn = null; if (f) f() } }
    function after(ms, token, f) { waitT.fn = () => { if (token === tc.run) f() }; waitT.interval = Math.max(1, ms); waitT.restart() }
    Timer { id: clearT; onTriggered: if (!tc.busy) { tc.phase = ""; tc.error = "" } }

    property var entry: null                      // the log entry of the running flow
    property var flowMedia: null                  // what the running flow sends (identify's result; TEST for the test)
    property var flowInfo: null                   // the source's title / subtitle / art for the TV session
    function note(call) { if (entry) entry.sent.push({ domain: call.domain, service: call.service, data: call.data }) }
    function pushLog(e) { log = log.concat([e]).slice(-20) }
    function post(token, call, cb) {
        note(call)
        HomeAssistant.request("POST", "/api/services/" + call.domain + "/" + call.service, call.data, (st, txt) => {
            if (token !== tc.run) return
            cb(st >= 200 && st < 300, st)
        }, 10000)
    }
    function postAll(token, calls, cb, i) {
        i = i || 0
        if (i >= calls.length) { cb(true, 200); return }
        post(token, calls[i], (ok, st) => { if (!ok) cb(false, st); else postAll(token, calls, cb, i + 1) })
    }
    function httpError(st) { return st === 0 ? "No reply from Home Assistant" : "Home Assistant: HTTP " + st }

    function cancel() {
        if (!busy) return
        run++
        waitT.stop()
        if (entry) { entry.result = "cancelled"; entry = null }
        phase = ""
        error = ""
    }
    function fail(token, msg) {
        if (token !== run) return
        if (entry) { entry.result = "failed: " + msg; entry = null }
        phase = "failed"
        error = msg
        clearT.interval = failedMs
        clearT.restart()
        log = log.slice()
    }
    function finish(token, src) {
        if (token !== run) return
        if (entry) { entry.result = "sent"; entry = null }
        if (TvPrefs.pauseAfter && src) pauseHere(src)
        // the TV session: the card now shows and drives the TV (a new send replaces it)
        if (src && flowMedia && flowMedia.kind !== "youtube-home")
            TvSession.begin({ name: tvName, kind: flowMedia.kind, ref: flowMedia.ref, startSeconds: flowMedia.startSeconds || 0,
                              title: flowInfo ? flowInfo.title : "", subtitle: flowInfo ? flowInfo.subtitle : "", artUrl: flowInfo ? flowInfo.artUrl : "",
                              members: members, sentVia: adapter })
        phase = "sent"
        clearT.interval = sentMs
        clearT.restart()
        log = log.slice()
    }
    function pauseHere(src) {
        if (src.kind === "mpris" && src.mpris) { if (src.mpris.isPlaying && src.mpris.canPause) src.mpris.pause() }
        else if (src.playing && src.canToggle) src.togglePlaying()
    }

    // the button: send, or cancel a running send
    function press(src) {
        if (busy) { cancel(); return }
        send(src)
    }
    function send(src) {
        if (!src) return "no source"
        if (src.kind === "mpris" && src.mpris && typeof src.mpris.positionChanged === "function") src.mpris.positionChanged()   // fresh position
        const media = identify(src)
        if (!Js.supports(adapter, media.kind)) return "unsupported"
        sourceKey = src.key
        return start(media, src)
    }
    function test() { return start(Js.TEST, null) }
    function start(media, src) {
        const p = Js.plan(adapter, entity, media, { keyEntity: keyEntity })
        if (!p) return "unsupported"
        const token = ++run
        flowEntity = entity
        flowMedia = media
        flowInfo = src ? { title: src.title || media.title || "", subtitle: src.subtitle || "", artUrl: src.artUrl || "" } : null
        clearT.stop()
        error = ""
        entry = { at: new Date().toISOString(), dry: TvPrefs.dryRun, adapter: adapter, kind: media.kind, ref: media.ref || "",
                  startSeconds: media.startSeconds || 0, plan: p, sent: [], result: "" }
        pushLog(entry)
        if (TvPrefs.dryRun) {
            entry.result = "dry run"
            entry = null
            phase = "sent"
            clearT.interval = sentMs
            clearT.restart()
            log = log.slice()
            return "dry run"
        }
        phase = "opening"
        readOne(tc.flowEntity, (st, o) => {
            if (token !== tc.run) return
            if (st !== 200) { fail(token, st === 404 ? "TV entity not found" : httpError(st)); return }
            if (Js.isMissing(o)) { fail(token, "TV unavailable"); return }
            if (Js.isOff(o)) wake(token, p, src)
            else launch(token, p, src, 0)
        })
        return "started"
    }
    function wake(token, p, src) {
        phase = "waking"
        const first = p.launchWakes ? p.launch : (p.wake ? [p.wake] : [])
        postAll(token, first, (ok, st) => {
            if (!ok) { fail(token, httpError(st)); return }
            waitReady(token, Date.now() + times.wake, () => after(times.grace, token, () => {
                // the launch that woke it may have landed during boot: open it (again) unless the app is already up
                if (p.launchWakes) readOne(tc.flowEntity, (st2, o) => {
                    if (token !== tc.run) return
                    if (Js.opened(o, p.verify) === true) afterSteps(token, p, src)
                    else launch(token, p, src, 0)
                })
                else launch(token, p, src, 0)
            }))
        })
    }
    function waitReady(token, deadline, cb) {
        readOne(tc.flowEntity, (st, o) => {
            if (token !== tc.run) return
            if (Js.isReady(o)) { cb(); return }
            if (Date.now() >= deadline) { fail(token, "TV did not wake"); return }
            after(times.poll, token, () => waitReady(token, deadline, cb))
        })
    }
    function launch(token, p, src, attempt) {
        phase = "opening"
        postAll(token, p.launch, (ok, st) => {
            if (!ok) { fail(token, httpError(st)); return }
            if (!p.verify) { afterSteps(token, p, src); return }
            verify(token, p, Date.now() + times.verify, res => {
                if (res === false && attempt === 0) launch(token, p, src, 1)        // ignored (still booting?): once more
                else if (res === false) fail(token, "App did not open")
                else afterSteps(token, p, src)
            })
        })
    }
    function verify(token, p, deadline, cb) {
        after(times.poll, token, () => readOne(tc.flowEntity, (st, o) => {
            if (token !== tc.run) return
            const r = Js.opened(o, p.verify)
            if (r === true || Date.now() >= deadline) cb(r)
            else verify(token, p, deadline, cb)
        }))
    }
    function afterSteps(token, p, src, i) {
        i = i || 0
        if (i >= p.after.length) { openKeys(token, p, src); return }
        const s = p.after[i]
        const deadline = Date.now() + afterMs
        const step = () => readOne(tc.flowEntity, (st, o) => {
            if (token !== tc.run) return
            if (o && o.state === s.state) post(token, s.call, () => afterSteps(token, p, src, i + 1))   // a failed seek still counts as sent
            else if (Date.now() >= deadline) afterSteps(token, p, src, i + 1)
            else after(times.poll, token, step)
        })
        step()
    }

    // an app whose link opens a page (Wholphin: the item's details): press OK once it had time to show (one press, never
    // repeated: a second one would pause what started); a failed press still counts as sent
    function openKeys(token, p, src) {
        if (!p.afterOpen) { finish(token, src); return }
        after(p.afterOpen.delayMs, token, () => post(token, p.afterOpen.call, () => finish(token, src)))
    }

    IpcHandler {
        target: "tvcast"
        function status(): string {
            const src = MediaSources.current
            const m = src ? tc.identify(src) : { kind: "none" }
            return JSON.stringify({ name: tc.tvName, entities: tc.members.length, entity: tc.entity, adapter: tc.adapter, configured: HomeAssistant.configured,
                                    reachable: tc.reachable, tv: tc.tvState ? tc.tvState.state : null, dryRun: TvPrefs.dryRun,
                                    pauseAfter: TvPrefs.pauseAfter, phase: tc.phase, error: tc.error, media: m,
                                    shown: src ? tc.shownFor(src) : false })
        }
        function last(): string { return JSON.stringify(tc.log.length > 0 ? tc.log[tc.log.length - 1] : null) }
        function log(): string { return JSON.stringify(tc.log) }
        function send(): string { return tc.send(MediaSources.current) }
        function test(): string { return tc.test() }
        function cancel(): string { tc.cancel(); return "ok" }
        function refresh(): string { tc.readState(); return "ok" }
        function candidates(): string { tc.loadCandidates(); return JSON.stringify(tc.candidates) }
    }
}
