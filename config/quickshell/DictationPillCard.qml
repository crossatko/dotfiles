import QtQuick

// The dictation pill's card (DictationPill, and the Settings > Voice preview through PillSection): the glass card (MotionCard),
// a full-width dithered swoosh driven by the mic level (DotSwoosh) with the mode as dot letters in the swoosh's own grid ("CS" /
// "EN" left; translating: "CS" left, "EN" right, colour accent -> accent2) and ONE caption line with the tail of the text
// (TailLine) that opens when there is text: the card grows away from its anchor edge (`flip` = the caption ABOVE the swoosh, so
// the swoosh stays beside a bottom bar). Error: a flat red dotted line and `errorLine`, no mode.
// Pure view: the window (or preview) sets the state; nothing here talks to the service. Width from the user; height =
// baseH + the caption's share (animated while `openMotion.shown`); `fullH` = the grown height (the window's room).
//   look     listening | speaking | translating | error        mode    a language code, "auto" or "src-dst" (see DictationPill)
//   caption  the text so far (the end is shown)                level / levels  the mic level (DotSwoosh)
//   running  the swoosh's clock runs
MotionCard {
    id: card
    property string look: "listening"
    property string mode: "cs"
    property string caption: ""
    property real level: 0
    property var levels: []
    property bool running: true
    property bool flip: false
    property string errorLine: "An error occurred"
    readonly property alias swoosh: swooshItem
    readonly property alias tail: tailItem

    readonly property bool isError: look === "error"
    readonly property var langs: String(mode).toLowerCase().split("-")
    readonly property string srcLang: langs[0] || ""
    readonly property string dstLang: langs[1] || (look === "translating" ? "en" : "")
    // Czech and English keep their colours, Auto and every other language one of the palette's, by its code
    // (a colour whose hue is near accent or accent2 would read as Czech or English: left out)
    function hueGap(a, b) { const d = Math.abs(a.hsvHue - b.hsvHue); return Math.min(d, 1 - d) }
    readonly property var langPalette: {
        const all = [Theme.blue, Theme.green, Theme.orange, Theme.cyan, Theme.yellow, Theme.red, Theme.fg]
        const ok = all.filter(c => c.hsvHue < 0 || (hueGap(c, Theme.accent) > 0.07 && hueGap(c, Theme.accent2) > 0.07))
        return ok.length ? ok : [Theme.fg]
    }
    function langColor(code) {
        if (code === "en") return Theme.accent2
        if (code === "cs") return Theme.accent
        if (code === "auto" || code === "") return Theme.fg
        let h = 0
        for (const c of String(code)) h = (h * 31 + c.charCodeAt(0)) % 997
        return langPalette[h % langPalette.length]
    }
    readonly property bool hasText: isError || caption !== ""

    // ---- geometry (Theme tokens; the swoosh row is this card's own content cap) ----
    readonly property int pillW: 336          // the card's width (the window's; shrinks only on a narrow screen)
    readonly property int waveH: 40           // the swoosh row
    readonly property int sidePad: Theme.pad + Theme.controlGap   // 18, as the OSD pill
    readonly property real baseH: 2 * Theme.pad + waveH
    readonly property real capH: tailItem.implicitHeight        // one line, caption or error
    readonly property real fullH: baseH + Theme.gapRow + capH

    // caption row share of the card height: opens / closes with the text (move tokens), instant while hidden
    property real capShare: hasText ? Theme.gapRow + capH : 0
    Behavior on capShare { enabled: card.openMotion.shown; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }

    height: baseH + capShare
    clip: true

    DotSwoosh {
        id: swooshItem
        x: card.sidePad
        y: card.flip ? card.height - Theme.pad - height : Theme.pad
        width: card.width - 2 * card.sidePad
        height: card.waveH
        running: card.running
        level: card.level
        levels: card.levels
        error: card.isError
        leftText: card.srcLang
        rightText: card.dstLang
        colorLeft: card.langColor(card.srcLang)
        colorRight: card.dstLang !== "" ? card.langColor(card.dstLang) : colorLeft
    }

    // the caption / error line, under the swoosh (above it when flipped); fades with its share of the height
    Item {
        x: card.sidePad
        width: card.width - 2 * card.sidePad
        height: card.capH
        y: card.flip ? Theme.pad : Theme.pad + card.waveH + Theme.gapRow
        opacity: card.hasText ? Math.max(0, Math.min(1, (card.capShare - Theme.gapRow) / Math.max(1, card.capH))) : 0
        TailLine {
            id: tailItem
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !card.isError
            text: card.caption
            label.font.pixelSize: Theme.fontLead
            label.font.weight: Font.Medium
        }
        Label {
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height
            visible: card.isError
            text: card.errorLine
            color: Theme.red
        }
    }
}
