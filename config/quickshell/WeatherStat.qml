import QtQuick
import QtQuick.Layouts

// One small fact of the weather card: a muted glyph (in the iconCol column, like a ListRow's) and its value with a
// caption ("feels like", humidity, wind). As wide as its text; the card spreads the facts across its row.
RowLayout {
    id: st
    property string icon: ""
    property string text: ""
    property string tip: ""        // what the value is, shown as a dim caption under it
    spacing: Theme.controlGap

    Icon { text: st.icon; color: Theme.fgDim; font.pixelSize: Theme.iconLg; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: Theme.iconCol }
    ColumnLayout {
        spacing: 0
        Label { text: st.text; font.pixelSize: Theme.fontSmall }
        Label { visible: st.tip !== ""; text: st.tip; color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
    }
}
