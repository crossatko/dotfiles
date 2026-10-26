pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Inline dropdown for popups: a box with the current choice and a chevron; clicking it unfolds the options right
// below (the panel grows around them, so it never leaves the popup surface). `options` is [{label, color?}]
// (`color` = a dot in front), `currentIndex` the one shown. Never changes currentIndex itself: picking emits
// picked(index) and folds the list. Long labels elide.
ColumnLayout {
    id: dsel

    property var options: []
    property int currentIndex: -1
    property bool open: false
    property string emptyText: "None"
    readonly property var current: currentIndex >= 0 && currentIndex < options.length ? options[currentIndex] : null
    signal picked(int index)

    spacing: 4

    Rectangle {
        id: headBox
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusItem
        color: headGlow.hovered ? Theme.alpha(Theme.fg, 0.13) : Theme.alpha(Theme.fg, 0.07)
        border.width: dsel.open ? 1 : 0
        border.color: Theme.alpha(Theme.accent, 0.8)
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            Dot { visible: dsel.current !== null && dsel.current.color !== undefined; tint: dsel.current?.color ?? "transparent" }
            Label { text: dsel.current ? dsel.current.label : dsel.emptyText; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall }
            Icon {
                visible: dsel.options.length > 1
                text: "\uf078"
                font.pixelSize: 11
                color: Theme.fgDim
                rotation: dsel.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        HoverGlow { id: headGlow; area: head; radius: Theme.radiusItem }
        MouseArea { id: head; anchors.fill: parent; hoverEnabled: true; enabled: dsel.options.length > 1; onClicked: dsel.open = !dsel.open }
    }

    // option list; collapses to zero height so the panel resizes around it
    Item {
        Layout.fillWidth: true
        implicitHeight: dsel.open ? list.implicitHeight : 0
        clip: true
        visible: implicitHeight > 0
        Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: list
            width: parent.width
            spacing: 2
            Repeater {
                model: dsel.options
                Rectangle {
                    id: optRow
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: index === dsel.currentIndex
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.radiusItem
                    color: isCurrent ? Theme.alpha(Theme.accent, 0.22) : optGlow.hovered ? Theme.alpha(Theme.fg, 0.12) : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Dot { visible: optRow.modelData.color !== undefined; tint: optRow.modelData.color ?? "transparent" }
                        Label { text: optRow.modelData.label; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: optRow.isCurrent ? Theme.accent : Theme.fg }
                        Icon { visible: optRow.isCurrent; text: "\uf00c"; font.pixelSize: 12; color: Theme.accent }
                    }
                    HoverGlow { id: optGlow; area: opt; radius: Theme.radiusItem }
                    MouseArea { id: opt; anchors.fill: parent; hoverEnabled: true; onClicked: { dsel.open = false; dsel.picked(optRow.index) } }
                }
            }
        }
    }

    component Dot: Rectangle {
        property color tint: "transparent"
        implicitWidth: 8; implicitHeight: 8; radius: 4
        color: tint
    }
}
