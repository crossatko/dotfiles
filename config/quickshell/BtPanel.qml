pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// Bluetooth: the AirPods section first while AirPods are connected, then the Bluetooth header (title, Scan, Power)
// right above the device list (click = connect / disconnect / pair, right-click = forget). Without AirPods it is
// just the header and the list.
ColumnLayout {
    id: bt
    spacing: Theme.gapRow
    // the list shows whole rows (no half row at the card's edge): 6, or 4 while the AirPods section takes its share
    readonly property int listRows: pods.visible ? 4 : 6
    readonly property int listMax: listRows * (Theme.rowH + Theme.gapTight) - Theme.gapTight

    readonly property var adapter: Bluetooth.defaultAdapter   // qmllint disable unresolved-type
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

    AirPodsSection {
        id: pods
        Layout.fillWidth: true
        Layout.bottomMargin: Theme.gapRow
        // connected AirPods, or (daemon down, so nothing is known) an AirPods-looking default output: then the notice
        visible: AirPods.connected || (!AirPods.daemon && AirPods.looksLike(Pipewire.defaultAudioSink))
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

    EmptyState { visible: bt.adapter === null; icon: Icons.bluetooth; text: "No Bluetooth adapter" }
    EmptyState { visible: bt.adapter !== null && !bt.adapter.enabled; icon: Icons.bluetooth; text: "Bluetooth is off" }

    ListView {
        id: list
        visible: bt.adapter !== null && bt.adapter.enabled
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(bt.listMax, contentHeight)
        clip: true
        spacing: Theme.gapTight
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
            icon: Icons.bluetooth
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
