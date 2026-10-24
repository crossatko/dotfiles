pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Current audio device with a dropdown of all the others (hardware only: no streams, monitors or
// filters). Choosing one sets Pipewire's preferred default, i.e. what `wpctl set-default` does.
ColumnLayout {
    id: dp

    property bool isSink: true
    property bool open: false

    readonly property var current: isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    readonly property string wantClass: isSink ? "Audio/Sink" : "Audio/Source"
    readonly property var devices: Pipewire.nodes.values.filter(n =>   // qmllint disable missing-property
        !n.isStream && n.isSink === isSink && n.properties && n.properties["media.class"] === wantClass)

    function label(n) { return n ? (n.description || n.nickname || n.name) : "No device" }
    function choose(n) {
        if (isSink) Pipewire.preferredDefaultAudioSink = n
        else Pipewire.preferredDefaultAudioSource = n
        open = false
    }

    spacing: 4

    // properties (media.class, ...) are only filled in for nodes something is bound to
    PwObjectTracker { objects: Pipewire.nodes.values }   // qmllint disable missing-property

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusItem
        color: headGlow.hovered ? Theme.alpha(Theme.fg, 0.13) : Theme.alpha(Theme.fg, 0.07)
        border.width: dp.open ? 1 : 0
        border.color: Theme.alpha(Theme.accent, 0.8)
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            Label { text: dp.label(dp.current); Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall }
            Icon {
                text: "\uf078"
                font.pixelSize: 12
                color: Theme.fgDim
                rotation: dp.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        HoverGlow { id: headGlow; area: head; radius: Theme.radiusItem }
        MouseArea { id: head; anchors.fill: parent; hoverEnabled: true; onClicked: dp.open = !dp.open }
    }

    // dropdown list; collapses to zero height so the panel resizes around it
    Item {
        Layout.fillWidth: true
        implicitHeight: dp.open ? list.implicitHeight : 0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: list
            width: parent.width
            spacing: 3
            Repeater {
                model: dp.devices
                Rectangle {
                    id: optRow
                    required property var modelData
                    readonly property bool isCurrent: dp.current !== null && modelData.id === dp.current.id
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.radiusItem
                    color: isCurrent ? Theme.alpha(Theme.accent, 0.22) : optGlow.hovered ? Theme.alpha(Theme.fg, 0.12) : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        Label { text: dp.label(optRow.modelData); Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: optRow.isCurrent ? Theme.accent : Theme.fg }
                        Icon { visible: optRow.isCurrent; text: "\uf00c"; font.pixelSize: 12; color: Theme.accent }
                    }
                    HoverGlow { id: optGlow; area: opt; radius: Theme.radiusItem }
                    MouseArea { id: opt; anchors.fill: parent; hoverEnabled: true; onClicked: dp.choose(optRow.modelData) }
                }
            }
            Label { visible: dp.devices.length === 0; text: "No devices"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
        }
    }
}
