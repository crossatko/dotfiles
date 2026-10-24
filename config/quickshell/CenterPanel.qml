pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// Control center: quick toggles (incl. do not disturb), volume / microphone, brightness. The notification list is NotifPanel (clock chip).
GridLayout {
    id: cc
    columns: 1
    rowSpacing: 12
    columnSpacing: 0

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    readonly property var sink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var source: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null
    readonly property var adapter: Bluetooth.defaultAdapter   // qmllint disable unresolved-type
    readonly property int btConnected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0   // qmllint disable missing-property
    readonly property var netDevs: Networking.devices.values   // qmllint disable missing-property
    readonly property int wiredUp: netDevs.filter(d => d.type === DeviceType.Wired && d.connected).length

    function open(name) { Popups.toggle(name, Popups.screen) }

    ColumnLayout {
        id: controlSec
        Layout.fillWidth: true
        spacing: 12

        PanelHeader {
            title: "Control center"
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
                icon: Icons.volumeGlyph(!cc.sink || cc.sink.muted, cc.sink ? cc.sink.volume : 0)
                title: "Sound"
                sub: cc.sink ? (cc.sink.muted ? "Muted" : Math.round(cc.sink.volume * 100) + "%") : "No output"
                on: cc.sink !== null && !cc.sink.muted
                onClicked: if (cc.sink) cc.sink.muted = !cc.sink.muted
            }
        }

        AudioSection { Layout.fillWidth: true }
        BrightnessSection { Layout.fillWidth: true }
    }
}
