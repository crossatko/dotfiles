pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell

// Clock of the lock screen: the time (HH:mm or HH:mm:ss, ClockFace) in glass lettering, one GlassText per character (each glyph its own
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
    // form(): the shared glass reveal (GlassReveal / GlassGlyph, also the desktop clock's): after a short pause the digits
    // condense one after the other, left to right, then the date fades in; popup motion speed, instant when motion is off.
    // A changed digit (the minute) morphs into the new one (GlassText); the others stay.
    GlassReveal { id: reveal; enabled: LockPrefs.clockReveal }   // Settings > Lock "Clock reveal"
    function form() { reveal.form(glyphRepeater) }
    // the time (HH:mm[:ss], Settings > Lock "Seconds" / "24-hour clock"), the digits' morph time and the fit; test hook
    // QS_LOCK_CLOCK (ClockFace)
    ClockFace {
        id: face
        h24: LockPrefs.clock24h
        seconds: LockPrefs.seconds
        morphTime: LockPrefs.morph
        testEnv: Quickshell.env("QS_LOCK_CLOCK") || ""
        active: c.visible
    }
    readonly property string text: face.text
    function demo() { face.demo() }
    // the widest the clock may be (seconds widen it): the digits shrink only if it would not fit
    property real maxWidth: 1e6
    readonly property int glyphSize: face.fitSize(pixelSize, maxWidth)
    spacing: -Math.round(glyphSize * 0.04)     // the glyph box has room for descenders the digits do not use

    Row {
        id: glyphs
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(c.glyphSize * 0.03)
        Repeater {
            id: glyphRepeater
            model: c.text.length
            GlassGlyph {
                id: ch
                required property int index
                text: c.text.charAt(index)
                pixelSize: c.glyphSize
                morphMs: face.morphMs
                backdrop: c.backdrop
                sharpBackdrop: c.sharpBackdrop
                sharpInset: c.sharpInset
                dim: Theme.lockDim
                backdropSize: c.backdropSize
                origin: Qt.point(c.origin.x + glyphs.x + ch.x, c.origin.y + glyphs.y + ch.y)
            }
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: LockPrefs.showDate
        opacity: reveal.dateShown
        text: face.dateText
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
