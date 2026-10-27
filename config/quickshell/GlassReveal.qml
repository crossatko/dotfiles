import QtQuick

// The glass clock's reveal (the lock screen's, shared with the desktop clock): `form(repeater)` = after a short pause
// the GlassGlyph items of `repeater` condense one after the other, left to right, like drops of liquid glass, each over
// `formMs` (~2.5 s for the whole clock at normal speed); then `dateShown` (bind the date's opacity to it) fades in.
// All on the popup motion tokens (Settings > Animations speed; none = instant); `enabled` false = instant too (Settings
// > Lock "Clock reveal" for the lock). Nothing runs once formed.
QtObject {
    id: r
    property bool enabled: true
    readonly property int formMs: enabled ? Theme.popupMs(Motion.baseMs * 8) : 0
    readonly property int staggerMs: Theme.popupMs(Motion.baseMs * 0.6)
    readonly property int delayMs: Theme.popupMs(Motion.baseMs * 2)
    property real dateShown: 1
    property int count: 0
    property int lead: 0
    function glyphAt(repeater, i) {
        const it = repeater.itemAt(i)
        return (it && it.glyph ? it.glyph : it) as GlassGlyph   // qmllint disable missing-property
    }
    // `delay` (optional, ms): the pause before the first digit instead of delayMs (the desktop clock after an unlock:
    // the lock's ring opening already was the pause)
    function form(repeater, delay) {
        count = repeater.count
        const d0 = delay === undefined ? delayMs : Math.max(0, delay)
        lead = d0
        for (let i = 0; i < repeater.count; i++) {
            const g = glyphAt(repeater, i)
            if (g) g.land(d0 + i * staggerMs, formMs)
        }
        dateAnim.stop()
        if (formMs <= 0) { dateShown = 1; return }
        dateShown = 0
        dateAnim.restart()
    }
    property SequentialAnimation dateAnim: SequentialAnimation {
        PauseAnimation { duration: Math.max(0, r.lead + (r.count - 1) * r.staggerMs + r.formMs * 0.5) }
        NumberAnimation { target: r; property: "dateShown"; from: 0; to: 1; duration: r.formMs; easing.type: Easing.InOutSine }
    }
}
