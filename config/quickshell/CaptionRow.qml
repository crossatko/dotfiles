import QtQuick
import QtQuick.Layouts

// A small caption row: an iconSm glyph and a caption in the same quiet colour, then whatever children the user adds (a
// status on the right, the card's age and close). The reminder popup's and its notification card's first row.
RowLayout {
    id: cap
    property string glyph: ""
    property string text: ""
    property color tone: Theme.fgDim          // glyph and caption
    property int pixelSize: Theme.fontSmall

    spacing: Theme.gapRow
    Icon { text: cap.glyph; color: cap.tone; font.pixelSize: Theme.iconSm }
    Label { text: cap.text; color: cap.tone; font.pixelSize: cap.pixelSize }
}
