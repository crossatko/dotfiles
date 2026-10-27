import QtQuick

// Glass lettering: the text's glyphs as clear glass tubes (GlassShape) over `backdrop` / `sharpBackdrop`, `origin` =
// where this item's top-left lies in them (LockClock passes all three). Falls back to GlassTextFlat (no shader) when
// GlassShape cannot refract. Big, heavy sizes only. A text change morphs: the new text goes into the other of two masks
// and the glass flows from one shape field to the other (popup motion speed; instant when motion is off). Same-size
// texts only (a monospace digit); nothing animates or re-renders while idle.
Item {
    id: g
    property string text: ""
    property int pixelSize: 160
    property int weight: Font.ExtraBold
    property real letterSpacing: 0
    property alias backdrop: shape.backdrop
    property alias sharpBackdrop: shape.sharpBackdrop
    property alias sharpInset: shape.sharpInset
    property alias dim: shape.dim
    property point origin: Qt.point(0, 0)
    property alias backdropSize: shape.backdropSize
    property alias strength: shape.strength
    property alias airy: shape.airy
    readonly property real strokeHalf: pixelSize * 0.1      // Paper Mono extra bold: stem ~ 0.2 em incl. the inflation
    readonly property int pad: Math.ceil(Math.max(4, Math.min(48, strokeHalf * 1.1)) * 3.5)
    implicitWidth: glyphs.width - 2 * pad
    implicitHeight: glyphs.height - 2 * pad
    width: implicitWidth
    height: implicitHeight

    // ping-pong: `cur` holds what is shown; a change is written into the other one, morphed to, then becomes `cur`
    property int cur: 0
    // set, not bound: a binding to `text` would follow a change in both masks at once (nothing left to morph from)
    property string textA: ""
    property string textB: ""
    property bool started: false
    Component.onCompleted: { textA = text; textB = text; started = true }
    // the morph's duration (the clocks set it: Settings morph time, the seconds cap); 0 = the new glyph just replaces the old
    property int morphMs: Theme.popupMs(Motion.baseMs * 3)
    // only the mask that took the new text has its field rendered again; the shown one and every other glyph stay
    property int bumped: 0       // which mask's field (0 = A, 1 = B), again in refreshAgain
    function bump(i) { bumped = i; if (i === 0) shape.refresh++; else shape.refresh2++ }
    onTextChanged: {
        if (!started || morphMs <= 0 || !shape.refracting) {
            // a plain swap: the shown mask takes the text
            morphAnim.stop(); shape.morph = 0
            if (cur === 0) textA = text; else textB = text
            if (started) { bump(cur); refreshAgain.restart() }
            return
        }
        if (morphAnim.running) { morphAnim.complete() }
        if (cur === 0) textB = text; else textA = text
        bump(1 - cur)
        refreshAgain.restart()
        morphAnim.restart()
    }
    // and once more a few frames later, after the new mask's layer surely rendered (layer updates run in no fixed order)
    Timer { id: refreshAgain; interval: 50; onTriggered: g.bump(g.bumped) }
    SequentialAnimation {
        id: morphAnim
        NumberAnimation { target: shape; property: "morph"; from: 0; to: 1; duration: g.morphMs; easing.type: Easing.InOutSine }
        ScriptAction { script: { g.cur = 1 - g.cur; shape.morph = 0 } }
    }
    GlassMask { id: glyphs; x: -g.pad; y: -g.pad; text: g.textA; pixelSize: g.pixelSize; weight: g.weight; letterSpacing: g.letterSpacing; pad: g.pad; superSample: shape.ss; visible: false }
    GlassMask { id: glyphs2; x: -g.pad; y: -g.pad; text: g.textB; pixelSize: g.pixelSize; weight: g.weight; letterSpacing: g.letterSpacing; pad: g.pad; superSample: shape.ss; visible: false }
    GlassShape {
        id: shape
        x: -g.pad; y: -g.pad
        width: glyphs.width; height: glyphs.height
        mask: glyphs
        mask2: glyphs2
        flip: g.cur === 1
        pad: g.pad
        strokeHalf: g.strokeHalf
        origin: Qt.point(g.origin.x - g.pad, g.origin.y - g.pad)
    }
    GlassTextFlat {
        visible: !shape.refracting
        x: -g.pad; y: -g.pad
        text: g.text; pixelSize: g.pixelSize; weight: g.weight; letterSpacing: g.letterSpacing; pad: g.pad
    }
}
