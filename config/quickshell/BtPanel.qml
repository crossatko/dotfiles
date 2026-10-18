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
        delegate: ListRow {
            id: devRow
            required property var modelData
            width: list.width
            rowH: 46
            icon: "\uf293"
            iconColor: modelData.connected ? Theme.accent : Theme.fg
            selected: modelData.connected
            rightClick: true
            onClicked: mouse => mouse.button === Qt.RightButton ? modelData.forget() : bt.act(modelData)
            RowText { title: devRow.modelData.name || devRow.modelData.address; sub: bt.sub(devRow.modelData) }
            RowState {
                connected: devRow.modelData.connected
                hovered: devRow.hovered
                busy: devRow.modelData.pairing || devRow.modelData.state === BluetoothDeviceState.Connecting || devRow.modelData.state === BluetoothDeviceState.Disconnecting
            }
        }
    }
}
