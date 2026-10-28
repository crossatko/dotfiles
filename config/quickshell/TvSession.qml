pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/TvSession.js" as Js

// The Send to TV session ("playing on TV"): begins with a successful send (TvCast.finish), shown as the media source
// TvSource (bar chip, popup card, lock card) whose controls drive the TV through Home Assistant until it ends. Logic and
// the per-integration control mapping: launcher/js/TvSession.js (node tests). Ends on: disconnect (detach, the TV keeps
// playing), stop (stops the TV, then detaches), the TV off / unavailable / idle for offMs, another app in front for
// awayMs, a new send (replaced). The TV's state (power, foreground app; Cast: title, position, volume) is read every
// pollMs while a session exists (one GET per TV entity, nothing without a session); a control shows its expected result at
// once (pend, holdMs), then the TV's own state wins where it reports one (Android TV Remote reports little: the card keeps
// what we sent and our last known play / pause). Persisted in tv-session.json next to tv.json (QS_TVSESSION_FILE), so a
// shell restart keeps it. Dry run (TvPrefs.dryRun): controls are logged, not sent.
// Auto-detect (TvPrefs.autoDetect, default on): without a session, what the TV plays by itself (a remote, a phone's cast,
// the TV's own app) is read from its entities' states pushed over HA's websocket (HaWatch: subscribe_entities, no
// polling; a REST read every autoPollMs only if QtWebSockets is missing) and shown as the same card (`card`, sent: false),
// whose controls drive the TV the same way (no disconnect: nothing to detach). Js.detect decides what counts (on, playing /
// paused, not a home screen, a title or a known app); a gap (track change) is held for gapMs, the TV going off is not.
//   qs ipc call tvsession status | control <what> | disconnect | stop | poll | auto
// Test hook: QS_TVSESSION_TIMES="poll,off,away,hold,gap,autoPoll" ms.
Singleton {
    id: ts

    readonly property string filePath: Quickshell.env("QS_TVSESSION_FILE") || (Appearance.dir + "/tv-session.json")
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    readonly property var times: {
        const t = String(Quickshell.env("QS_TVSESSION_TIMES") || "").split(",").map(Number)
        return { poll: t[0] > 0 ? t[0] : 5000, off: t[1] > 0 ? t[1] : 25000, away: t[2] > 0 ? t[2] : 20000, hold: t[3] > 0 ? t[3] : 3000,
                 gap: t[4] > 0 ? t[4] : 3000, autoPoll: t[5] > 0 ? t[5] : 10000 }
    }

    property var session: null
    property var states: ({})                     // member id -> last read state (null = missing)
    property double now: Date.now()
    readonly property bool active: session !== null
    readonly property var view: session ? Js.view(session, states, now) : null
    readonly property var caps: session ? Js.caps(session, states) : null
    // what the TV card shows (TvSource): the sent session, else what auto-detect found; null = no card
    readonly property var card: session && view && caps
        ? { sent: true, name: session.name, title: view.title, subtitle: view.subtitle, artUrl: session.artUrl, playing: view.playing,
            muted: view.muted, volume: view.volume, live: session.kind === "twitch", caps: caps, position: -1, positionAt: 0, duration: -1 }
        : autoView ? Object.assign({ sent: false, name: autoName, artUrl: Js.pictureUrl(HomeAssistant.base || HomeAssistant.url, autoView.picture),
                                     live: false, caps: autoCaps }, autoView) : null
    property string lastEnd: ""                   // why the last session ended
    property var log: []                          // controls: {at, what, calls, dry}

    function begin(o) {
        session = Js.start(Object.assign({}, o, { now: Date.now(), artUrl: Js.artFor(o.kind, o.ref, o.artUrl) }))
        states = ({})
        lastEnd = ""
        save()
        poll()
    }
    function end(reason) {
        if (!session) return
        session = null
        states = ({})
        lastEnd = reason
        save()
    }
    function disconnect() { end("disconnect") }

    // a control from the card: optimistic first, then the calls (a failure rolls the expectation back)
    function control(what) {
        if (!session) return auto ? controlAuto(what) : "no session"
        if (what === "disconnect") { disconnect(); return "ok" }
        const c = Js.control(session, states, what, Date.now())
        if (!c) { console.log("tvsession: " + what + ": no route on this TV"); return "unsupported" }
        const dry = TvPrefs.dryRun
        log = log.concat([{ at: new Date().toISOString(), what: what, calls: c.calls, dry: dry }]).slice(-30)
        if (Object.keys(c.expect).length > 0) {
            const s = Object.assign({}, session)
            s.pend = Object.assign({}, c.expect, { until: Date.now() + times.hold })
            for (const k of ["playing", "muted", "volume"]) if (c.expect[k] !== undefined) s[k] = c.expect[k]
            session = s
            settle.restart()
        }
        if (c.ends) end("stop")
        if (dry) return "dry run"
        const was = session
        send(what, c, () => {
            if (ts.session && was && ts.session.startedAt === was.startedAt) {   // roll the expectation back
                const s = Object.assign({}, ts.session); s.pend = null; ts.session = s
            }
        })
        return "ok"
    }
    // a control on what auto-detect shows: the same mapping (Js.control on a session-shaped object), its expectation in autoPend
    function controlAuto(what) {
        if (what === "disconnect") return "unsupported"
        const c = Js.control(Js.autoSession(autoName, autoMembers, autoView), autoStates, what, Date.now())
        if (!c) { console.log("tvsession: " + what + ": no route on this TV"); return "unsupported" }
        const dry = TvPrefs.dryRun
        log = log.concat([{ at: new Date().toISOString(), what: what, calls: c.calls, dry: dry, auto: true }]).slice(-30)
        if (Object.keys(c.expect).length > 0) { autoPend = Object.assign({}, c.expect, { until: Date.now() + times.hold }); settle.restart() }
        if (dry) return "dry run"
        send(what, c, () => { ts.autoPend = null })
        return "ok"
    }
    // every call is logged with its outcome ("tvsession: toggle -> remote.send_command (keys): ok" / "...: HTTP 400 <HA's message>")
    function send(what, c, rollback) {
        for (const call of c.calls) {
            const name = what + " -> " + call.domain + "." + call.service + (call.data.command ? " " + call.data.command : "") + " (" + c.via + ")"
            HomeAssistant.request("POST", "/api/services/" + call.domain + "/" + call.service, call.data, (st, txt) => {
                if (st >= 200 && st < 300) { console.log("tvsession: " + name + ": ok"); pollSoon.restart(); return }
                let msg = ""
                try { const o = JSON.parse(txt); msg = o && o.message ? String(o.message) : "" } catch (e) { msg = String(txt || "") }
                console.log("tvsession: " + name + ": " + (st === 0 ? "no reply" : "HTTP " + st) + (msg ? " " + msg.slice(0, 160) : ""))
                HomeAssistant.actionError = (st === 0 ? "No reply" : "HTTP " + st) + " for " + call.domain + "." + call.service
                rollback()
            }, 6000)
        }
    }
    Timer { id: settle; interval: ts.times.hold + 50; onTriggered: { ts.now = Date.now(); ts.autoPend = null; if (ts.session && ts.session.pend) { const s = Object.assign({}, ts.session); s.pend = null; ts.session = s; ts.save() } } }
    Timer { id: pollSoon; interval: 700; onTriggered: { ts.poll(); if (ts.restAuto) ts.pollAuto() } }

    // ---- the TV's state, lifetime ---------------------------------------------------------------------------------
    property int inFlight: 0
    function poll() {
        if (!session || !HomeAssistant.configured || inFlight > 0) return
        const s = session
        const ids = s.members.map(m => m.id)
        inFlight = ids.length
        const got = {}
        for (const id of ids)
            HomeAssistant.request("GET", "/api/states/" + id, null, (st, txt) => {
                if (st === 200) { try { const o = JSON.parse(txt); got[id] = o && o.entity_id === id ? o : null } catch (e) { got[id] = null } }
                else if (st === 404) got[id] = null                         // gone = missing; no reply = unknown (kept)
                if (--ts.inFlight > 0 || ts.session !== s) return
                ts.now = Date.now()
                ts.states = Object.assign({}, ts.states, got)
                const j = Js.judge(ts.session, ts.states, ts.now, ts.times.off, ts.times.away)
                if (j.end !== "") { ts.end(j.end); return }
                if (j.badSince !== ts.session.badSince || j.awaySince !== ts.session.awaySince) {
                    const n = Object.assign({}, ts.session); n.badSince = j.badSince; n.awaySince = j.awaySince; ts.session = n; ts.save()
                }
            })
    }
    Timer { interval: ts.times.poll; repeat: true; running: ts.session !== null && HomeAssistant.configured; onTriggered: ts.poll() }
    Connections {
        target: HomeAssistant
        function onConfiguredChanged() { if (HomeAssistant.configured && ts.session) Qt.callLater(ts.poll) }
    }

    // ---- auto-detect: what the TV plays by itself ------------------------------------------------------------------
    readonly property var autoMembers: TvPrefs.autoDetect && TvPrefs.tv && HomeAssistant.configured ? TvPrefs.tv.entities : []
    readonly property string autoName: TvPrefs.tvName || "TV"
    readonly property bool watching: autoMembers.length > 0
    readonly property bool restAuto: watching && watcher.status === Loader.Error      // no QtWebSockets: REST reads instead
    property var restStates: ({})
    readonly property var autoStates: watcher.item ? watcher.item.entities : restAuto ? restStates : ({})
    readonly property var detected: watching ? Js.detect(autoMembers, autoStates) : null
    property var auto: null                       // detected, held over a short gap (gapMs) while the TV stays on
    property var autoPend: null                   // a control's expected result (playing / muted / volume, until)
    readonly property var autoView: auto ? Js.withPend(auto, autoPend, now) : null
    readonly property var autoCaps: {
        if (!auto) return null
        return Js.caps(Js.autoSession(autoName, autoMembers, auto), autoStates)
    }
    onDetectedChanged: {
        if (detected) { gap.stop(); if (JSON.stringify(detected) !== JSON.stringify(auto)) auto = detected }
        else if (auto && watching && Js.powered(autoMembers, autoStates)) { if (!gap.running) gap.restart() }
        else { gap.stop(); auto = null; autoPend = null }
    }
    Timer { id: gap; interval: ts.times.gap; onTriggered: { if (!ts.detected) { ts.auto = null; ts.autoPend = null } } }
    Loader {
        id: watcher
        active: ts.watching
        source: "HaWatch.qml"
        onLoaded: item.ids = Qt.binding(() => ts.autoMembers.map(m => m.id))
    }
    property int autoInFlight: 0
    function pollAuto() {
        if (!restAuto || autoInFlight > 0) return
        const ids = autoMembers.map(m => m.id)
        autoInFlight = ids.length
        const got = {}
        for (const id of ids)
            HomeAssistant.request("GET", "/api/states/" + id, null, (st, txt) => {
                if (st === 200) { try { const o = JSON.parse(txt); if (o && o.entity_id === id) got[id] = o } catch (e) {} }
                if (--ts.autoInFlight > 0) return
                ts.restStates = got
            })
    }
    Timer { interval: ts.times.autoPoll; repeat: true; triggeredOnStart: true; running: ts.restAuto; onTriggered: ts.pollAuto() }

    // ---- persistence ----------------------------------------------------------------------------------------------
    property string lastText: ""
    function save() { if (!saver.running) Quickshell.execDetached(["mkdir", "-p", ts.dir]); saver.restart() }
    Timer {
        id: saver
        interval: 300
        onTriggered: { const t = ts.session ? JSON.stringify(ts.session) + "\n" : "{}\n"; ts.lastText = t; fileView.setText(t) }
    }
    function applyLoaded(t) {
        if (saver.running || t === lastText) return
        lastText = t
        const s = Js.parse(t)
        const had = session
        session = s
        if (s && (!had || had.startedAt !== s.startedAt)) { states = ({}); Qt.callLater(poll) }
    }
    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: ts.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: ts.applyLoaded(text())
        onLoadFailed: ts.applyLoaded("")
    }

    IpcHandler {
        target: "tvsession"
        function status(): string {
            return JSON.stringify({ active: ts.active, lastEnd: ts.lastEnd, session: ts.session, view: ts.view, caps: ts.caps,
                                    states: Object.keys(ts.states).reduce((o, k) => { const s = ts.states[k]; o[k] = s ? s.state : null; return o }, {}) })
        }
        function control(what: string): string { return ts.control(what) }
        function disconnect(): string { ts.disconnect(); return "ok" }
        function stop(): string { return ts.control("stop") }
        function poll(): string { ts.poll(); return "ok" }
        function log(): string { return JSON.stringify(ts.log) }
        function auto(): string {
            const a = ts.auto ? Object.assign({}, ts.auto, { picture: ts.auto.picture !== "" }) : null   // the picture URL carries an access token
            return JSON.stringify({ watching: ts.watching, live: !!(watcher.item && watcher.item.live), rest: ts.restAuto, auto: a, caps: ts.autoCaps,
                                    states: Object.keys(ts.autoStates).reduce((o, k) => { o[k] = ts.autoStates[k].state; return o }, {}) })
        }
    }
}
