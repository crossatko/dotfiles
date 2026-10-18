import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Tailscale section of the network popup: connect/disconnect toggle + every machine on the tailnet.
// Lives only while the popup is open (the Loader drops it on close), so it polls `tailscale status --json`
// every 4 s while visible and not at all otherwise. `QS_TAILSCALE` replaces the binary (tests).
ColumnLayout {
    id: ts
    spacing: 6

    readonly property string bin: Quickshell.env("QS_TAILSCALE") ? String(Quickshell.env("QS_TAILSCALE")) : "tailscale"
    readonly property int rowH: 44
    readonly property int maxListH: 5 * rowH + 4 * 6 + 22      // ~5.5 rows, then it scrolls

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
    readonly property bool canToggle: loaded && !daemonDown && (backend === "Running" || backend === "Starting" || backend === "Stopped")
    readonly property int onlineCount: peers.filter(p => p.online).length

    // ---- polling -------------------------------------------------------------------------------------------
    function refresh() { if (!statusProc.running) statusProc.running = true }
    Component.onCompleted: refresh()
    Timer { interval: ts.acting !== "" || ts.backend === "Starting" ? 1000 : 4000; running: true; repeat: true; onTriggered: ts.refresh() }

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

    // One flat object per machine. Name = first label of DNSName (the MagicDNS machine name, renameable in the
    // admin console); host = the OS hostname the machine reports (HostName), shown when it differs.
    function build(d) {
        const users = d.User || {}
        const selfUser = d.Self ? d.Self.UserID : null
        const one = (p, isSelf) => {
            const fqdn = String(p.DNSName || "").replace(/\.$/, "")
            const host = String(p.HostName || "")
            const ips = Array.isArray(p.TailscaleIPs) ? p.TailscaleIPs : []
            const u = users[String(p.UserID)]
            const seen = String(p.LastSeen || "")
            return {
                id: String(p.ID || p.PublicKey || fqdn || host),
                name: fqdn ? fqdn.split(".")[0] : host,
                fqdn: fqdn,
                host: host,
                os: String(p.OS || ""),
                online: isSelf ? true : p.Online === true,
                lastSeen: seen.startsWith("0001-") ? "" : seen,
                ipv4: ips.find(a => a.indexOf(":") < 0) || "",
                ipv6: ips.find(a => a.indexOf(":") >= 0) || "",
                exitNode: p.ExitNode === true,
                exitOption: p.ExitNodeOption === true,
                tags: Array.isArray(p.Tags) ? p.Tags.map(String) : [],
                owner: !isSelf && selfUser !== null && p.UserID !== selfUser && u ? String(u.DisplayName || u.LoginName || "") : "",
                self: isSelf
            }
        }
        const others = Object.values(d.Peer || {}).map(p => one(p, false))
            .sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name))
        return (d.Self ? [one(d.Self, true)] : []).concat(others)
    }

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
    function setUp(want) { run(want ? "up" : "down", [want ? "up" : "down"]) }
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
        return o === "linux" ? "" : o === "ios" || o === "macos" || o === "tvos" ? ""
             : o === "android" ? "" : o === "windows" ? "" : ""
    }
    function ago(iso) {
        const t = Date.parse(iso)
        if (isNaN(t)) return ""
        const m = Math.floor((Date.now() - t) / 60000)
        if (m < 1) return "just now"
        if (m < 60) return m + " min ago"
        if (m < 1440) return Math.floor(m / 60) + " h ago"
        if (m < 43200) return Math.floor(m / 1440) + " d ago"
        return iso.slice(0, 10)
    }
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

    // ---- UI ------------------------------------------------------------------------------------------------
    SectionHead {
        title: "Tailscale"
        detail: ts.running ? ts.onlineCount + " / " + ts.peers.length + " online" : ts.acting === "down" ? "Disconnecting…" : ""
        Toggle {
            checked: ts.running || ts.starting
            busy: ts.acting === "up" || ts.acting === "down" || ts.backend === "Starting"
            enabledLook: ts.canToggle
            onToggled: want => ts.setUp(want)
        }
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
        padX: 8
        padY: 8
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Tailscale refused: this user is not its operator. Run once in a terminal:"
            font.pixelSize: Theme.fontSmall
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Theme.inner(Theme.radiusItem, 8)
            color: Theme.alpha(Theme.bg, 0.6)
            Label {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                text: ts.copied === "operator" ? "Copied" : "sudo tailscale set --operator=$USER"
                color: ts.copied === "operator" ? Theme.accent : Theme.fg
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
            }
        }
        RowLayout {
            spacing: 6
            Btn { outerRadius: Theme.radiusItem; inset: 8; text: "Dismiss"; onClicked: ts.needOperator = false }
            Btn { outerRadius: Theme.radiusItem; inset: 8; text: "Copy command"; active: true; onClicked: ts.copy("operator", "sudo tailscale set --operator=$USER") }
        }
    }

    ListView {
        id: list
        visible: ts.running && ts.peers.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(ts.maxListH, contentHeight)
        Layout.maximumHeight: Math.min(ts.maxListH, contentHeight)
        Layout.minimumHeight: Math.min(2 * ts.rowH + 6, contentHeight)
        clip: true
        spacing: 6
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
            icon: brand || "\uf390"
            iconFamily: brand ? Theme.brandFont : Theme.iconFont
            iconSize: 16
            iconColor: p.online ? Theme.accent : Theme.muted
            selected: p.self
            outlined: open
            onClicked: ts.expanded = card.open ? "" : card.p.id
            // expanded details under the text column
            expanded: open
            bodyLeft: 48
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
                MouseArea { id: ipArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ts.copy(card.p.id + "/4", card.p.ipv4) }
            }
            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: card.p.online ? Theme.green : Theme.alpha(Theme.muted, 0.6)
            }

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
                        spacing: 8
                        Label { text: kv.modelData.k; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 64 }
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
                    Layout.topMargin: 4
                    spacing: 6
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
