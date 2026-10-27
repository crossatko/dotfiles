pragma ComponentBehavior: Bound
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
    readonly property int minW: 190          // narrowest menu
    readonly property int anchorW: 18        // width of the bar spot the menu hangs from
    readonly property int sepH: Theme.gapRow + 1     // height of a separator row (the hairline with a gap each side)
    readonly property int markW: Theme.iconMd        // check / radio marker column
    readonly property int itemIcon: Theme.iconMd     // the entry's own icon
    readonly property int rowRadius: Theme.inner(Theme.radius, Theme.controlGap)   // rows sit controlGap inside the card

    // No open / close motion of its own: an xdg popup has no glass region of its own (the compositor blurs the whole
    // surface), so fading the card would leave an empty blurred box; Hyprland's popup animation does it.
    function show() { stack = []; visible = true }
    function hide() { visible = false }
    onStackChanged: subReveal.play()      // a submenu / back: the rows arrive (Reveal)

    // one click-away thing at a time; a click on another monitor (ClickCatcher) closes it too
    readonly property string kind: "tray-" + tm.toString()
    PopupRegistration { kind: tm.kind; open: tm.visible; screenName: tm.host && tm.host.screen ? tm.host.screen.name : ""; onDismissed: tm.visible = false }

    // PopupWindow.anchor (Quickshell's PopupAnchor) is not described in its qmltypes
    // qmllint disable missing-property unresolved-type unqualified
    anchor.window: host
    anchor.rect.x: anchorX
    // a floating bar gets popupGap of air between bar and menu; docked stays flush with the bar
    readonly property int gapToBar: BarConfig.floating(tm.host ? tm.host.screen : null) ? BarConfig.popupGapOf(tm.host.screen) : 0
    anchor.rect.y: atTop ? host.height + gapToBar : -gapToBar
    anchor.rect.width: anchorW
    anchor.rect.height: 1
    anchor.edges: (atTop ? Edges.Bottom : Edges.Top) | Edges.Left
    anchor.gravity: (atTop ? Edges.Bottom : Edges.Top) | Edges.Right
    anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
    // qmllint enable missing-property unresolved-type unqualified
    grabFocus: true
    color: Theme.alpha(Theme.bg, 0)
    implicitWidth: Math.max(minW, col.implicitWidth + 2 * Theme.controlGap)
    implicitHeight: col.implicitHeight + 2 * Theme.controlGap

    QsMenuOpener { id: opener; menu: tm.current }
    // the leading columns exist for every row of a menu as soon as one entry has a check / radio or an icon, so labels line up
    readonly property var entries: opener.children.values ?? []   // qmllint disable missing-property
    readonly property bool anyMarks: entries.some(e => e.buttonType !== QsMenuButtonType.None)
    readonly property bool anyIcons: entries.some(e => e.icon !== "")

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        // 0.92 fill: an xdg popup gets no compositor glass of its own, so the card is nearly opaque instead
        color: Theme.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Theme.edge

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: Theme.controlGap }
            spacing: Theme.gapTight / 2
            Reveal { id: subReveal; rise: 4 }

            // a submenu's first row: back to the parent menu (the chevron sits in the marker column, so labels line up)
            Rectangle {
                visible: tm.stack.length > 0
                Layout.fillWidth: true
                implicitHeight: Theme.controlH
                radius: tm.rowRadius
                color: backArea.containsMouse ? Theme.itemHover : Theme.alpha(Theme.itemHover, 0)
                Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                HoverGlow { area: backArea; radius: parent.radius }
                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.gapRow; rightMargin: Theme.gapRow }
                    spacing: Theme.gapRow
                    Icon { text: Icons.chevronLeft; font.pixelSize: Theme.iconSm; color: Theme.fg; Layout.preferredWidth: tm.markW; horizontalAlignment: Text.AlignHCenter }
                    Label { text: "Back"; Layout.fillWidth: true }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: tm.stack = tm.stack.slice(0, -1) }
            }

            Repeater {
                model: opener.children
                delegate: Item {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.isSeparator ? tm.sepH : Theme.controlH
                    implicitWidth: rowContent.implicitWidth + 2 * Theme.gapRow

                    Rectangle {
                        visible: row.modelData.isSeparator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.gapTight; rightMargin: Theme.gapTight }
                        height: 1
                        color: Theme.edge
                    }
                    Rectangle {
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: tm.rowRadius
                        color: rowArea.containsMouse && row.modelData.enabled ? Theme.alpha(Theme.accent, 0.28) : Theme.alpha(Theme.accent, 0)
                        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                        HoverGlow { area: rowArea; radius: parent.radius }
                    }
                    RowLayout {
                        id: rowContent
                        visible: !row.modelData.isSeparator
                        anchors { fill: parent; leftMargin: Theme.gapRow; rightMargin: Theme.gapRow }
                        spacing: Theme.gapRow
                        opacity: row.modelData.enabled ? 1 : Theme.disabledOpacity   // disabled = the one dimmed look, not a second ink
                        // check / radio marker keeps text aligned when any entry has one; a checked entry is "on" = accent
                        Icon {
                            visible: tm.anyMarks
                            text: row.modelData.checkState === Qt.Checked ? (row.modelData.buttonType === QsMenuButtonType.RadioButton ? Icons.circleDot : Icons.check) : ""
                            font.pixelSize: Theme.iconSm
                            Layout.preferredWidth: tm.markW
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.accent
                        }
                        Item {
                            visible: tm.anyIcons
                            Layout.preferredWidth: tm.itemIcon; Layout.preferredHeight: tm.itemIcon
                            Image {
                                anchors.fill: parent
                                visible: row.modelData.icon !== ""
                                source: row.modelData.icon
                                sourceSize: Qt.size(2 * tm.itemIcon, 2 * tm.itemIcon)
                            }
                        }
                        Label {
                            text: row.modelData.text.replace(/&&/g, "\u0001").replace(/&/g, "").replace(/\u0001/g, "&")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Icon { visible: row.modelData.hasChildren; text: Icons.chevronRight; font.pixelSize: Theme.iconSm; color: Theme.fgDim }
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
