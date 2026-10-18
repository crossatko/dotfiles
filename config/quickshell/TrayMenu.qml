import QtQuick
import QtQuick.Layouts
import Quickshell

// Themed context menu for a system tray item (QsMenuAnchor's platform menus need QApplication, so we draw our own).
// Submenus replace the list in place; the first row becomes a "back" row.
PopupWindow {
    id: tm

    property var handle: null          // QsMenuHandle of the tray item
    property var host: null            // PanelWindow to anchor to
    property real anchorX: 0
    property bool atTop: false
    property var stack: []             // opened submenu entries
    readonly property var current: stack.length ? stack[stack.length - 1] : handle

    function show() { stack = []; visible = true }
    function hide() { visible = false }

    // one click-away thing at a time; a click on another monitor (ClickCatcher) closes it too
    readonly property string kind: "tray-" + tm.toString()
    PopupRegistration { kind: tm.kind; open: tm.visible; screenName: tm.host && tm.host.screen ? tm.host.screen.name : ""; onDismissed: tm.visible = false }

    anchor.window: host
    anchor.rect.x: anchorX
    // a floating bar gets popupGap of air between bar and menu; docked stays flush with the bar
    readonly property int gapToBar: Theme.barFloating ? Theme.popupGap : 0
    anchor.rect.y: atTop ? host.height + gapToBar : -gapToBar
    anchor.rect.width: 18
    anchor.rect.height: 1
    anchor.edges: (atTop ? Edges.Bottom : Edges.Top) | Edges.Left
    anchor.gravity: (atTop ? Edges.Bottom : Edges.Top) | Edges.Right
    anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
    grabFocus: true
    color: "transparent"
    implicitWidth: Math.max(190, col.implicitWidth + 12)
    implicitHeight: col.implicitHeight + 12

    QsMenuOpener { id: opener; menu: tm.current }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.12)

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 6 }
            spacing: 2

            Rectangle {
                visible: tm.stack.length > 0
                Layout.fillWidth: true
                implicitHeight: 28
                radius: Theme.inner(Theme.radius, 6)
                color: backArea.containsMouse ? Theme.alpha(Theme.fg, 0.14) : "transparent"
                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8
                    Icon { text: ""; font.pixelSize: 11; color: Theme.fgDim }
                    Label { text: "Back"; Layout.fillWidth: true; color: Theme.fgDim }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: tm.stack = tm.stack.slice(0, -1) }
            }

            Repeater {
                model: opener.children
                delegate: Item {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.isSeparator ? 9 : 28
                    implicitWidth: rowContent.implicitWidth + 16

                    Rectangle {
                        visible: row.modelData.isSeparator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 4; rightMargin: 4 }
                        height: 1
                        color: Theme.alpha(Theme.fg, 0.14)
                    }
                    Rectangle {
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: Theme.inner(Theme.radius, 6)
                        color: rowArea.containsMouse && row.modelData.enabled ? Theme.alpha(Theme.accent, 0.28) : "transparent"
                    }
                    RowLayout {
                        id: rowContent
                        visible: !row.modelData.isSeparator
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8
                        // check / radio marker keeps text aligned when any entry has one
                        Icon {
                            visible: row.modelData.buttonType !== QsMenuButtonType.None
                            text: row.modelData.checkState === Qt.Checked ? (row.modelData.buttonType === QsMenuButtonType.RadioButton ? "" : "") : ""
                            font.pixelSize: 11
                            Layout.preferredWidth: 14
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.accent
                        }
                        Image {
                            visible: row.modelData.icon !== ""
                            source: row.modelData.icon
                            sourceSize: Qt.size(32, 32)
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                        }
                        Label {
                            text: row.modelData.text.replace(/&&/g, "\u0001").replace(/&/g, "").replace(/\u0001/g, "&")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: row.modelData.enabled ? Theme.fg : Theme.muted
                        }
                        Icon { visible: row.modelData.hasChildren; text: ""; font.pixelSize: 11; color: Theme.fgDim }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !row.modelData.isSeparator && row.modelData.enabled
                        onClicked: {
                            if (row.modelData.hasChildren) tm.stack = tm.stack.concat([row.modelData])
                            else { row.modelData.triggered(); tm.hide() }
                        }
                    }
                }
            }
        }
    }
}
