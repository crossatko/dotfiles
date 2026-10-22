import QtQuick

// The row of monitor cards of Settings > Bar and > Wallpaper & theme, with a MonitorLinkButton between each pair of
// neighbouring cards (card order = `count` indices). The cards are the Repeater (or anything else) the page puts inside,
// placed with `x: row.xOf(index); y: row.yOf(index); width: row.cardW; height: row.cardH`. Cards wrap onto further rows
// when they would get narrower than `minCardW`; a link between two cards of one row sits in the gap, a link across a row break sits in the gap between the rows, centred, because its two cards are not adjacent.
// Each card gets a round notch around every link button that reaches it (`notches: row.notchesOf(index)`, drawn by
// NotchMask as the card's layer.effect), so the button sits in a cut-out with an even `notchGap` (Theme.controlGap)
// around it; the card `gap` is derived from it so the cut keeps the same distance to the card content.
// The page decides what linking means: it answers `linkedAt(i)` (is card i linked to card i+1) and reacts to
// `linkToggled(i)`.
Item {
    id: row
    property int count: 0
    property int minCardW: 200
    property int cardH: 62
    property int inset: 10                      // the cards' smallest content margin (WallpaperMonitorCard's left 10)
    readonly property real btnSize: 26         // MonitorLinkButton
    readonly property real notchGap: Theme.controlGap    // even gap between the button and the cut edge of the cards
    // card gap: the notch (button radius + notchGap) may bite into a card only as far as keeps notchGap between the
    // cut edge and the card content (inset): 26 + 4 x 6 - 2 x 10 = 30
    readonly property real gap: Math.max(2 * notchGap, btnSize + 4 * notchGap - 2 * inset)
    property var linkedAt: function (i) { return false }
    property var linkTip: function (i) { return "" }
    signal linkToggled(int i)

    readonly property int cols: Math.max(1, Math.min(count, Math.floor((width + gap) / (minCardW + gap))))
    readonly property int rows: Math.max(1, Math.ceil(count / cols))
    readonly property real cardW: Math.floor((width - (cols - 1) * gap) / cols)
    function xOf(i) { return (i % cols) * (cardW + gap) }
    function yOf(i) { return Math.floor(i / cols) * (cardH + gap) }
    // centre of the link between card k and k + 1: in the gap between them, or centred in the gap between the rows
    function linkCenter(k) {
        return (k + 1) % cols !== 0 ? Qt.point(xOf(k) + cardW + gap / 2, yOf(k) + cardH / 2)
                                    : Qt.point(width / 2, yOf(k) + cardH + gap / 2)
    }
    // notches of card i: [Qt.vector3d(x, y, radius)] in the card's coordinates, one per link whose notch reaches it
    function notchesOf(i) {
        const r = btnSize / 2 + notchGap, x0 = xOf(i), y0 = yOf(i), out = []
        for (let k = 0; k < count - 1 && out.length < 4; k++) {
            const c = linkCenter(k)
            const dx = Math.max(x0 - c.x, 0, c.x - x0 - cardW), dy = Math.max(y0 - c.y, 0, c.y - y0 - cardH)
            if (dx * dx + dy * dy < r * r)
                out.push(Qt.vector3d(c.x - x0, c.y - y0, r))
        }
        return out
    }

    implicitHeight: rows * cardH + (rows - 1) * gap
    height: implicitHeight

    Repeater {
        model: row.count > 1 ? row.count - 1 : 0          // one link after card i, between i and i + 1
        Item {
            id: lk
            z: 10                                          // above the cards, which the page adds as siblings
            required property int index
            readonly property bool on: row.linkedAt(index)
            readonly property point c: row.linkCenter(index)
            MonitorLinkButton {
                implicitWidth: row.btnSize; implicitHeight: row.btnSize
                x: lk.c.x - width / 2
                y: lk.c.y - height / 2
                linked: lk.on
                tip: row.linkTip(lk.index)
                onToggled: row.linkToggled(lk.index)
            }
        }
    }
}
