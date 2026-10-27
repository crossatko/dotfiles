pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// One chip of MonitorChooser: the monitor's wallpaper still in its real aspect, its model (connector when it has none)
// over the connector + an optional status, the PrimaryTag on the primary (dot only when the chip is tight) and an
// optional accent glyph (`mark`). `screen` null = the chooser's "All" chip (desktop glyph + label). An L1 item: fill only,
// the selected look is the chooser's gliding marker; `grouped` (linked to the selected one) = accent outline, no fill.
Rectangle {
    id: chip
    property var screen: null
    property string allLabel: "All"
    property bool selected: false
    property bool grouped: false
    property string subtitle: ""
    property string mark: ""
    property string markTip: ""
    property string thumb: ""
    property real maxWidth: 240
    signal clicked()

    readonly property int thumbH: 18                         // the still's height; width follows the monitor's aspect
    readonly property int thumbW: screen && screen.height > 0 ? Math.max(12, Math.min(40, Math.round(thumbH * screen.width / screen.height))) : thumbH
    readonly property bool primary: screen !== null && Monitors.isPrimary(screen)
    readonly property string title: screen ? Monitors.title(screen) : allLabel
    readonly property string sub: !screen ? subtitle
        : [title !== screen.name ? screen.name : "", subtitle].filter(t => t !== "").join(" · ")
    readonly property real margins: Theme.padSm + Theme.pad
    // the chip's full width (name and tag unelided) and without the tag's word; the chooser caps it with maxWidth
    readonly property real naturalWidth: compactWidth + (primary ? tag.spacing + tagWord.implicitWidth : 0)
    readonly property real compactWidth: Math.ceil(slack + margins + thumbW + row.spacing + Math.max(titleText.implicitWidth, subText.implicitWidth)
        + (primary ? row.spacing + tagDot : 0) + (mark !== "" ? row.spacing + markIcon.implicitWidth : 0))
    readonly property int tagDot: 6                          // PrimaryTag's dot
    readonly property int slack: 2                           // text rounding: the labels never elide at the natural width
    readonly property bool tight: naturalWidth > maxWidth

    objectName: "monitor-chip-" + (screen ? screen.name : "all")
    implicitWidth: Math.min(tight ? compactWidth : naturalWidth, maxWidth)
    width: implicitWidth
    radius: Theme.radiusPage
    color: selected ? Theme.alpha(Theme.accent, 0) : chipArea.containsMouse ? Theme.itemHover : Theme.itemFill
    border.width: grouped ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.5)
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Accessible.role: Accessible.PageTab
    Accessible.name: title
    Accessible.description: markTip
    Accessible.checked: selected

    HoverGlow { area: chipArea; radius: chip.radius }
    PressFeedback { area: chipArea }
    Label { id: tagWord; visible: false; text: "Primary"; font.pixelSize: Theme.fontCaption }
    // unelided widths of the two lines (hidden copies of the labels below)
    Label { id: titleText; visible: false; text: chip.title; font.pixelSize: Theme.fontSmall }
    Label { id: subText; visible: false; text: chip.sub; font.pixelSize: Theme.fontCaption }

    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.pad }
        spacing: Theme.gapRow
        // the wallpaper still (All: the desktop glyph)
        Item {
            Layout.preferredWidth: chip.thumbW
            Layout.preferredHeight: chip.thumbH
            Rectangle { id: corners; anchors.fill: parent; radius: Math.min(3, Theme.radiusDeep); visible: false; layer.enabled: true }
            Item {
                visible: chip.screen !== null
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: corners }
                Rectangle { anchors.fill: parent; color: Theme.itemActive }
                Image {
                    anchors.fill: parent
                    source: chip.thumb
                    sourceSize.width: 2 * chip.thumbW
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            Rectangle {
                visible: chip.screen !== null
                anchors.fill: parent
                radius: corners.radius
                color: Theme.alpha(Theme.fg, 0)
                border.width: 1
                border.color: chip.selected ? Theme.alpha(Theme.accent, 0.7) : Theme.edge
            }
            Icon { visible: chip.screen === null; anchors.centerIn: parent; text: Icons.monitor; font.pixelSize: Theme.iconMd; color: chip.selected ? Theme.accent : Theme.fgDim }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: chip.title
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSmall
                color: chip.selected ? Theme.fg : Theme.fgDim
            }
            Label {
                visible: text !== ""
                Layout.fillWidth: true
                text: chip.sub
                elide: Text.ElideRight
                font.pixelSize: Theme.fontCaption
                color: Theme.muted
            }
        }
        PrimaryTag { id: tag; Layout.fillWidth: false; visible: chip.primary; compact: chip.tight }
        Icon { id: markIcon; visible: chip.mark !== ""; text: chip.mark; font.pixelSize: Theme.iconSm; color: Theme.accent }
    }
    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
