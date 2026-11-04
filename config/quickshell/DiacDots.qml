import QtQuick
import "launcher/js/DiacScene.js" as Scene

// The diacritics pill's picture (DiacPill): the approved "Flare" scene (launcher/js/DiacScene.js) drawn by DotGridCanvas in the
// shell's colours, advanced by a plain Timer (like DotSwoosh: a running QML animation would keep Qt's animation driver on and make
// every shell window redraw each frame).
//   kind    words (the text's real words) | neutral (generic loop, no text) | loading (the neutral loop, dim and slow)
//   phase   working | done | failed | unsupported (the end states fade the picture, then draw their icon)
//   text    the words to show (kind words)
//   running the clock runs and the picture redraws (false while the pill is hidden)
// restart() starts the working picture from its first chunk. Reduced motion (Motion.reduced): the end icons still draw, the working
// picture shows its first chunk and neutral loop frozen at one frame.
Item {
    id: dd
    property string kind: "words"
    property string phase: "working"
    property string text: ""
    property bool running: true

    readonly property bool working: phase === "working"
    readonly property var prep: Scene.prepare(text)
    property real t: 0                    // seconds in the working picture
    property real sT: 0                   // seconds in the current end state
    property double last: 0

    // colours: letters and marks while working, the state's tint in the end states (the prototype's: accent / green / red / dim, 25 % to white)
    readonly property color accentLight: Qt.tint(Theme.accent, Qt.rgba(1, 1, 1, 0.3))
    readonly property color stateColor: Qt.tint(phase === "done" ? Theme.green : phase === "failed" ? Theme.red : Theme.fgDim, Qt.rgba(1, 1, 1, 0.25))

    function restart() { t = 0; sT = 0; last = Date.now(); refresh() }
    function refresh() { dots.grid = Scene.scene(kind, phase, t, sT, prep) }
    onPhaseChanged: { sT = 0; refresh() }
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
            dd.sT += dt
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
