pragma ComponentBehavior: Bound
import QtQuick

// Choice as captioned icon tiles: one Btn per entry of `model` ([{value, glyph, name, label}]) filling
// `fillWidth`, a few px apart; the one whose value equals `current` is active. The caption is the full `name` when it
// fits the tile, else the short `label` (never elided). Each tile carries its name as the accessible name. Never
// changes `current` itself; picked(v) on click.
Row {
    id: mt
    property var model: []
    property var current: undefined
    property real fillWidth: 0
    readonly property int tileHeight: 50      // two-line tile (icon + caption); between controlH and rowTallH
    readonly property int captionPad: Theme.controlGap
    signal picked(var value)

    readonly property real tileWidth: model.length ? Math.floor((fillWidth - spacing * (model.length - 1)) / model.length) : 0
    spacing: Theme.gapTight / 2

    FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: Theme.fontCaption }

    Repeater {
        model: mt.model
        Btn {
            id: b
            required property var modelData
            required property int index
            // the last tile takes the rounding remainder, so the row ends flush with the rows around it
            width: index === mt.model.length - 1 ? mt.fillWidth - (mt.tileWidth + mt.spacing) * index : mt.tileWidth
            implicitHeight: mt.tileHeight
            active: mt.current === modelData.value
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checked: active
            onClicked: mt.picked(modelData.value)
            Column {
                anchors.centerIn: parent
                spacing: Theme.gapTight
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: b.modelData.glyph
                    font.pixelSize: Theme.iconMd
                    color: b.active ? Theme.accent : Theme.fgDim
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: fm.advanceWidth(b.modelData.name) <= b.width - mt.captionPad ? b.modelData.name : b.modelData.label
                    font.pixelSize: Theme.fontCaption
                    color: b.active ? Theme.accent : Theme.fg
                }
            }
        }
    }
}
