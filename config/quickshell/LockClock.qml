pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell

// Clock of the lock screen: the time (HH:mm) in glass lettering, one GlassText per character (each glyph its own
// shape field, so neighbours never melt together), spaced apart a little; the date under it in the UI font (glass does
// not read at that size), with a soft halo of the theme bg for busy or opposite-brightness wallpapers. `pixelSize` =
// the digits' size; `origin` = this item's top-left in the backdrop (`backdrop`, `sharpBackdrop`, `sharpInset`).
Column {
    id: c
    property int pixelSize: 200
    property Item backdrop: null
    property Item sharpBackdrop: null
    property real sharpInset: 0
    property point origin: Qt.point(0, 0)
    property size backdropSize: Qt.size(1, 1)
    // form(): after a short pause the digits condense one after the other, left to right, like drops of liquid glass:
    // each inflates from flat (refraction, rim and highlights grow with it) with a very soft settle and a small scale
    // (0.96 -> 1); then the date fades in. Calm, ~2.5 s at normal speed; popup motion speed, instant when motion is off.
    // A changed digit (the minute) morphs into the new one (GlassText); the others stay.
    readonly property int formMs: LockPrefs.clockReveal ? Theme.popupMs(Motion.baseMs * 8) : 0   // Settings > Lock "Clock reveal"
    readonly property int staggerMs: Theme.popupMs(Motion.baseMs * 0.6)
    readonly property int delayMs: Theme.popupMs(Motion.baseMs * 2)
    property real dateShown: 1
    function form() {
        for (let i = 0; i < glyphRepeater.count; i++) {
            const g = glyphRepeater.itemAt(i)
            if (g) g.land(delayMs + i * staggerMs)   // qmllint disable missing-property
        }
        dateAnim.stop()
        if (formMs <= 0) { dateShown = 1; return }
        dateShown = 0
        dateAnim.restart()
    }
    SequentialAnimation {
        id: dateAnim
        PauseAnimation { duration: Math.max(0, c.delayMs + (glyphRepeater.count - 1) * c.staggerMs + c.formMs * 0.5) }
        NumberAnimation { target: c; property: "dateShown"; from: 0; to: 1; duration: c.formMs; easing.type: Easing.InOutSine }
    }
    // test hook QS_LOCK_CLOCK: a fixed text, or several separated by spaces, cycled every 3 s (the morph)
    readonly property var testTimes: String(Quickshell.env("QS_LOCK_CLOCK") || "").split(" ").filter(t => t !== "")
    property int testIdx: 0
    Timer { running: c.testTimes.length > 1; interval: 3000; repeat: true; onTriggered: c.testIdx = (c.testIdx + 1) % c.testTimes.length }
    readonly property string text: testTimes.length > 0 ? testTimes[testIdx] : (LockPrefs.clock24h ? Qt.formatDateTime(clock.date, "HH:mm") : Qt.formatDateTime(clock.date, "h:mm AP").replace(/\s*[AP]M$/i, ""))   // "h" alone is 24 h in Qt
    spacing: -Math.round(pixelSize * 0.04)     // the glyph box has room for descenders the digits do not use

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Row {
        id: glyphs
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(c.pixelSize * 0.03)
        Repeater {
            id: glyphRepeater
            model: c.text.length
            GlassText {
                id: ch
                required property int index
                text: c.text.charAt(index)
                pixelSize: c.pixelSize
                backdrop: c.backdrop
                sharpBackdrop: c.sharpBackdrop
                sharpInset: c.sharpInset
                dim: Theme.lockDim
                backdropSize: c.backdropSize
                origin: Qt.point(c.origin.x + glyphs.x + ch.x, c.origin.y + glyphs.y + ch.y)
                property real pop: 1
                strength: pop
                opacity: Math.min(1, pop * 1.4)
                scale: 0.96 + 0.04 * pop
                transformOrigin: Item.Bottom
                function land(delay) {
                    landAnim.stop()
                    if (c.formMs <= 0) { pop = 1; return }
                    pop = 0
                    landDelay.duration = delay
                    landAnim.restart()
                }
                SequentialAnimation {
                    id: landAnim
                    PauseAnimation { id: landDelay; duration: 0 }
                    NumberAnimation { target: ch; property: "pop"; from: 0; to: 1; duration: c.formMs; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
                }
            }
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: LockPrefs.showDate
        opacity: c.dateShown
        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
        font.pixelSize: Math.max(Theme.fontTitle, Math.round(c.pixelSize * 0.09))
        font.weight: Font.Medium
        color: Theme.fg
        layer.enabled: true
        // 2x on a scale-1 output (smooth halo, no colour fringes from the text in the layer), 1x on scaled outputs
        layer.smooth: true
        layer.textureSize: Screen.devicePixelRatio > 1 ? Qt.size(0, 0) : Qt.size(width * 2, height * 2)
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 1; shadowHorizontalOffset: 0; shadowColor: Theme.alpha(Theme.bg, 0.9) }
    }
}
