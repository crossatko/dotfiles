import QtQuick

// A synthetic, speech-like mic level at ~30 Hz for demos: the dictation pill's `demo` test hook and the Settings > Voice pill
// preview. `level` 0..1 follows the envelope while `talking`, else a true 0 (as the service sends at its noise floor).
Timer {
    id: dl
    property bool talking: true
    property real level: 0
    interval: 33
    repeat: true
    onRunningChanged: if (!running) level = 0
    onTriggered: {
        const t = Date.now() / 1000
        const env = (.5 + .5 * Math.sin(t * 2.6)) * (.55 + .45 * Math.sin(t * .8 + 1)) * (.7 + .3 * Math.sin(t * 7.3) * Math.sin(t * 4.1))
        dl.level = dl.talking ? Math.min(1, .1 + env * .95) : 0
    }
}
