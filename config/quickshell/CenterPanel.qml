import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// Control + notification center: quick toggles, volume / microphone, then the notification history.
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

    property bool panelsOpen: false

    function open(name) { Popups.toggle(name, Popups.screen, Popups.right) }

    ColumnLayout {
        id: controlSec
        Layout.fillWidth: true
        Layout.row: cc.barBottom ? 2 : 0
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Control center"; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
            // panel (bar) settings: which monitors have one and on which edge
            Btn { icon: true; text: "\uf013"; active: cc.panelsOpen; onClicked: cc.panelsOpen = !cc.panelsOpen }
        }

        // ---- panel settings (behind the gear) ----
        ColumnLayout {
            id: panelSettings
            Layout.fillWidth: true
            visible: cc.panelsOpen
            spacing: 6

            SectionHead { title: "Panels"; detail: BarConfig.enabledCount + " of " + Quickshell.screens.length + " monitors" }

            Repeater {
                model: Quickshell.screens
                Rectangle {
                    id: mon
                    required property var modelData
                    readonly property bool on: BarConfig.enabled(modelData)
                    readonly property bool onlyOne: on && BarConfig.enabledCount <= 1
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: Math.max(0, Theme.rounding - 4)
                    color: Theme.alpha(Theme.fg, 0.06)
                    border.width: on ? 1 : 0
                    border.color: Theme.alpha(Theme.accent, 0.5)

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                        spacing: 8
                        Toggle {
                            checked: mon.on
                            enabledLook: !mon.onlyOne           // the last bar is the way back into this menu
                            onToggled: want => BarConfig.set(mon.modelData, "enabled", want)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: mon.modelData.model || mon.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: mon.modelData.name + " · " + mon.modelData.width + "×" + mon.modelData.height; color: Theme.fgDim; font.pixelSize: 11 }
                        }
                        Btn { text: "Top"; active: mon.on && BarConfig.edge(mon.modelData) === "top"; enabledLook: mon.on; onClicked: BarConfig.set(mon.modelData, "edge", "top") }
                        Btn { text: "Bottom"; active: mon.on && BarConfig.edge(mon.modelData) === "bottom"; enabledLook: mon.on; onClicked: BarConfig.set(mon.modelData, "edge", "bottom") }
                    }
                }
            }

            // which modules the bars show (all bars alike). The notification chip that opens this panel is
            // not listed: it always stays, so nothing here can lock you out.
            SectionHead {
                Layout.topMargin: 6
                title: "Bar widgets"
                detail: BarWidgets.shownCount + " of " + BarWidgets.widgets.length + " shown"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 6
                columnSpacing: 6
                Repeater {
                    model: BarWidgets.widgets
                    Rectangle {
                        id: wid
                        required property var modelData
                        readonly property bool on: BarWidgets.shown(modelData.id)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1          // equal columns
                        implicitHeight: 40
                        radius: Math.max(0, Theme.rounding - 4)
                        color: Theme.alpha(Theme.fg, 0.06)
                        border.width: on ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.5)

                        MouseArea {                       // the whole row toggles, not just the switch
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarWidgets.set(wid.modelData.id, !wid.on)
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                            spacing: 8
                            Label {
                                text: wid.modelData.icon
                                font.family: Theme.iconFont; font.styleName: "Regular"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                Layout.preferredWidth: 18
                                color: wid.on ? Theme.accent : Theme.muted
                            }
                            Label { text: wid.modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; color: wid.on ? Theme.fg : Theme.fgDim }
                            Toggle {
                                implicitWidth: 34; implicitHeight: 18
                                checked: wid.on
                                onToggled: want => BarWidgets.set(wid.modelData.id, want)
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; height: 1; color: Theme.alpha(Theme.overlay, 0.5) }
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
