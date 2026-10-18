import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Bluetooth: power, scan, and a device list (click = connect / disconnect / pair, right-click = forget).
ColumnLayout {
    id: bt
    spacing: 8
    implicitHeight: Math.min(460, 70 + Math.min(300, list.contentHeight) + 20)

    readonly property var adapter: Bluetooth.defaultAdapter
    // scanning is manual (the Scan button): auto start/stop on open/close races BlueZ ("operation already in progress")

    // BlueZ names unnamed devices after their MAC address ("2A-C5-C8-72-AF-B8"); that's discovery noise
    function named(d) { return d.name && d.name !== "" && !/^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(d.name) }

    function sub(d) {
        if (d.pairing) return "Pairing…"
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")
        return d.paired ? "Paired" : "Not paired"
    }
    function act(d) {
        if (d.connected) d.disconnect()
        else if (d.paired) d.connect()
        else d.pair()
    }

    PanelHeader {
        title: "Bluetooth"
        Btn {
            visible: bt.adapter !== null && bt.adapter.enabled
            text: "Scan"
            active: bt.adapter && bt.adapter.discovering
            onClicked: bt.adapter.discovering = !bt.adapter.discovering
        }
        Label { visible: bt.adapter !== null; text: "Power"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        Toggle {
            visible: bt.adapter !== null
            checked: bt.adapter !== null && bt.adapter.enabled
            busy: bt.adapter !== null && (bt.adapter.state === BluetoothAdapterState.Enabling || bt.adapter.state === BluetoothAdapterState.Disabling)
            onToggled: want => bt.adapter.enabled = want
        }
    }

    Label { visible: bt.adapter === null; text: "No Bluetooth adapter"; color: Theme.muted }
    Label { visible: bt.adapter !== null && !bt.adapter.enabled; text: "Bluetooth is off"; color: Theme.muted }

    ListView {
        id: list
        visible: bt.adapter !== null && bt.adapter.enabled
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(300, contentHeight)
        clip: true
        spacing: 4
        // connected first, then paired, then the rest (by name); skip nameless discovery noise
        model: bt.adapter
            ? bt.adapter.devices.values
                .filter(d => d.paired || d.connected || bt.named(d))
                .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
            : []
        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: 46
            radius: Theme.radiusItem
            color: area.containsMouse ? Theme.alpha(Theme.fg, 0.12) : modelData.connected ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.fg, 0.05)
            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 14
                Icon { text: "\uf293"; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 22; font.pixelSize: 18; color: modelData.connected ? Theme.accent : Theme.fg }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: modelData.name || modelData.address; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { text: bt.sub(modelData); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                }
                RowState {
                    connected: modelData.connected
                    hovered: area.containsMouse
                    busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => mouse.button === Qt.RightButton ? modelData.forget() : bt.act(modelData)
            }
        }
    }
}
