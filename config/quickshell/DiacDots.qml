import QtQuick
import "launcher/js/DiacScene.js" as Scene

// The diacritics pill's picture (DiacPill): the approved "Flare" scene (launcher/js/DiacScene.js) drawn by DotGridCanvas in the
// shell's colours, advanced by a plain Timer (like DotSwoosh: a running QML animation would keep Qt's animation driver on and make
// every shell window redraw each frame).
//   kind    words (the text's real words) | neutral (generic loop, no text) | loading (the neutral loop, dim and slow)
//   phase   working | done | failed | unsupported (the end states fade the picture, then draw their icon)
//   text    the words to show (kind words)
//   replayText  the fixed text (kind words): on phase done it is replayed first (Scene.replayPlan: every chunk with its marks flaring
//           in, at most 1.5 s), then the check draws; a new phase (the next run) cancels the replay. `busy` = replay or check still
//           playing (the pill stays open for it, the service goes idle sooner)
//   running the clock runs and the picture redraws (false while the pill is hidden)
// restart() starts the working picture from its first chunk. Reduced motion (Motion.reduced): the end icons still draw, the working
// picture shows its first chunk and neutral loop frozen at one frame.
Item {
    id: dd
    property string kind: "words"
    property string phase: "working"
    property string text: ""
    property string replayText: ""
    property bool running: true

    // the replay of the fixed text on done
    property bool replaying: false
    property bool replayed: false          // the replay has played in this done phase: the picture is its last frame
    property var plan: ({ items: [], total: 0 })
    property var replayPrep: null
    property real rT: 0                    // seconds in the replay
    readonly property real checkHold: 1.0  // the check stays this long after the replay (as long as the service's done state did)
    readonly property bool busy: replaying || (replayed && phase === "done" && sT < checkHold)
    function startReplay() {
        replaying = false; replayed = false
        if (kind !== "words" || replayText === "" || Motion.reduced) return
        replayPrep = Scene.prepare(replayText)
        plan = Scene.replayPlan(replayPrep)
        if (!plan.items.length) return
        rT = 0; replaying = true; replayed = true
    }

    readonly property bool working: phase === "working" || replaying
    readonly property var prep: Scene.prepare(text)
    property real t: 0                    // seconds in the working picture
    property real sT: 0                   // seconds in the current end state
    property double last: 0

    // colours: letters and marks while working, the state's tint in the end states (the prototype's: accent / green / red / dim, 25 % to white)
    readonly property color accentLight: Qt.tint(Theme.accent, Qt.rgba(1, 1, 1, 0.3))
    readonly property color stateColor: Qt.tint(phase === "done" ? Theme.green : phase === "failed" ? Theme.red : Theme.fgDim, Qt.rgba(1, 1, 1, 0.25))

    function restart() { replaying = false; replayed = false; t = 0; sT = 0; last = Date.now(); refresh() }
    function refresh() {
        dots.grid = replayed ? Scene.scene("replay", replaying ? "working" : phase, rT, sT, replayPrep, plan)
                             : Scene.scene(kind, phase, t, sT, prep, null)
    }
    onPhaseChanged: {
        sT = 0
        if (phase === "done") startReplay(); else { replaying = false; replayed = false }
        refresh()
    }
    onKindChanged: refresh()
    onPrepChanged: refresh()

    Timer {
        interval: 16
        repeat: true
        running: dd.running && dd.visible
        onRunningChanged: dd.last = Date.now()
        onTriggered: {
            const now = Date.now(), dt = Math.min(0.1, (now - dd.last) / 1000)
            dd.last = now
            if (Motion.reduced && dd.working) return
            dd.t = (dd.t + dt) % 3600
            if (dd.replaying) {
                dd.rT += dt
                if (dd.rT >= dd.plan.total) { dd.rT = dd.plan.total; dd.replaying = false; dd.sT = 0 }
            } else dd.sT += dt
            dd.refresh()
        }
    }

    DotGridCanvas {
        id: dots
        anchors.fill: parent
        color: dd.working ? dd.accentLight : dd.stateColor
        markColor: dd.working ? "white" : dd.stateColor
        flareColor: dd.accentLight
        flare: dd.working
    }
}
