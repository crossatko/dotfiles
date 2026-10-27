pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wired status + Wi-Fi list + Tailscale machines + Mullvad (both VPN sections fold, see FoldSection). Wi-Fi password prompt appears inline for new secured networks.
ColumnLayout {
    id: net
    spacing: Theme.gapRow
    readonly property int rowH: Theme.rowH            // every connection row, wired or Wi-Fi
    readonly property int rowGap: Theme.gapTight      // gap between any two rows (items of a list)
    readonly property int maxH: 760                   // content cap of the popup
    readonly property int listRows: 5                 // Wi-Fi list: whole rows, then it scrolls (as BtPanel)
    readonly property int listMax: listRows * (rowH + rowGap) - rowGap
    readonly property int formH: 2 * Theme.controlH + Theme.controlGap + Theme.padSm + Theme.gapTight / 2   // password form: field + buttons + gaps (bodyTop / bodyGap below)
    readonly property int listMaxAsking: listMax + formH   // ... while a password form is open: the same rows plus the form
    implicitHeight: Math.min(maxH, header.implicitHeight + body.implicitHeight + tailscale.implicitHeight + mullvad.implicitHeight + 5 * Theme.gapRow + 2 * Theme.gapTight)

    readonly property var devs: Networking.devices.values   // qmllint disable missing-property
    readonly property var wired: devs.filter(d => d.type === DeviceType.Wired)
    readonly property var wifiDev: devs.find(d => d.type === DeviceType.Wifi) || null
    property var asking: null       // WifiNetwork waiting for a password (its card shows the form)
    property var frozen: []         // the list as it was when the form opened (see wifiList.model)

    // scan only while this panel is open
    Component.onCompleted: if (wifiDev) wifiDev.scannerEnabled = true
    Component.onDestruction: if (wifiDev) wifiDev.scannerEnabled = false

    function bars(s) { return s > 0.66 ? Icons.wifi : s > 0.33 ? Icons.wifiFair : Icons.wifiWeak }
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

    PanelHeader {
        id: header
        title: "Network"
    }

    // Captive portal: NetworkManager says the link is up but a sign-in page is in the way. "Sign in" opens the URL NM
    // probes (the portal redirects it to its login page) in the default browser.
    readonly property bool portal: Networking.connectivity === NetworkConnectivity.Portal   // qmllint disable missing-property
    Process {
        id: portalUrl
        command: ["busctl", "--system", "get-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
            "org.freedesktop.NetworkManager", "ConnectivityCheckUri"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /"(https?:\/\/[^"]+)"/.exec(text)
                if (m) Quickshell.execDetached(["xdg-open", m[1]])
            }
        }
    }
    Notice {
        visible: net.portal
        padX: Theme.gapRow
        padY: Theme.gapRow
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "This network needs a sign-in."
            font.pixelSize: Theme.fontSmall
        }
        Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Sign in"; active: true; onClicked: portalUrl.running = true }
    }

    Notice {
        visible: net.confirm !== null
        danger: true
        padX: Theme.gapRow
        padY: Theme.gapRow
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: net.confirm ? "Disconnect " + net.confirm.label + "? It is your only active connection." : ""
            font.pixelSize: Theme.fontSmall
        }
        RowLayout {
            spacing: Theme.controlGap
            Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Cancel"; onClicked: net.confirm = null }
            Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Disconnect"; active: true; onClicked: { const c = net.confirm; net.confirm = null; c.run() } }
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: Theme.gapRow      // head <-> list; the blocks below add gapTight (= pad between blocks)

        SectionHead {
            visible: net.wired.length > 0
            title: "Wired"
            detail: net.wired.filter(d => d.connected).length + " / " + net.wired.length + " connected"
        }

        ColumnLayout {
            visible: net.wired.length > 0
            Layout.fillWidth: true
            spacing: net.rowGap
            Repeater {
                model: net.wired
                ListRow {
                    id: wiredRow
                    required property var modelData
                    readonly property bool canToggle: !!modelData.network || modelData.connected
                    readonly property bool on: modelData.state === ConnectionState.Connected || modelData.state === ConnectionState.Connecting
                    Layout.fillWidth: true
                    rowH: net.rowH
                    icon: Icons.ethernet
                    iconColor: modelData.connected ? Theme.accent : Theme.muted   // the icon and the check carry the state; the row stays neutral
                    baseColor: Theme.alpha(Theme.fg, 0.07)
                    interactive: canToggle
                    opacity: canToggle ? 1 : Theme.disabledOpacity
                    onClicked: net.setWired(wiredRow.modelData, !wiredRow.on)
                    RowText {
                        title: wiredRow.modelData.name
                        sub: net.stateText(wiredRow.modelData.state) + (wiredRow.modelData.linkSpeed > 0 ? " · " + wiredRow.modelData.linkSpeed + " Mb/s" : "")
                    }
                    RowState {
                        connected: wiredRow.modelData.state === ConnectionState.Connected
                        hovered: wiredRow.hovered
                        hintable: wiredRow.canToggle
                        busy: wiredRow.modelData.state === ConnectionState.Connecting || wiredRow.modelData.state === ConnectionState.Disconnecting
                    }
                }
            }
        }

        SectionHead {
            Layout.topMargin: net.wired.length > 0 ? Theme.gapTight : 0
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

        EmptyState { visible: net.wifiDev === null; icon: Icons.wifiOff; text: "No Wi-Fi adapter" }
        EmptyState { visible: net.wifiDev !== null && !Networking.wifiEnabled; icon: Icons.wifiOff; text: "Wi-Fi is off" }

        ListView {
            id: wifiList
            visible: net.wifiDev !== null && Networking.wifiEnabled
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(net.asking ? net.listMaxAsking : net.listMax, contentHeight)
            clip: true
            spacing: net.rowGap
            // frozen while a password is being typed: the live list re-sorts whenever a signal strength changes,
            // which would rebuild every card and wipe the half-typed password
            model: net.asking ? net.frozen : net.wifiDev
                ? net.wifiDev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
                : []
            delegate: ListRow {
                id: card
                required property var modelData
                required property int index
                readonly property bool asking: net.asking === modelData
                property bool failed: false
                width: wifiList.width
                rowH: net.rowH
                icon: net.bars(modelData.signalStrength)
                iconColor: modelData.connected ? Theme.accent : Theme.fg
                selected: modelData.connected
                outlined: asking
                color: asking ? Theme.alpha(Theme.accent, 0.12) : stateColor
                rightClick: true
                onClicked: mouse => mouse.button === Qt.RightButton && modelData.known ? modelData.forget() : net.setWifi(modelData, !modelData.connected)
                // the password form below expands inside this card
                expanded: asking
                bodyTop: Theme.gapTight / 2
                bodyGap: Theme.padSm

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

                RowText { title: card.modelData.name }
                Icon { visible: card.modelData.security !== WifiSecurityType.Open; text: Icons.lock; font.pixelSize: Theme.iconSm; color: Theme.muted }
                RowState {
                    connected: card.modelData.connected
                    busy: card.modelData.stateChanging
                    hovered: card.hovered
                }

                body: ColumnLayout {
                    id: form
                    Layout.fillWidth: true
                    spacing: Theme.controlGap
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.controlH
                        radius: Theme.inner(card.radius, Theme.pad)    // inside the card's padding
                        color: Theme.alpha(Theme.bg, 0.6)
                        border.width: 1
                        border.color: card.failed ? Theme.dangerEdge : pw.activeFocus ? Theme.accentEdge : Theme.edge
                        Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.controlGap }
                            spacing: Theme.controlGap
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
                                text: shown ? Icons.eye : Icons.eyeOff
                                color: revealArea.containsMouse ? Theme.fg : Theme.muted
                                font.pixelSize: Theme.iconMd
                                MouseArea { id: revealArea; anchors.fill: parent; anchors.margins: -Theme.gapTight; hoverEnabled: true; onClicked: reveal.shown = !reveal.shown }
                            }
                        }
                    }
                    Label { visible: card.failed; text: "Could not connect. Wrong password?"; color: Theme.red; font.pixelSize: Theme.fontCaption }
                    RowLayout {
                        spacing: Theme.controlGap
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
        Layout.topMargin: Theme.gapTight
    }
    MullvadSection {
        id: mullvad
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Theme.gapTight
    }
}
