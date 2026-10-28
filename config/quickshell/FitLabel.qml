import QtQuick

// A line of text that never overflows its width: wraps up to `lines` lines (1 = no wrap), then elides; a word longer
// than the width breaks anywhere. With `tip`, hovering a cut text shows all of it in a TipBubble as wide as the line.
// Set the width (or Layout.fillWidth). MediaPanel, LockMedia.
Label {
    id: fl
    property int lines: 2
    property bool tip: true
    readonly property int minTip: 160      // the bubble is as wide as the line, at least this
    wrapMode: lines > 1 ? Text.Wrap : Text.NoWrap
    maximumLineCount: lines
    elide: Text.ElideRight

    HoverHandler { id: hh; enabled: fl.tip }
    TipBubble { anchors.fill: parent; text: fl.text; shown: fl.tip && hh.hovered && fl.truncated; alignRight: false; maxWidth: Math.max(fl.width, fl.minTip) }
}
