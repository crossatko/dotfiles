import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

// Wired status + Wi-Fi list + Tailscale machines. Wi-Fi password prompt appears inline for new secured networks.
ColumnLayout {
    id: net
    spacing: 8
    readonly property int rowH: 44         // every connection row, wired or Wi-Fi
    readonly property int rowGap: 6        // gap between any two rows
    implicitHeight: Math.min(760, header.implicitHeight + body.implicitHeight + tailscale.implicitHeight + 48)

    readonly property var devs: Networking.devices.values
    readonly property var wired: devs.filter(d => d.type === DeviceType.Wired)
    readonly property var wifiDev: devs.find(d => d.type === DeviceType.Wifi) || null
    property var asking: null       // WifiNetwork waiting for a password (its card shows the form)
    property var frozen: []         // the list as it was when the form opened (see wifiList.model)

    // scan only while this panel is open
    Component.onCompleted: if (wifiDev) wifiDev.scannerEnabled = true
    Component.onDestruction: if (wifiDev) wifiDev.scannerEnabled = false

    function bars(s) { return s > 0.66 ? "\uf1eb" : s > 0.33 ? "\uf6ab" : "\uf6aa" }
    function stateText(st) {
        return st === ConnectionState.Connected ? "Connected" : st === ConnectionState.Connecting ? "Connecting…"
             : st === ConnectionState.Disconnecting ? "Disconnecting…" : "Disconnected"
    }
    // how many connections are up right now (wired devices + connected Wi-Fi networks)
    readonly property int linksUp: wired.filter(d => d.connected).length + (wifiDev ? wifiDev.networks.values.filter(n => n.connected).length : 0)
    property var confirm: null            // {label, run} waiting for "yes, cut my only connection"

    // Run `action` now, or first ask when it would take down the last connection (that is how you lock
    // yourself out of the machine remotely, or lose this session).
    function guarded(label, wasUp, action) {
        if (wasUp && linksUp <= 1) { confirm = { label: label, run: action }; return }
        action()
    }
    function setWired(d, wantOn) {
        if (wantOn) { if (d.network) d.network.connect() }
        else guarded(d.name, d.connected, () => d.disconnect())
    }
    function setWifi(n, wantOn) {
        if (wantOn) pick(n)
        else guarded(n.name, n.connected, () => n.disconnect())
    }

    property var lastTried: null
    function submit(n, psk) {
        if (psk.length < 8) return
        lastTried = n
        n.connectWithPsk(psk)
        asking = null
    }

    function pick(n) {
        if (n.connected) { n.disconnect(); return }
        if (n.known || n.security === WifiSecurityType.Open) { n.connect(); return }
        frozen = wifiDev ? wifiDev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []
        asking = n
    }

    RowLayout {
        id: header
        Layout.fillWidth: true
        Label { text: "Network"; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.fillWidth: true }
    }

    Rectangle {
        visible: net.confirm !== null
        Layout.fillWidth: true
        implicitHeight: confirmRow.implicitHeight + 16
        radius: Theme.radiusItem
        color: Theme.alpha(Theme.red, 0.16)
        border.width: 1
        border.color: Theme.alpha(Theme.red, 0.7)
        ColumnLayout {
            id: confirmRow
            anchors { fill: parent; margins: 8 }
            spacing: 6
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: net.confirm ? "Disconnect " + net.confirm.label + "? It is your only active connection." : ""
                font.pixelSize: Theme.fontSmall
            }
            RowLayout {
                spacing: 6
                Btn { outerRadius: Theme.radiusItem; inset: 8; text: "Cancel"; onClicked: net.confirm = null }
                Btn { outerRadius: Theme.radiusItem; inset: 8; text: "Disconnect"; active: true; onClicked: { const c = net.confirm; net.confirm = null; c.run() } }
            }
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: net.rowGap

        SectionHead {
            visible: net.wired.length > 0
            title: "Wired"
            detail: net.wired.filter(d => d.connected).length + " / " + net.wired.length + " connected"
        }

        Repeater {
            model: net.wired
            Rectangle {
                id: wiredRow
                required property var modelData
                readonly property bool canToggle: !!modelData.network || modelData.connected
                readonly property bool on: modelData.state === ConnectionState.Connected || modelData.state === ConnectionState.Connecting
                Layout.fillWidth: true
                implicitHeight: net.rowH
                radius: Theme.radiusItem
                opacity: canToggle ? 1 : 0.45
                color: wiredArea.containsMouse && canToggle ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.07)
                MouseArea {
                    id: wiredArea
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    enabled: wiredRow.canToggle
                    cursorShape: Qt.PointingHandCursor
                    onClicked: net.setWired(wiredRow.modelData, !wiredRow.on)
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 14
                    Icon { text: "\uf796"; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 22; font.pixelSize: 18; color: modelData.connected ? Theme.accent : Theme.muted }
                    ColumnLayout {
                        spacing: 0
                        Label { text: modelData.name }
                        Label { text: net.stateText(modelData.state) + (modelData.linkSpeed > 0 ? " · " + modelData.linkSpeed + " Mb/s" : ""); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    }
                    Item { Layout.fillWidth: true }
                    RowState {
                        connected: modelData.state === ConnectionState.Connected
                        hovered: wiredArea.containsMouse
                        hintable: wiredRow.canToggle
                        busy: modelData.state === ConnectionState.Connecting || modelData.state === ConnectionState.Disconnecting
                    }
                }
            }
        }

        SectionHead {
            Layout.topMargin: 8
            title: "Wireless"
            detail: net.wifiDev && Networking.wifiEnabled ? net.wifiDev.networks.values.length + " networks" : ""
            Toggle {
                visible: net.wifiDev !== null
                checked: Networking.wifiEnabled
                onToggled: want => {
                    if (want) Networking.wifiEnabled = true
                    else net.guarded("Wi-Fi", net.wifiDev && net.wifiDev.connected, () => Networking.wifiEnabled = false)
                }
            }
        }

        Label {
            visible: net.wifiDev === null
            text: "No Wi-Fi adapter"
            color: Theme.muted
        }
        Label {
            visible: net.wifiDev !== null && !Networking.wifiEnabled
            text: "Wi-Fi is off"
            color: Theme.muted
        }

        ListView {
            id: wifiList
            visible: net.wifiDev !== null && Networking.wifiEnabled
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(net.asking ? 380 : 260, contentHeight)
            clip: true
            spacing: net.rowGap
            // frozen while a password is being typed: the live list re-sorts whenever a signal strength changes,
            // which would rebuild every card and wipe the half-typed password
            model: net.asking ? net.frozen : net.wifiDev
                ? net.wifiDev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
                : []
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property bool asking: net.asking === modelData
                property bool failed: false
                width: wifiList.width
                height: net.rowH + (asking ? form.implicitHeight + 10 : 0)
                clip: true
                radius: Theme.radiusItem
                color: asking ? Theme.alpha(Theme.accent, 0.12)
                    : area.containsMouse ? Theme.alpha(Theme.fg, 0.12) : modelData.connected ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.fg, 0.05)
                border.width: asking ? 1 : 0
                border.color: Theme.alpha(Theme.accent, 0.7)
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                onAskingChanged: if (asking) {
                    failed = false; pw.text = ""
                    Qt.callLater(() => { pw.forceActiveFocus(); wifiList.positionViewAtIndex(index, ListView.Contain) })
                }
                // keep the whole card (buttons included) in view while it grows
                onHeightChanged: if (asking) wifiList.positionViewAtIndex(index, ListView.Contain)
                Connections {
                    target: card.modelData
                    function onConnectionFailed() { if (card.asking || net.lastTried === card.modelData) card.failed = true }
                }

                RowLayout {
                    id: top
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
                    height: net.rowH
                    spacing: 14
                    Icon { text: net.bars(modelData.signalStrength); horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 22; font.pixelSize: 16; color: modelData.connected ? Theme.accent : Theme.fg }
                    Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                    Icon { visible: modelData.security !== WifiSecurityType.Open; text: "\uf023"; font.pixelSize: 13; color: Theme.muted }
                    RowState {
                        connected: modelData.connected
                        busy: modelData.stateChanging
                        hovered: area.containsMouse
                    }
                }
                MouseArea {
                    id: area
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: net.rowH
                    z: -1
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => mouse.button === Qt.RightButton && modelData.known ? modelData.forget() : net.setWifi(modelData, !modelData.connected)
                }

                // password form, expands inside this card
                ColumnLayout {
                    id: form
                    anchors { left: parent.left; right: parent.right; top: top.bottom; leftMargin: 12; rightMargin: 12; topMargin: 2 }
                    spacing: 6
                    opacity: card.asking ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.inner(card.radius, 12)    // inside the card's 12 px padding
                        color: Theme.alpha(Theme.bg, 0.6)
                        border.width: 1
                        border.color: card.failed ? Theme.alpha(Theme.red, 0.9) : pw.activeFocus ? Theme.alpha(Theme.accent, 0.9) : Theme.alpha(Theme.overlay, 0.6)
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                            spacing: 6
                            TextInput {
                                id: pw
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: reveal.shown ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                clip: true
                                onTextChanged: card.failed = false
                                onAccepted: net.submit(card.modelData, text)
                                Keys.onEscapePressed: { Popups.escAt = Date.now(); net.asking = null }
                                Label { visible: pw.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Password"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                            }
                            Icon {
                                id: reveal
                                property bool shown: false
                                text: shown ? "\uf06e" : "\uf070"
                                color: revealArea.containsMouse ? Theme.fg : Theme.muted
                                font.pixelSize: 15
                                MouseArea { id: revealArea; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: reveal.shown = !reveal.shown }
                            }
                        }
                    }
                    Label { visible: card.failed; text: "Could not connect. Wrong password?"; color: Theme.red; font.pixelSize: Theme.fontCaption }
                    RowLayout {
                        spacing: 6
                        Btn { outerRadius: card.radius; text: "Cancel"; onClicked: net.asking = null }
                        Btn { outerRadius: card.radius; text: "Connect"; active: true; enabledLook: pw.text.length >= 8; onClicked: net.submit(card.modelData, pw.text) }
                    }
                }
            }
        }
    }

    // own file, so this already-loaded panel needs no inline component (hot reload)
    TailscaleSection {
        id: tailscale
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: 8
    }
}
