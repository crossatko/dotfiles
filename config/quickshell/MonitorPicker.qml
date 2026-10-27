pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Settings > Monitors: the monitor MAP and selector. Every connected monitor at its real relative size and position
// (uniformly scaled to the width and at most `maxH` tall, centred), each tile showing its wallpaper still (cover crop)
// under a soft bottom scrim with the connector name, a refresh badge and the Primary marker. Real gaps are kept, with at
// least `gap` px between neighbours. The `selected` monitor (the one the detail card below acts on) has the accent
// outline (heavier while the map has keyboard focus). Click = select, double click = make it primary (Monitors.setPrimary). Keyboard: Tab focuses the map,
// Left / Right (by position) select, Enter / Space make the selected one primary. Tiles: objectName monitor-pick-<conn>.
Rectangle {
    id: pk
    property string selected: ""                                        // connector name
    signal picked(string name)                                          // a tile was clicked / chosen by keyboard
    readonly property var screens: Monitors.screens.filter(s => s.width > 0 && s.height > 0)
    readonly property var byX: screens.slice().sort(Monitors.byPosition)
    readonly property real minX: Math.min.apply(null, screens.map(s => s.x))
    readonly property real minY: Math.min.apply(null, screens.map(s => s.y))
    readonly property real spanW: Math.max.apply(null, screens.map(s => s.x + s.width)) - minX
    readonly property real spanH: Math.max.apply(null, screens.map(s => s.y + s.height)) - minY
    readonly property var ink: Theme.barInkLight                       // light text on the dark scrim, whatever the theme mode
    readonly property real maxH: 240                                    // tallest the map gets (without the stage padding)
    readonly property real gap: Theme.controlGap                        // smallest gap between neighbouring tiles
    readonly property real pad: Theme.pad                               // stage padding around the map
    readonly property real k: spanW > 0 && spanH > 0 ? Math.min((width - 2 * pad) / spanW, maxH / spanH) : 0
    readonly property real offX: (width - spanW * k) / 2

    Layout.fillWidth: true
    implicitHeight: Math.round(spanH * k) + 2 * pad
    // the stage: a quiet page-level box the map sits in
    radius: Theme.radiusPage
    color: Theme.alpha(Theme.fg, 0.03)
    border.width: 1
    border.color: Theme.edge

    activeFocusOnTab: true
    function step(d) {
        const i = byX.findIndex(s => s.name === selected)
        const s = byX[Math.max(0, Math.min(byX.length - 1, (i < 0 ? 0 : i + d)))]
        if (s) pk.picked(s.name)
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            const s = Monitors.byName(pk.selected)
            if (s) Monitors.setPrimary(s)
            e.accepted = true
        }
    }

    Repeater {
        model: pk.screens
        Item {
            id: th
            required property var modelData
            readonly property bool primary: Monitors.isPrimary(modelData)
            readonly property bool sel: modelData.name === pk.selected
            readonly property bool small: width < 120                   // too small for the badge next to the name
            objectName: "monitor-pick-" + modelData.name
            x: Math.round(pk.offX + (modelData.x - pk.minX) * pk.k + pk.gap / 2)
            y: Math.round(pk.pad + (modelData.y - pk.minY) * pk.k + pk.gap / 2)
            width: Math.round(modelData.width * pk.k - pk.gap)
            height: Math.round(modelData.height * pk.k - pk.gap)
            Accessible.role: Accessible.RadioButton
            Accessible.name: Monitors.title(modelData)
            Accessible.checked: sel

            // wallpaper, cover-cropped, clipped to the rounded tile
            Rectangle { id: corners; anchors.fill: parent; radius: Theme.radiusItem; visible: false; layer.enabled: true }
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: corners }
                Rectangle { anchors.fill: parent; color: Theme.itemFill }
                Image {
                    anchors.fill: parent
                    source: LockWallpapers.stillFor(th.modelData)
                    sourceSize.width: 2 * th.width
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                }
                // the scrim the labels sit on: readable over any wallpaper
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: Math.min(parent.height, 56)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.alpha(pk.ink.bg, 0) }
                        GradientStop { position: 1; color: Theme.alpha(pk.ink.bg, 0.75) }
                    }
                }
                // hover / press wash
                Rectangle { anchors.fill: parent; color: Theme.alpha(pk.ink.fg, thArea.pressed ? 0.14 : thArea.containsMouse ? 0.08 : 0) }
            }
            // the outline: accent = selected, the hairline otherwise
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusItem
                color: Theme.alpha(Theme.accent, 0)
                border.width: th.sel ? (pk.activeFocus ? 3 : 2) : 1          // keyboard focus: a heavier outline
                border.color: th.sel ? Theme.accent : Theme.edge
                Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            }
            PressFeedback { area: thArea }

            // Primary marker: top left, a dark chip with the accent dot
            Rectangle {
                visible: th.primary
                anchors { left: parent.left; top: parent.top; margins: Theme.controlGap }
                width: tagRow.implicitWidth + 2 * Theme.controlGap
                height: tagRow.implicitHeight + 4
                radius: Math.min(Theme.radiusDeep, height / 3)
                color: Theme.alpha(pk.ink.bg, 0.72)
                RowLayout {
                    id: tagRow
                    anchors.centerIn: parent
                    spacing: Theme.gapTight
                    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: pk.ink.accent }
                    Label { visible: th.width >= 70; text: "Primary"; font.pixelSize: Theme.fontTiny; font.bold: true; color: pk.ink.fg }
                }
            }
            // name bottom left, refresh badge bottom right
            RowLayout {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.gapRow }
                spacing: Theme.controlGap
                Label {
                    text: Monitors.label(th.modelData)
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                    color: pk.ink.fg
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: !th.small && Monitors.mode(th.modelData).hz > 0
                    text: Math.round(Monitors.mode(th.modelData).hz) + " Hz"
                    font.pixelSize: Theme.fontTiny
                    color: pk.ink.fgDim
                }
            }

            MouseArea {
                id: thArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pk.picked(th.modelData.name)
                onDoubleClicked: { pk.picked(th.modelData.name); Monitors.setPrimary(th.modelData) }
            }
        }
    }
}
