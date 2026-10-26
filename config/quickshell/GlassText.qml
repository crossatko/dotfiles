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
    readonly property real strokeHalf: pixelSize * 0.1      // Paper Mono extra bold: stem ~ 0.2 em incl. the inflation
    readonly property int pad: Math.ceil(Math.max(4, Math.min(48, strokeHalf * 1.1)) * 3.5)
    implicitWidth: glyphs.width - 2 * pad
    implicitHeight: glyphs.height - 2 * pad
    width: implicitWidth
    height: implicitHeight

    // ping-pong: `cur` holds what is shown; a change is written into the other one, morphed to, then becomes `cur`
    property int cur: 0
    property string textA: text
    property string textB: text
    readonly property int morphMs: Theme.popupMs(Motion.baseMs * 3)
    onTextChanged: {
        if (morphMs <= 0 || !shape.refracting) { morphAnim.stop(); textA = text; textB = text; cur = 0; shape.morph = 0; return }
        if (morphAnim.running) { morphAnim.complete() }
        if (cur === 0) textB = text; else textA = text
        morphAnim.restart()
    }
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
        mask: g.cur === 0 ? glyphs : glyphs2
        mask2: g.cur === 0 ? glyphs2 : glyphs
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
