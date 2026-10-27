pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "launcher/js/Vpn.js" as Vpn

// Tailscale section of the network popup: connect/disconnect toggle + every machine on the tailnet, folded by
// default (FoldSection: the head row keeps a state summary and the switch).
// Lives only while the popup is open (the Loader drops it on close), so it polls `tailscale status --json`
// every 4 s while visible and not at all otherwise. `QS_TAILSCALE` replaces the binary (tests).
ColumnLayout {
    id: ts
    spacing: Theme.controlGap

    readonly property string bin: Quickshell.env("QS_TAILSCALE") ? String(Quickshell.env("QS_TAILSCALE")) : "tailscale"
    readonly property int rowH: Theme.rowH
    readonly property int listGap: Theme.gapTight                                    // items of a list
    readonly property int maxListH: 5 * rowH + 4 * listGap                           // 5 whole rows, then it scrolls (as BtPanel)
    readonly property int keyColW: 64     // width of the key column in a machine's details

    property bool loaded: false
    property bool daemonDown: false
    property string backend: ""           // BackendState: Running, Starting, Stopped, NeedsLogin, NeedsMachineAuth, NoState
    property string tailnet: ""
    property var peers: []                // self first, see build()
    property string sig: ""               // last list as JSON; the model is only replaced when this changes
    property string expanded: ""          // id of the expanded row
    property string copied: ""            // key of the value just copied (brief "Copied" feedback)

    property string acting: ""            // "up" | "down" | "exit" while a command runs
    property bool needOperator: false     // last command was refused: user is not the tailscale operator
    property string error: ""

    readonly property bool running: backend === "Running"
    readonly property bool starting: backend === "Starting" || acting === "up"
    readonly property bool switching: VpnSwitch.switching("tailscale")     // a Tailscale <-> Mullvad switch runs
    readonly property bool canToggle: loaded && !daemonDown && (backend === "Running" || backend === "Starting" || backend === "Stopped")
    readonly property int onlineCount: peers.filter(p => p.online).length

    // ---- polling -------------------------------------------------------------------------------------------
    function refresh() { if (!statusProc.running) statusProc.running = true }
    Component.onCompleted: { refresh(); VpnSwitch.checkMode() }
    Timer { interval: ts.acting !== "" || ts.switching || ts.backend === "Starting" ? 1000 : 4000; running: true; repeat: true; onTriggered: ts.refresh() }

    Process {
        id: statusProc
        command: [ts.bin, "status", "--json"]
        stdout: StdioCollector { id: statusOut }
        stderr: StdioCollector { id: statusErr }
        onExited: (code, status) => Qt.callLater(() => ts.parseStatus(code, statusOut.text, statusErr.text))
    }

    function parseStatus(code, out, err) {
        let d = null
        try { d = JSON.parse(out) } catch (e) { d = null }
        loaded = true
        if (!d || typeof d !== "object") {
            daemonDown = true
            backend = ""
            setPeers([])
            return
        }
        daemonDown = false
        backend = String(d.BackendState || "")
        tailnet = d.CurrentTailnet && d.CurrentTailnet.Name ? String(d.CurrentTailnet.Name) : ""
        setPeers(backend === "Running" ? build(d) : [])
    }

    function setPeers(list) {
        const s = JSON.stringify(list)
        if (s !== sig) { sig = s; peers = list }
    }

    function build(d) { return Vpn.tsPeers(d) }

    // ---- actions -------------------------------------------------------------------------------------------
    function run(kind, args) {
        if (actProc.running) return
        error = ""
        needOperator = false
        acting = kind
        actProc.command = [bin].concat(args)
        actProc.running = true
        actTimeout.restart()
    }
    // on = VpnSwitch (bin/vpn-switch: takes Mullvad down first unless both may run); off = plain `tailscale down`
    function setUp(want) {
        if (!want) { run("down", ["down"]); return }
        if (actProc.running || VpnSwitch.busy) return
        error = ""
        needOperator = false
        if (VpnSwitch.run("tailscale")) acting = "up"
    }
    Connections {
        target: VpnSwitch
        function onFinished(t, code, text) {
            if (t === "tailscale") ts.actionDone(code, text)
            else ts.refresh()
        }
    }
    function useExit(p) { run("exit", ["set", "--exit-node=" + (p ? p.ipv4 : "")]) }

    Process {
        id: actProc
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: (code, status) => Qt.callLater(() => ts.actionDone(code, actErr.text + "\n" + actOut.text))
    }
    // `tailscale up` blocks while it waits for a login; never let the switch pulse forever
    Timer { id: actTimeout; interval: 25000; onTriggered: if (actProc.running) { actProc.running = false; ts.error = "Timed out waiting for tailscale" } }

    function actionDone(code, text) {
        actTimeout.stop()
        acting = ""
        if (code !== 0) {
            if (/access denied|operator/i.test(text)) needOperator = true
            else if (error === "") error = firstLine(text) || ("tailscale exited with code " + code)
        }
        refresh()
    }
    // first meaningful line of an error, with any URL (login links) left out
    function firstLine(t) {
        const l = String(t).split("\n").map(s => s.trim()).filter(s => s !== "")[0] || ""
        return l.replace(/https?:\/\/\S+/g, "<link>").slice(0, 160)
    }

    function copy(key, value) {
        if (!value) return
        Quickshell.execDetached(["wl-copy", "--", value])
        copied = key
        copiedTimer.restart()
    }
    Timer { id: copiedTimer; interval: 1200; onTriggered: ts.copied = "" }

    // ---- helpers -------------------------------------------------------------------------------------------
    function osGlyph(os) {
        const o = os.toLowerCase()
        return o === "linux" ? Icons.linux : o === "ios" || o === "macos" || o === "tvos" ? Icons.apple
             : o === "android" ? Icons.android : o === "windows" ? Icons.windows : ""
    }
    function ago(iso) { return Vpn.ago(iso) }
    function stateLine() {
        if (!loaded) return "Checking…"
        if (daemonDown) return "tailscaled is not running"
        switch (backend) {
        case "Running": return peers.length <= 1 ? "No other machines on this tailnet" : ""
        case "Starting": return "Connecting…"
        case "Stopped": return acting === "up" ? "Connecting…" : "Disconnected"
        case "NeedsLogin": return "Logged out · run tailscale login in a terminal"
        case "NeedsMachineAuth": return "Waiting for this machine to be approved in the admin console"
        default: return backend ? "State: " + backend : "Unknown state"
        }
    }

    // one-word state for the folded head (stateLine() has the full sentence inside)
    function shortState() {
        if (!loaded) return "Checking…"
        if (daemonDown) return "Not running"
        if (backend === "Starting" || acting === "up") return "Connecting…"
        switch (backend) {
        case "Stopped": return "Disconnected"
        case "NeedsLogin": return "Logged out"
        case "NeedsMachineAuth": return "Needs approval"
        default: return backend
        }
    }
    // a failed switch click explains itself inside the fold, so unfold it
    onErrorChanged: if (error !== "") fold.open = true
    onNeedOperatorChanged: if (needOperator) fold.open = true

    // ---- UI ------------------------------------------------------------------------------------------------
    // folded by default; the head row keeps the summary and the switch (FoldSection.qml)
    FoldSection {
        id: fold
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "Tailscale"
        detail: ts.switching ? "Switching…" : ts.running ? ts.onlineCount + " / " + ts.peers.length + " online" : ts.acting === "down" ? "Disconnecting…"
              : fold.open ? "" : ts.shortState()
        trailing: Toggle {
            checked: ts.running || ts.starting
            busy: ts.acting === "up" || ts.acting === "down" || ts.switching || ts.backend === "Starting"
            enabledLook: ts.canToggle
            onToggled: want => ts.setUp(want)
        }

        Label {
            visible: text !== ""
            Layout.fillWidth: true
            text: ts.stateLine()
            color: Theme.muted
            wrapMode: Text.Wrap
        }
        Label {
            visible: ts.running && ts.tailnet !== ""
            Layout.fillWidth: true
            Layout.topMargin: -4
            text: ts.tailnet
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideRight
        }
        Label {
            visible: ts.error !== ""
            Layout.fillWidth: true
            text: ts.error
            color: Theme.red
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.Wrap
        }

        // operator hint: same box as NetPanel's confirm row
        Notice {
            visible: ts.needOperator
            danger: true
            padX: Theme.gapRow
            padY: Theme.gapRow
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Tailscale refused: this user is not its operator. Run once in a terminal:"
                font.pixelSize: Theme.fontSmall
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.controlH
                radius: Theme.inner(Theme.radiusItem, Theme.gapRow)
                color: Theme.alpha(Theme.bg, 0.6)
                Label {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
                    text: ts.copied === "operator" ? "Copied" : "sudo tailscale set --operator=$USER"
                    color: ts.copied === "operator" ? Theme.accent : Theme.fg
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }
            RowLayout {
                spacing: Theme.controlGap
                Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Dismiss"; onClicked: ts.needOperator = false }
                Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Copy command"; active: true; onClicked: ts.copy("operator", "sudo tailscale set --operator=$USER") }
            }
        }

        ListView {
            id: list
            visible: ts.running && ts.peers.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(ts.maxListH, contentHeight)
            Layout.maximumHeight: Math.min(ts.maxListH, contentHeight)
            Layout.minimumHeight: Math.min(2 * ts.rowH + ts.listGap, contentHeight)
            clip: true
            spacing: ts.listGap
            boundsBehavior: Flickable.StopAtBounds
            model: ts.peers
            delegate: ListRow {
                id: card
                required property var modelData
                required property int index
                readonly property var p: modelData
                readonly property bool open: ts.expanded === p.id
                readonly property string brand: ts.osGlyph(p.os)
                width: list.width
                rowH: ts.rowH
                icon: brand || Icons.monitor
                iconFamily: brand ? Theme.brandFont : Theme.iconFont
                iconSize: 16
                iconColor: p.online ? Theme.accent : Theme.muted
                selected: p.self
                outlined: open
                onClicked: ts.expanded = card.open ? "" : card.p.id
                // expanded details under the text column
                expanded: open
                bodyLeft: Theme.pad + Theme.iconCol + Theme.pad
                onHeightChanged: if (open) list.positionViewAtIndex(index, ListView.Contain)

                RowText {
                    title: card.p.name
                    titleColor: card.p.online ? Theme.fg : Theme.fgDim
                    sub: !card.p.online ? (card.p.lastSeen ? "Last seen " + ts.ago(card.p.lastSeen) : "Offline")
                        : [card.p.tags.map(t => t.replace(/^tag:/, "")).join(", "), card.p.exitOption && !card.p.exitNode ? "exit node available" : ""].filter(s => s).join(" · ") || card.p.os
                    Label { visible: card.p.self; text: "this device"; color: Theme.accent; font.pixelSize: Theme.fontTiny }
                    Label { visible: card.p.exitNode; text: "exit node"; color: Theme.orange; font.pixelSize: Theme.fontTiny }
                }
                // click-to-copy IPv4 (its MouseArea sits above the row's own)
                Label {
                    id: ipLabel
                    readonly property bool done: ts.copied === card.p.id + "/4"
                    text: done ? "Copied" : card.p.ipv4
                    font.pixelSize: Theme.fontSmall
                    color: done ? Theme.accent : ipArea.containsMouse ? Theme.fg : Theme.fgDim
                    MouseArea { id: ipArea; anchors.fill: parent; anchors.margins: -Theme.gapTight; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ts.copy(card.p.id + "/4", card.p.ipv4) }
                }
                StatusDot { tint: card.p.online ? Theme.green : Theme.alpha(Theme.muted, 0.6) }

                body: ColumnLayout {
                    id: details
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: [
                            { k: "MagicDNS", v: card.p.fqdn, c: "/dns" },
                            { k: "Hostname", v: card.p.host.toLowerCase() !== card.p.name.toLowerCase() ? card.p.host : "", c: "" },
                            { k: "IPv4", v: card.p.ipv4, c: "/4" },
                            { k: "IPv6", v: card.p.ipv6, c: "/6" },
                            { k: "OS", v: card.p.os, c: "" },
                            { k: "Owner", v: card.p.owner, c: "" },
                            { k: "Tags", v: card.p.tags.join(", "), c: "" },
                            { k: "Exit node", v: card.p.exitNode ? "in use" : card.p.exitOption ? "available" : "", c: "" }
                        ].filter(r => r.v)
                        RowLayout {
                            id: kv
                            required property var modelData
                            readonly property bool done: modelData.c !== "" && ts.copied === card.p.id + modelData.c
                            Layout.fillWidth: true
                            spacing: Theme.gapRow
                            Label { text: kv.modelData.k; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: ts.keyColW }
                            Label {
                                Layout.fillWidth: true
                                text: kv.done ? "Copied" : kv.modelData.v
                                color: kv.done ? Theme.accent : kv.modelData.c !== "" && valArea.containsMouse ? Theme.fg : Theme.fgDim
                                font.pixelSize: Theme.fontCaption
                                elide: Text.ElideMiddle
                                MouseArea {
                                    id: valArea
                                    anchors.fill: parent
                                    enabled: kv.modelData.c !== ""
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ts.copy(card.p.id + kv.modelData.c, kv.modelData.v)
                                }
                            }
                        }
                    }
                    RowLayout {
                        visible: !card.p.self && (card.p.exitOption || card.p.exitNode)
                        Layout.topMargin: Theme.gapTight
                        spacing: Theme.controlGap
                        Btn {
                            outerRadius: card.radius
                            text: card.p.exitNode ? "Stop using exit node" : "Use as exit node"
                            active: card.p.exitNode
                            enabledLook: ts.acting === "" && card.p.online
                            onClicked: if (enabledLook) ts.useExit(card.p.exitNode ? null : card.p)
                        }
                    }
                }
            }
        }
    }
}
