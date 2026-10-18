import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// Control + notification center: quick toggles, volume / microphone, brightness, then the notification history.
GridLayout {
    id: cc
    columns: 1
    rowSpacing: 12
    columnSpacing: 0
    // The control section hangs next to the bar and the notifications sit beyond it: panel at the
    // bottom -> notifications on top, control center at the bottom; bar at the top -> reversed.
    readonly property bool barBottom: Popups.edgeOf(Popups.screen) !== "top"

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    readonly property var sink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var source: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int btConnected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0
    readonly property var netDevs: Networking.devices.values
    readonly property int wiredUp: netDevs.filter(d => d.type === DeviceType.Wired && d.connected).length

    function open(name) { Popups.toggle(name, Popups.screen, Popups.right) }

    ColumnLayout {
        id: controlSec
        Layout.fillWidth: true
        Layout.row: cc.barBottom ? 2 : 0
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Control center"; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
            // gear: Settings window (bar layout, monitors); opens on this popup's monitor
            Btn { icon: true; text: "\uf013"; onClicked: Popups.settingsRequest("open", "") }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Tile {
                Layout.fillWidth: true
                icon: Networking.wifiEnabled ? "\uf1eb" : "\uf6ac"
                title: "Wi-Fi"
                sub: cc.wiredUp > 0 ? cc.wiredUp + " wired up" : (Networking.wifiEnabled ? "On" : "Off")
                on: Networking.wifiEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                onSecondary: cc.open("net")
            }
            Tile {
                Layout.fillWidth: true
                visible: cc.adapter !== null
                icon: "\uf293"
                title: "Bluetooth"
                sub: !cc.adapter || !cc.adapter.enabled ? "Off" : cc.btConnected > 0 ? cc.btConnected + " connected" : "On"
                on: cc.adapter !== null && cc.adapter.enabled
                onClicked: cc.adapter.enabled = !cc.adapter.enabled
                onSecondary: cc.open("bt")
            }
            Tile {
                Layout.fillWidth: true
                icon: Notifs.dnd ? "\uf1f6" : "\uf0f3"
                title: "Do not disturb"
                sub: Notifs.dnd ? "On" : "Off"
                on: Notifs.dnd
                onClicked: Notifs.setDnd(!Notifs.dnd)
            }
            Tile {
                Layout.fillWidth: true
                icon: !cc.sink || cc.sink.muted ? "\uf6a9" : cc.sink.volume < 0.01 ? "\uf026" : cc.sink.volume < 0.5 ? "\uf027" : "\uf028"
                title: "Sound"
                sub: cc.sink ? (cc.sink.muted ? "Muted" : Math.round(cc.sink.volume * 100) + "%") : "No output"
                on: cc.sink !== null && !cc.sink.muted
                onClicked: if (cc.sink) cc.sink.muted = !cc.sink.muted
            }
        }

        AudioSection { Layout.fillWidth: true }
        BrightnessSection { Layout.fillWidth: true }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.row: 1
        height: 1
        color: Theme.alpha(Theme.overlay, 0.5)
    }

    ColumnLayout {
        id: notifSec
        Layout.fillWidth: true
        Layout.fillHeight: true               // takes whatever the minimum panel height leaves over
        Layout.row: cc.barBottom ? 0 : 2
        spacing: 12


        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Label { text: "Notifications"; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true }
            Label { visible: Notifs.count > 0; text: Notifs.count; color: Theme.fgDim; font.pixelSize: 12 }
            Btn { text: "Clear"; enabledLook: Notifs.count > 0; onClicked: Notifs.clearAll() }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true               // takes whatever the minimum panel height leaves over
            Layout.minimumHeight: 52
            Layout.preferredHeight: Notifs.count === 0 ? 52 : Math.min(contentHeight, 360)
            clip: true
            spacing: 8
            model: Notifs.all.values.slice().reverse()      // newest first
            delegate: Item {
                id: row
                required property var modelData
                width: list.width
                height: card.implicitHeight * card.collapse
                clip: card.leaving
                NotifCard {
                    id: card
                    n: row.modelData
                    width: row.width
                }
            }

            Label {
                anchors.centerIn: parent
                visible: Notifs.count === 0
                text: Notifs.dnd ? "Do not disturb is on" : "No notifications"
                color: Theme.muted
            }
        }
    }
}
