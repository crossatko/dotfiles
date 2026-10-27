pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The one inline dropdown for popups: a box with the current choice and a chevron; clicking it unfolds the options right
// below (the panel grows around them, so it never leaves the popup surface). `options` is
// [{label, color?, icon?, note?, noteTint?}]: `color` = a StatusDot in front, `icon` = a leading glyph, `note` = a small
// dimmer line-end text (tinted `noteTint`, default muted). `currentIndex` the one shown. Never changes currentIndex
// itself: picking emits picked(index) and folds the list. `headText` overrides the head label (a busy state), `headIcon`
// puts a glyph in front of the head. Long labels elide. `toggled(open)` fires when the head opens / folds the list.
ColumnLayout {
    id: dsel

    property var options: []
    property int currentIndex: -1
    property bool open: false
    property string emptyText: "None"
    property string headText: ""
    property string headIcon: ""
    readonly property var current: currentIndex >= 0 && currentIndex < options.length ? options[currentIndex] : null
    signal picked(int index)
    signal toggled(bool open)

    spacing: Theme.gapTight

    Rectangle {
        id: headBox
        Layout.fillWidth: true
        implicitHeight: Theme.controlH
        radius: Theme.radiusItem
        color: dsel.open ? Theme.itemActive : headGlow.hovered ? Theme.itemHover : Theme.itemFill
        border.width: dsel.open ? 1 : 0
        border.color: Theme.accentEdge
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        RowLayout {
            anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
            spacing: Theme.gapRow
            Icon { visible: dsel.headIcon !== ""; text: dsel.headIcon; font.pixelSize: Theme.iconSm; color: Theme.fgDim }
            StatusDot { visible: dsel.current !== null && dsel.current.color !== undefined; tint: dsel.current?.color ?? Theme.accent }
            Label { text: dsel.headText !== "" ? dsel.headText : dsel.current ? dsel.current.label : dsel.emptyText; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall }
            Label {
                visible: dsel.headText === "" && dsel.current !== null && !!dsel.current.note
                text: dsel.current?.note ?? ""
                color: dsel.current?.noteTint ?? Theme.muted
                font.pixelSize: Theme.fontCaption
            }
            Chevron {
                visible: dsel.options.length > 1
                open: dsel.open
            }
        }
        HoverGlow { id: headGlow; area: head; radius: Theme.radiusItem }
        MouseArea {
            id: head
            anchors.fill: parent
            hoverEnabled: true
            enabled: dsel.options.length > 1
            onClicked: { dsel.open = !dsel.open; dsel.toggled(dsel.open) }
        }
    }

    // option list; collapses to zero height so the panel resizes around it
    FoldBox {
        Layout.fillWidth: true
        open: dsel.open
        contentHeight: list.implicitHeight

        ColumnLayout {
            id: list
            width: parent.width
            spacing: Theme.gapTight
            Repeater {
                model: dsel.options
                Rectangle {
                    id: optRow
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: index === dsel.currentIndex
                    Layout.fillWidth: true
                    implicitHeight: Theme.controlH
                    radius: Theme.radiusItem
                    color: isCurrent ? Theme.accentFill : optGlow.hovered ? Theme.itemHover : Theme.alpha(Theme.fg, 0)
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
                        spacing: Theme.gapRow
                        Icon { visible: optRow.modelData.icon !== undefined; text: optRow.modelData.icon ?? ""; font.pixelSize: Theme.iconSm; color: Theme.fgDim }
                        StatusDot { visible: optRow.modelData.color !== undefined; tint: optRow.modelData.color ?? Theme.accent }
                        Label { text: optRow.modelData.label; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: optRow.isCurrent ? Theme.accent : Theme.fg }
                        Label { visible: !!optRow.modelData.note; text: optRow.modelData.note ?? ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                        Icon { visible: optRow.isCurrent; text: Icons.check; font.pixelSize: Theme.iconSm; color: Theme.accent }
                    }
                    HoverGlow { id: optGlow; area: opt; radius: Theme.radiusItem }
                    MouseArea { id: opt; anchors.fill: parent; hoverEnabled: true; onClicked: { dsel.open = false; dsel.picked(optRow.index) } }
                }
            }
        }
    }
}
