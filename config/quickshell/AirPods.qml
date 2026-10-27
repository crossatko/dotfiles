pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/AirPods.js" as Pods

// AirPods state for the AirPods section of the Bluetooth popup and the Bluetooth bar chip. The librepods daemon (systemd user service) writes
// `$XDG_STATE_HOME/librepods/status.json` on every change and removes it when it stops, so there is nothing to poll:
// a watched FileView is the whole read side (parsing in launcher/js/AirPods.js). Writes go through the daemon's
// `librepods-ctl <verb>` (one-shot Process, argv only). Controls are optimistic: a click shows the wanted value at
// once, the status file confirms it (the override is dropped) or, after `settleMs` without confirmation, the real
// value comes back (rollback). Env hooks for tests: QS_AIRPODS_STATUS (status file), QS_AIRPODS_CTL (ctl binary),
// QS_AIRPODS_ASSUME_OUTPUT=1 (make looksLike() true: fixtures have no bluez sink).
Singleton {
    id: root

    readonly property string statusPath: Quickshell.env("QS_AIRPODS_STATUS") ? String(Quickshell.env("QS_AIRPODS_STATUS"))
        : (Quickshell.env("XDG_STATE_HOME") ? String(Quickshell.env("XDG_STATE_HOME")) : Quickshell.env("HOME") + "/.local/state") + "/librepods/status.json"
    readonly property string ctl: Quickshell.env("QS_AIRPODS_CTL") ? String(Quickshell.env("QS_AIRPODS_CTL")) : "librepods-ctl"
    readonly property bool assumeOutput: Quickshell.env("QS_AIRPODS_ASSUME_OUTPUT") === "1"
    readonly property int settleMs: 4000

    property bool daemon: false                    // status file present (daemon running)
    property var raw: Pods.parse("")
    property var pend: ({})                        // optimistic overrides: {mode, adaptive, ear}
    property string error: ""

    readonly property bool connected: daemon && raw.valid && raw.connected
    readonly property string name: raw.name
    readonly property string model: raw.model
    readonly property string title: Pods.title(raw.model)
    readonly property bool headset: raw.headset
    readonly property var left: raw.left
    readonly property var right: raw.right
    readonly property var box: raw.box
    readonly property var max: raw.max
    readonly property var modes: Pods.modes(raw)
    readonly property int mode: pend.mode ?? raw.mode
    readonly property int adaptive: pend.adaptive ?? raw.adaptive
    readonly property int ear: pend.ear ?? raw.ear
    // Case reading on demand: the daemon has no live case level while both pods are out of the case, so the
    // AirPods section asks for one short BLE burst (`case:refresh`) while it is on screen, never otherwise.
    // caseSeenAt = unix seconds of the last live reading (0 none yet, -1 = a daemon without the verb).
    readonly property int caseSeenAt: raw.caseSeenAt
    readonly property bool canRefreshCase: connected && !headset && caseSeenAt >= 0
    function refreshCase() { if (canRefreshCase) run("case:refresh") }

    // does this Pipewire sink look like AirPods the daemon cannot confirm
    // bar chip: lowest bud (or headset) level, -1 = none known; charging = that part is charging
    readonly property int lowest: connected ? Pods.lowest(raw) : -1
    readonly property bool lowestCharging: connected && Pods.lowestCharging(raw)
    function looksLike(sink) { return assumeOutput || !!sink && Pods.looksLikeAirPods(sink.description, sink.name) }

    function setMode(m) {
        const e = modes.find(x => x.value === m)
        if (e) _want("mode", m, e.verb)
    }
    function setAdaptive(v) {            // 0..100, debounced while a slider drags
        adaptiveTarget = Math.max(0, Math.min(100, Math.round(v)))
        _hold("adaptive", adaptiveTarget)
        adaptiveSend.restart()
    }
    function setEar(v) {
        const e = Pods.EAR.find(x => x.value === v)
        if (e) _want("ear", v, e.verb)
    }
    readonly property var earOptions: Pods.EAR

    property int adaptiveTarget: 0
    property var _queue: []

    function _hold(field, value) {
        const p = Object.assign({}, pend)
        p[field] = value
        pend = p
        settle.restart()
    }
    function _want(field, value, verb) {
        if (!daemon) return
        _hold(field, value)
        run(verb)
    }
    // one command at a time; a newer one replaces a waiting one (a slider drag sends many)
    function run(verb) {
        if (verb === "") return
        if (proc.running) {
            // keep every verb in order, but only the newest adaptive level (a slider drag sends many)
            _queue = _queue.filter(v => !(verb.startsWith("adaptive:") && v.startsWith("adaptive:"))).concat([verb])
            return
        }
        proc.command = [ctl, verb]
        proc.running = true
    }
    function _confirm() {
        const p = Object.assign({}, pend)
        let any = false
        for (const k of Object.keys(p)) if (p[k] === raw[k]) { delete p[k]; any = true }
        if (any) pend = p
        if (Object.keys(p).length === 0) settle.stop()
    }
    function _apply(text) {
        daemon = true
        misses = 0
        raw = Pods.parse(text)
        _confirm()
    }
    function _gone() {
        daemon = false
        raw = Pods.parse("")
        pend = ({})
        settle.stop()
    }

    Timer { id: settle; interval: root.settleMs; onTriggered: { root.pend = ({}); stateFile.reload() } }
    Timer { id: adaptiveSend; interval: 150; onTriggered: root.run("adaptive:" + root.adaptiveTarget) }
    Timer { id: errClear; interval: 5000; onTriggered: root.error = "" }
    // the file appears when the daemon starts (a watch on a missing file can miss that): look again while it is absent, but only
    // while something shows it (the Bluetooth chip in a bar layout, or its popup), every 5 s for `fastTries` misses, then once a
    // minute (machines without the daemon); opening the popup starts the quick tries again
    readonly property bool watched: BarWidgets.shown("bluetooth") || Popups.name === "bt"
    readonly property int fastTries: 12
    property int misses: 0
    onWatchedChanged: if (watched && !daemon) { misses = 0; stateFile.reload() }
    Timer {
        interval: root.misses >= root.fastTries ? 60000 : 5000; repeat: true; running: !root.daemon && root.watched
        onTriggered: { root.misses++; stateFile.reload() }
    }

    FileView {
        id: stateFile
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._apply(text())
        onLoadFailed: root._gone()
    }
    Process {
        id: proc
        stderr: StdioCollector { id: errOut }
        onExited: code => {
            if (code !== 0) {
                root.pend = ({})
                root.error = (errOut.text || "librepods-ctl failed").replace(/\s+/g, " ").trim().substring(0, 120)
                errClear.restart()
                stateFile.reload()
            }
            if (root._queue.length > 0) { const v = root._queue[0]; root._queue = root._queue.slice(1); root.run(v) }
        }
    }
}
