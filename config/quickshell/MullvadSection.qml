pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "launcher/js/Vpn.js" as Vpn

// Mullvad section of the network popup, folded like Tailscale (FoldSection): the head keeps the state summary and
// the on/off switch; unfolded = tunnel card (relay, exit IP), location picker (countries -> cities from
// `mullvad relay list`), lockdown mode and auto-connect. On / off go through VpnSwitch (bin/vpn-switch: Tailscale
// and Mullvad are mutually exclusive unless the coexist rules are installed; Mullvad off brings Tailscale back).
// Lives only while the popup is open. State: `mullvad status -j listen` streams every tunnel change (one JSON
// object per line), so no tight polling; while the daemon is down (or the listener died) a 10 s poll of
// `mullvad status -j` notices it coming back. `QS_MULLVAD` replaces the binary (tests).
// Never shows the real (non-Mullvad) location / IP of the disconnected state, and never runs `account get`.
ColumnLayout {
    id: mv
    spacing: 6

    readonly property string bin: Quickshell.env("QS_MULLVAD") ? String(Quickshell.env("QS_MULLVAD")) : "mullvad"
    readonly property int rowH: 44
    readonly property int cityH: 36
    readonly property int maxListH: 5 * cityH + 4 * 6 + 18      // ~5.5 rows, then it scrolls

    property bool loaded: false
    property bool missing: false          // no mullvad CLI on PATH
    property bool daemonDown: false
    property string tunnel: ""            // connected | connecting | disconnected | disconnecting | error
    property var loc: null                // {country, city, hostname, entry, ipv4, ipv6} of the relay (connected / connecting only)
    property bool lockedDown: false       // disconnected AND lockdown mode blocks traffic
    property string cause: ""             // error state: why
    property bool blocked: false          // error state: traffic is blocked (the firewall held)
    property var countries: []            // [{name, code, cities: [{name, code}]}]
    property string relayLoc: ""          // `relay get` Location value, e.g. "country se" / "city got, se"
    property var lockdown: undefined      // bool, undefined = unknown
    property var autoConnect: undefined
    property bool picking: false          // location list open
    property string openCountry: ""       // code of the country whose cities are shown
    property string copied: ""

    property string acting: ""            // "up" | "down" | "loc" | "lockdown" | "auto" while a command runs
    property string error: ""

    readonly property bool up: loaded && !missing && !daemonDown
    readonly property bool switching: VpnSwitch.switching("mullvad")
    readonly property bool on: tunnel === "connected" || tunnel === "connecting" || tunnel === "error"
    readonly property bool canToggle: up && tunnel !== "disconnecting"

    // ---- state ---------------------------------------------------------------------------------------------
    function refresh() { if (!statusProc.running) statusProc.running = true }
    Component.onCompleted: { refresh(); VpnSwitch.checkMode() }
    onUpChanged: if (up) { readSettings(); if (countries.length === 0) relaysProc.running = true; startListen() }
    // fallback poll: daemon down / CLI missing / listener gone (it restarts on the next successful status)
    Timer { interval: 10000; running: !listenProc.running; repeat: true; onTriggered: mv.refresh() }

    // exit 127 = no CLI (a missing binary would never report an exit at all)
    Process {
        id: statusProc
        command: ["sh", "-c", "command -v \"$0\" >/dev/null 2>&1 || exit 127; exec \"$0\" status -j", mv.bin]
        stdout: StdioCollector { id: statusOut }
        onExited: (code, status) => Qt.callLater(() => mv.parseStatus(code, statusOut.text))
    }
    function parseStatus(code, out) {
        loaded = true
        missing = code === 127
        let d = null
        try { d = JSON.parse(out) } catch (e) { d = null }
        daemonDown = !missing && !(d && typeof d === "object")
        if (daemonDown || missing) { tunnel = ""; loc = null; return }
        applyState(d)
        startListen()
    }
    function applyState(d) {
        const st = Vpn.mvState(d)
        tunnel = st.tunnel; loc = st.loc; lockedDown = st.lockedDown; cause = st.cause; blocked = st.blocked
    }

    function startListen() { if (up && !listenProc.running) listenProc.running = true }
    Process {
        id: listenProc
        command: [mv.bin, "status", "-j", "listen"]
        stdout: SplitParser {
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { d = null }
                if (d && typeof d === "object" && d.state !== undefined) mv.applyState(d)
                else mv.refresh()
            }
        }
        // daemon stopped (or restarted): find out which, the poll above takes over meanwhile
        onExited: (code, status) => Qt.callLater(() => mv.refresh())
    }

    // `relay get`, `lockdown-mode get`, `auto-connect get` in one go, "@@" between them
    function readSettings() { if (!setProc.running) setProc.running = true }
    Process {
        id: setProc
        command: ["sh", "-c", "\"$0\" relay get; echo @@; \"$0\" lockdown-mode get; echo @@; \"$0\" auto-connect get", mv.bin]
        stdout: StdioCollector { id: setOut }
        onExited: (code, status) => Qt.callLater(() => mv.parseSettings(setOut.text))
    }
    function parseSettings(text) {
        const parts = String(text).split("@@")
        relayLoc = Vpn.mvRelayLoc(parts[0] || "")
        lockdown = onOff(parts[1])
        autoConnect = onOff(parts[2])
    }
    function onOff(t) {
        const all = String(t || "").match(/\b(on|off)\b/gi)
        return all ? all[all.length - 1].toLowerCase() === "on" : undefined
    }

    Process {
        id: relaysProc
        command: [mv.bin, "relay", "list"]
        stdout: StdioCollector { id: relaysOut }
        onExited: (code, status) => Qt.callLater(() => { if (code === 0) mv.countries = mv.parseRelays(relaysOut.text) })
    }
    function parseRelays(text) { return Vpn.mvRelays(text) }

    // the selected location as codes, matched against the relay list: {cc, city}
    readonly property var chosen: Vpn.mvChosen(relayLoc, countries)
    function chosenLabel() {
        if (relayLoc === "" ) return ""
        const c = countries.find(x => x.code === chosen.cc)
        if (!c) return /^any$/i.test(relayLoc) ? "Any location" : relayLoc
        const ci = c.cities.find(x => x.code === chosen.city)
        return ci ? ci.name + ", " + c.name : c.name
    }

    // ---- actions -------------------------------------------------------------------------------------------
    function run(kind, args) {
        if (actProc.running) return
        error = ""
        acting = kind
        actProc.command = [bin].concat(args)
        actProc.running = true
        actTimeout.restart()
    }
    // on / off = VpnSwitch (bin/vpn-switch: `tailscale down` first / `tailscale up` after, unless both may run)
    function setOn(want) {
        if (actProc.running || VpnSwitch.busy) return
        error = ""
        if (VpnSwitch.run(want ? "mullvad" : "mullvad-off")) acting = want ? "up" : "down"
    }
    function setLocation(cc, city) { run("loc", ["relay", "set", "location", cc].concat(city ? [city] : [])) }
    function setLockdown(want) { run("lockdown", ["lockdown-mode", "set", want ? "on" : "off"]) }
    function setAutoConnect(want) { run("auto", ["auto-connect", "set", want ? "on" : "off"]) }

    Connections {
        target: VpnSwitch
        function onFinished(t, code, text) {
            if (t === "mullvad" || t === "mullvad-off") mv.actionDone(code, text)
            else mv.refresh()
        }
    }
    Process {
        id: actProc
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: (code, status) => Qt.callLater(() => mv.actionDone(code, actErr.text + "\n" + actOut.text))
    }
    Timer { id: actTimeout; interval: 15000; onTriggered: if (actProc.running) { actProc.running = false; mv.error = "Timed out waiting for mullvad" } }

    function actionDone(code, text) {
        actTimeout.stop()
        acting = ""
        if (code !== 0 && error === "") error = firstLine(text) || ("mullvad exited with code " + code)
        refresh()
        readSettings()
    }
    function firstLine(t) { return Vpn.mvFirstLine(t) }
    onErrorChanged: if (error !== "") fold.open = true

    function copy(key, value) {
        if (!value) return
        Quickshell.execDetached(["wl-copy", "--", value])
        copied = key
        copiedTimer.restart()
    }
    Timer { id: copiedTimer; interval: 1200; onTriggered: mv.copied = "" }

    // ---- helpers -------------------------------------------------------------------------------------------
    function describe(c) { return Vpn.mvDescribe(c) }
    function place() {
        if (!loc) return ""
        return [loc.city, loc.country].filter(s => s).join(", ")
    }
    function shortState() {
        if (!loaded) return "Checking…"
        if (missing) return "Not installed"
        if (daemonDown) return "Not running"
        if (acting === "up") return "Connecting…"
        if (acting === "down") return "Disconnecting…"
        switch (tunnel) {
        case "connected": return place() || "Connected"
        case "connecting": return "Connecting…"
        case "disconnecting": return "Disconnecting…"
        case "disconnected": return lockedDown ? "Blocked" : "Disconnected"
        case "error": return blocked ? "Error · blocked" : "Error"
        default: return tunnel || "Unknown state"
        }
    }
    function stateTitle() {
        switch (tunnel) {
        case "connected": return "Connected"
        case "connecting": return "Connecting…"
        case "disconnecting": return "Disconnecting…"
        case "disconnected": return lockedDown ? "Disconnected · traffic blocked" : "Disconnected"
        case "error": return blocked ? "Error · traffic blocked" : "Error · not blocked"
        default: return tunnel
        }
    }

    // ---- UI ------------------------------------------------------------------------------------------------
    FoldSection {
        id: fold
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "Mullvad"
        detail: mv.switching ? "Switching…" : mv.shortState()
        trailing: Toggle {
            checked: mv.on
            busy: mv.acting === "up" || mv.acting === "down" || mv.switching || mv.tunnel === "disconnecting"
            enabledLook: mv.canToggle
            onToggled: want => mv.setOn(want)
        }

        Label {
            visible: mv.missing
            Layout.fillWidth: true
            text: "The mullvad CLI is not installed (Mullvad VPN app)."
            color: Theme.muted
            wrapMode: Text.Wrap
        }

        // daemon down: same box as Tailscale's operator hint
        Notice {
            visible: mv.loaded && mv.daemonDown
            padX: 8
            padY: 8
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "mullvad-daemon is not running. Start it (and at boot) once in a terminal:"
                font.pixelSize: Theme.fontSmall
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Theme.inner(Theme.radiusItem, 8)
                color: Theme.alpha(Theme.bg, 0.6)
                Label {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                    text: mv.copied === "daemon" ? "Copied" : "sudo systemctl enable --now mullvad-daemon"
                    color: mv.copied === "daemon" ? Theme.accent : Theme.fg
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }
            RowLayout {
                spacing: Theme.controlGap
                Btn { outerRadius: Theme.radiusItem; inset: 8; text: "Copy command"; active: true; onClicked: mv.copy("daemon", "sudo systemctl enable --now mullvad-daemon") }
            }
        }

        // the tunnel: state, relay, exit IP (click to copy)
        ListRow {
            visible: mv.up
            Layout.fillWidth: true
            rowH: mv.rowH
            interactive: false
            icon: "\uf3ed"
            iconColor: mv.tunnel === "connected" ? Theme.accent : mv.tunnel === "error" || mv.lockedDown ? Theme.orange : Theme.muted
            selected: mv.tunnel === "connected"
            RowText {
                title: mv.stateTitle()
                sub: mv.tunnel === "error" ? mv.cause
                   : mv.loc ? [mv.place(), mv.loc.entry ? mv.loc.entry + " → " + mv.loc.hostname : mv.loc.hostname].filter(s => s).join(" · ")
                   : mv.chosenLabel() ? "Location: " + mv.chosenLabel() : ""
            }
            Label {
                id: ipLabel
                visible: mv.tunnel === "connected" && !!mv.loc && mv.loc.ipv4 !== ""
                readonly property bool done: mv.copied === "ip"
                text: done ? "Copied" : mv.loc ? mv.loc.ipv4 : ""
                font.pixelSize: Theme.fontSmall
                color: done ? Theme.accent : ipArea.containsMouse ? Theme.fg : Theme.fgDim
                MouseArea { id: ipArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.copy("ip", mv.loc.ipv4) }
            }
        }

        Label {
            visible: mv.error !== ""
            Layout.fillWidth: true
            text: mv.error
            color: Theme.red
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.Wrap
        }
        Label {
            visible: mv.up && mv.tunnel === "error" && /account|auth|logged|key|device/i.test(mv.cause)
            Layout.fillWidth: true
            text: "Not logged in? Run mullvad account login in a terminal."
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.Wrap
        }

        // location: the row opens the country list
        ListRow {
            visible: mv.up
            Layout.fillWidth: true
            rowH: 36
            icon: "\uf0ac"
            iconSize: 15
            iconColor: Theme.fgDim
            outlined: mv.picking
            onClicked: { mv.picking = !mv.picking; if (mv.picking && mv.countries.length === 0) relaysProc.running = true }
            RowText { title: "Location"; titleColor: Theme.fgDim }
            Label { text: mv.chosenLabel() || "…"; color: Theme.fg; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 200 }
            Icon {
                text: "\uf078"
                font.pixelSize: 11
                color: Theme.fgDim
                rotation: mv.picking ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Easing.OutCubic } }
            }
        }

        // countries; a click shows its cities ("Any city" = the whole country)
        ListView {
            id: list
            visible: mv.up && mv.picking
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(mv.maxListH, contentHeight)
            Layout.maximumHeight: Math.min(mv.maxListH, contentHeight)
            Layout.minimumHeight: Math.min(2 * mv.cityH + 6, contentHeight)
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: mv.countries
            delegate: ListRow {
                id: card
                required property var modelData
                required property int index
                readonly property var c: modelData
                readonly property bool open: mv.openCountry === c.code
                readonly property bool current: mv.chosen.cc === c.code
                width: list.width
                rowH: mv.cityH
                selected: current
                outlined: open
                onClicked: mv.openCountry = card.open ? "" : card.c.code
                expanded: open
                bodyGap: 10
                onHeightChanged: if (open) list.positionViewAtIndex(index, ListView.Contain)

                RowText {
                    title: card.c.name
                    titleColor: card.current ? Theme.accent : Theme.fg
                }
                Label { text: card.c.cities.length + (card.c.cities.length === 1 ? " city" : " cities"); color: Theme.muted; font.pixelSize: Theme.fontCaption }

                body: Flow {
                    Layout.fillWidth: true
                    spacing: Theme.controlGap
                    Btn {
                        outerRadius: card.radius
                        text: "Any city"
                        active: card.current && mv.chosen.city === ""
                        enabledLook: mv.acting === ""
                        onClicked: if (enabledLook) mv.setLocation(card.c.code, "")
                    }
                    Repeater {
                        model: card.c.cities
                        Btn {
                            required property var modelData
                            outerRadius: card.radius
                            text: modelData.name
                            active: card.current && mv.chosen.city === modelData.code
                            enabledLook: mv.acting === ""
                            onClicked: if (enabledLook) mv.setLocation(card.c.code, modelData.code)
                        }
                    }
                }
            }
        }

        // daemon settings; switches as in the section heads
        Repeater {
            model: [
                { k: "lockdown", t: "Lockdown mode", s: "Block all traffic while Mullvad is off" },
                { k: "auto", t: "Auto-connect", s: "Connect when the daemon starts" }
            ]
            RowLayout {
                id: opt
                required property var modelData
                readonly property var val: modelData.k === "lockdown" ? mv.lockdown : mv.autoConnect
                visible: mv.up && val !== undefined
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                spacing: 10
                RowText { title: opt.modelData.t; sub: opt.modelData.s; titleColor: Theme.fgDim }
                Toggle {
                    checked: opt.val === true
                    busy: mv.acting === opt.modelData.k
                    enabledLook: mv.acting === ""
                    onToggled: want => opt.modelData.k === "lockdown" ? mv.setLockdown(want) : mv.setAutoConnect(want)
                }
            }
        }
    }
}
