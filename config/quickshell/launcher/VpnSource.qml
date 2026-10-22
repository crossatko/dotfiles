import QtQuick
import Quickshell
import Quickshell.Io
import "js/Vpn.js" as Vpn

// Source: the launcher "tailscale" and "mullvad" sections (root rows live in SectionsSource, which delegates rows /
// headerSub / enter here). Same CLIs and the same parsing as the network popup (js/Vpn.js); on / off for Tailscale
// (on) and Mullvad go through VpnSwitch (bin/vpn-switch), Tailscale off is plain `tailscale down`.
//   tailscale: first row = state + switch (Enter), then the other machines, online first (green dot, offline dim; subtitle =
//              OS, offline: last seen). Enter copies the MagicDNS name; Ctrl+K: copy IP, copy name, ssh in kitty,
//              open http://<name>. `tailscale status --json` is polled every 4 s (1 s while a switch runs) while the section is shown.
//   mullvad:   first row = tunnel state + switch (Enter), Reconnect while on, then the countries (Enter descends to
//              "Any city" + its cities; picking one runs `mullvad relay set location <cc> [city]` and connects when
//              the tunnel is down, then the launcher closes with a toast). `mullvad status -j` polled every 2 s while shown.
// `QS_TAILSCALE` / `QS_MULLVAD` replace the binaries (tests, same as the popup). Never runs `mullvad account get`.
// Switch / copy rows act in place (Launcher: owns/activate, the launcher stays open and the row shows progress or the error);
// peers and locations close it (run()).
QtObject {
    id: src

    signal updated()

    property bool active: false                     // launcher shown
    property string section: ""                     // launcher section
    readonly property string current: active && (section === "tailscale" || section === "mullvad") ? section : ""
    readonly property var items: []                 // root rows: SectionsSource
    property var sw: null                           // the VpnSwitch singleton (set by Launcher; the root qmldir is not visible from launcher/)

    readonly property string tsBin: Quickshell.env("QS_TAILSCALE") ? String(Quickshell.env("QS_TAILSCALE")) : "tailscale"
    readonly property string mvBin: Quickshell.env("QS_MULLVAD") ? String(Quickshell.env("QS_MULLVAD")) : "mullvad"
    readonly property string daemonHint: "sudo systemctl enable --now mullvad-daemon"

    // ---- state ---------------------------------------------------------------------------------------------
    property bool tsLoaded: false
    property bool tsDown: false                     // tailscaled not running / no CLI
    property string tsBackend: ""
    property var tsPeerList: []
    property string tsAct: ""                       // "down" while `tailscale down` runs
    property string tsError: ""
    property bool tsNeedOp: false                   // the last switch was refused: this user is not the tailscale operator

    property bool mvLoaded: false
    property bool mvMissing: false
    property bool mvDown: false
    property string mvTunnel: ""
    property var mvLoc: null
    property bool mvLocked: false
    property string mvCause: ""
    property bool mvBlocked: false
    property var mvCountries: []
    property string mvRelayLoc: ""
    property string mvAct: ""                       // "up" | "down" | "loc" while a command runs
    property string mvError: ""
    property string country: ""                     // non-empty = the nested city level of that country code is open
    readonly property var mvChosen: Vpn.mvChosen(mvRelayLoc, mvCountries)
    property int rev: 0                             // bumped on every visible change: headerSub() bindings depend on it

    readonly property bool tsOn: tsBackend === "Running" || tsBackend === "Starting"
    readonly property bool mvOn: mvTunnel === "connected" || mvTunnel === "connecting" || mvTunnel === "error"

    onCurrentChanged: {
        if (current !== "mullvad") country = ""
        if (current === "") return
        tsError = ""; mvError = ""; tsNeedOp = false
        sw.checkMode()
        poll()
        if (current === "mullvad") { settingsProc.running = false; settingsProc.running = true; if (mvCountries.length === 0) relaysProc.running = true }
    }
    function enter(name) { country = ""; tsError = ""; mvError = ""; tsNeedOp = false }
    property var ticker: Timer {
        interval: src.tsAct !== "" || src.mvAct !== "" || sw.busy || src.tsBackend === "Starting" ? 1000 : src.current === "mullvad" ? 2000 : 4000
        repeat: true
        running: src.current !== ""
        onTriggered: src.poll()
    }
    function poll() {
        if (current === "tailscale" && !tsProc.running) tsProc.running = true
        else if (current === "mullvad" && !mvProc.running) mvProc.running = true
    }

    // ---- tailscale ---------------------------------------------------------------------------------------
    property var tsProc: Process {
        command: [src.tsBin, "status", "--json"]
        stdout: StdioCollector { id: tsOut }
        onExited: (code, status) => Qt.callLater(() => src.tsParse(tsOut.text))
    }
    function tsParse(text) {
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        tsLoaded = true
        if (!d || typeof d !== "object") { tsDown = true; tsBackend = ""; tsPeerList = [] }
        else {
            tsDown = false
            tsBackend = String(d.BackendState || "")
            tsPeerList = tsBackend === "Running" ? Vpn.tsPeers(d).filter(p => !p.self) : []
        }
        changed()
    }
    // a signature of everything the rows show: updated() only when it differs (the launcher keeps its selection otherwise)
    property string sig: ""
    function changed() {
        const s = JSON.stringify([rows("tailscale"), rows("mullvad"), country])
        if (s !== sig) { sig = s; rev++; updated() }
    }

    function osText(os) {
        const o = os.toLowerCase()
        return o === "macos" ? "macOS" : o === "ios" ? "iOS" : o === "tvos" ? "tvOS" : o === "" ? "" : o.charAt(0).toUpperCase() + o.slice(1)
    }
    function peerRow(p) {
        const sub = [osText(p.os)]
        if (!p.online) sub.push(p.lastSeen ? "last seen " + Vpn.ago(p.lastSeen) : "offline")
        else if (p.exitNode) sub.push("exit node")
        const target = p.fqdn || p.ipv4
        return { id: "vpn:ts:peer:" + p.id, name: p.name, subtitle: sub.filter(s => s).join("  ·  "), kind: "vpn-peer",
                 source: p.online ? "Online" : "", glyph: "", iconColor: p.online ? "green" : "muted", transient: true, private: true,
                 runLabel: "Copy name", keywords: [p.host, p.ipv4, p.owner].concat(p.tags).filter(s => s), fqdn: p.fqdn, ipv4: p.ipv4, target: target,
                 actions: [{ id: "vpn-copy-ip", label: "Copy IP", glyph: "" },
                           { id: "vpn-copy-name", label: "Copy name", glyph: "" },
                           { id: "vpn-ssh", label: "SSH in terminal", glyph: "" },
                           { id: "vpn-web", label: "Open in browser", glyph: "" }] }
    }
    function info(id, name, sub, glyph, color) {
        return { id: "vpn:info:" + id, name: name, subtitle: sub || "", kind: "info", source: "", glyph: glyph || "", iconColor: color || "muted",
                 transient: true, private: true }
    }
    function copyRow(id, name, text) {
        return { id: "vpn:copy:" + id, name: name, subtitle: "Enter copies  " + text, kind: "vpn-copy", source: "", glyph: "", iconColor: "muted",
                 transient: true, private: true, text: text, runLabel: "Copy command" }
    }
    function tsRows() {
        if (!tsLoaded) return [info("ts-load", "Checking Tailscale...", "")]
        if (tsDown) return [copyRow("ts-daemon", "tailscaled is not running", "sudo systemctl enable --now tailscaled")]
        const rowsOut = []
        const switching = sw.switching("tailscale") || tsAct === "up" || tsAct === "down"
        const online = tsPeerList.filter(p => p.online).length
        if (tsBackend === "NeedsLogin") return [info("ts-login", "Logged out", "Run tailscale login in a terminal", "")]
        if (tsBackend === "NeedsMachineAuth") return [info("ts-auth", "Needs approval", "Waiting for this machine to be approved in the admin console", "")]
        if (tsBackend !== "Running" && tsBackend !== "Starting" && tsBackend !== "Stopped") return [info("ts-state", "State: " + (tsBackend || "unknown"), "")]
        const on = tsOn
        const name = switching ? (tsAct === "down" ? "Disconnecting..." : "Connecting...") : tsBackend === "Starting" ? "Connecting..." : on ? "Connected" : "Disconnected"
        rowsOut.push({ id: "vpn:ts:toggle", name: name, subtitle: tsError !== "" ? tsError : (on ? "Enter turns Tailscale off" : "Enter turns Tailscale on") + (on && tsBackend === "Running" ? "  ·  " + online + " of " + tsPeerList.length + " online" : ""),
                       kind: switching || tsBackend === "Starting" ? "info" : "vpn-ts-toggle", source: on ? "On" : "Off", glyph: "",
                       iconColor: tsError !== "" ? "red" : on ? "green" : "muted", transient: true, private: true, want: !on, runLabel: on ? "Turn off" : "Turn on",
                       keywords: ["tailscale", "vpn", "switch", "toggle", "on", "off"] })
        if (tsNeedOp) rowsOut.push(copyRow("ts-operator", "Tailscale refused: this user is not its operator", "sudo tailscale set --operator=$USER"))
        if (tsBackend === "Running") {
            if (tsPeerList.length === 0) rowsOut.push(info("ts-none", "No other machines on this tailnet", ""))
            for (const p of tsPeerList) rowsOut.push(peerRow(p))
        }
        return rowsOut
    }

    // ---- mullvad -----------------------------------------------------------------------------------------
    property var mvProc: Process {
        command: ["sh", "-c", "command -v \"$0\" >/dev/null 2>&1 || exit 127; exec \"$0\" status -j", src.mvBin]
        stdout: StdioCollector { id: mvOut }
        onExited: (code, status) => Qt.callLater(() => src.mvParse(code, mvOut.text))
    }
    function mvParse(code, text) {
        mvLoaded = true
        mvMissing = code === 127
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        mvDown = !mvMissing && !(d && typeof d === "object")
        if (mvDown || mvMissing) { mvTunnel = ""; mvLoc = null }
        else {
            const st = Vpn.mvState(d)
            mvTunnel = st.tunnel; mvLoc = st.loc; mvLocked = st.lockedDown; mvCause = st.cause; mvBlocked = st.blocked
        }
        changed()
    }
    property var settingsProc: Process {
        command: [src.mvBin, "relay", "get"]
        stdout: StdioCollector { id: setOut }
        onExited: (code, status) => Qt.callLater(() => { src.mvRelayLoc = Vpn.mvRelayLoc(setOut.text); src.changed() })
    }
    property var relaysProc: Process {
        command: [src.mvBin, "relay", "list"]
        stdout: StdioCollector { id: relOut }
        onExited: (code, status) => Qt.callLater(() => { if (code === 0) { src.mvCountries = Vpn.mvRelays(relOut.text); src.changed() } })
    }

    function mvPlace() { return mvLoc ? [mvLoc.city, mvLoc.country].filter(s => s).join(", ") : "" }
    function mvToggleName() {
        if (mvAct === "up" || (sw.switching("mullvad") && sw.target === "mullvad")) return "Connecting..."
        if (mvAct === "down" || sw.switching("mullvad")) return "Disconnecting..."
        switch (mvTunnel) {
        case "connected": return "Connected" + (mvPlace() ? "  ·  " + mvPlace() : "")
        case "connecting": return "Connecting..." + (mvPlace() ? "  ·  " + mvPlace() : "")
        case "disconnecting": return "Disconnecting..."
        case "disconnected": return mvLocked ? "Disconnected  ·  traffic blocked" : "Disconnected"
        case "error": return /^Account problem/.test(mvCause) ? "Not logged in" : mvBlocked ? "Error  ·  traffic blocked" : "Error"
        default: return mvTunnel || "Unknown state"
        }
    }
    function mvRows() {
        if (!mvLoaded) return [info("mv-load", "Checking Mullvad...", "")]
        if (mvMissing) return [info("mv-missing", "Mullvad is not installed", "")]
        if (mvDown) return [copyRow("mv-daemon", "Mullvad daemon is not running", daemonHint)]
        const out = []
        const busy = mvAct !== "" || sw.switching("mullvad") || mvTunnel === "disconnecting"
        const on = mvOn
        const bad = mvError !== "" || mvTunnel === "error"
        out.push({ id: "vpn:mv:toggle", name: mvToggleName(), subtitle: mvError !== "" ? mvError : mvTunnel === "error" ? mvCause : on ? "Enter disconnects" : "Enter connects",
                   kind: busy ? "info" : "vpn-mv-toggle", source: on ? "On" : "Off", glyph: "", iconColor: bad ? "red" : on ? "green" : "muted",
                   transient: true, private: true, want: !on, runLabel: on ? "Disconnect" : "Connect", keywords: ["mullvad", "vpn", "switch", "toggle", "on", "off"] })
        if (country === "") {
            if (on) out.push({ id: "vpn:mv:reconnect", name: "Reconnect", subtitle: "Get a new connection to the same location", kind: "vpn-mv-reconnect", source: "",
                               glyph: "", iconColor: "", transient: true, private: true, keywords: ["mullvad", "reconnect", "reset", "restart"] })
            for (const c of mvCountries)
                out.push({ id: "vpn:mv:cc:" + c.code, name: c.name, subtitle: c.cities.length + (c.cities.length === 1 ? " city" : " cities"), kind: "vpn-country", cc: c.code,
                           source: mvChosen.cc === c.code ? "Selected" : "", glyph: "", iconColor: mvChosen.cc === c.code ? "" : "muted", transient: true, private: true,
                           runLabel: "Choose city", keywords: [c.code].concat(c.cities.map(x => x.name)) })
            if (mvCountries.length === 0) out.push(info("mv-relays", "Loading locations...", ""))
            return out
        }
        // nested level: only the cities of one country
        const c = mvCountries.find(x => x.code === country)
        if (!c) return [info("mv-gone", "Country not found", "")]
        const list = []
        const here = mvChosen.cc === c.code
        list.push({ id: "vpn:mv:any:" + c.code, name: "Any city", subtitle: c.name, kind: "vpn-city", cc: c.code, city: "", label: c.name,
                   source: here && mvChosen.city === "" ? "Selected" : "", glyph: "", iconColor: here && mvChosen.city === "" ? "" : "muted", transient: true, private: true })
        for (const x of c.cities)
            list.push({ id: "vpn:mv:city:" + c.code + ":" + x.code, name: x.name, subtitle: c.name, kind: "vpn-city", cc: c.code, city: x.code, label: x.name + ", " + c.name,
                       source: here && mvChosen.city === x.code ? "Selected" : "", glyph: "", iconColor: here && mvChosen.city === x.code ? "" : "muted", transient: true, private: true })
        return list
    }

    // ---- rows (SectionsSource delegates) -----------------------------------------------------------------
    function rows(name) { return name === "tailscale" ? tsRows() : name === "mullvad" ? mvRows() : [] }
    function headerSub(name) {
        void rev
        if (name === "mullvad") {
            if (country === "") return ""
            const c = mvCountries.find(x => x.code === country)
            return c ? "Choose a city" : ""
        }
        if (name === "tailscale" && tsLoaded && tsBackend === "Running") return tsPeerList.filter(p => p.online).length + " online"
        return ""
    }
    function countryName() { const c = mvCountries.find(x => x.code === country); return c ? c.name : "" }
    function enterCountry(cc) { country = cc; changed() }
    function leaveCountry() { country = ""; changed() }

    // ---- switch / actions --------------------------------------------------------------------------------
    function owns(item) { return !!item && /^vpn-(ts|mv)-/.test(item.kind || "") }
    // Enter on a switch / Reconnect row (the launcher stays open and the row shows progress or the error)
    function activate(item, arg) {
        if (sw.busy || tsAct !== "" || mvAct !== "") return true
        if (item.kind === "vpn-ts-toggle") {
            tsError = ""; tsNeedOp = false
            if (item.want) { if (sw.run("tailscale")) tsAct = "up" }
            else { tsAct = "down"; downProc.running = true }
        } else if (item.kind === "vpn-mv-toggle") {
            mvError = ""
            if (sw.run(item.want ? "mullvad" : "mullvad-off")) mvAct = item.want ? "up" : "down"
        } else if (item.kind === "vpn-mv-reconnect") {
            mvError = ""; mvAct = "up"; reconnectProc.running = true
        }
        changed()
        return true
    }
    property var downProc: Process {
        command: [src.tsBin, "down"]
        stdout: StdioCollector { id: downOut }
        stderr: StdioCollector { id: downErr }
        onExited: (code, status) => Qt.callLater(() => {
            src.tsAct = ""
            if (code !== 0) src.tsFailed(downErr.text + "\n" + downOut.text, code)
            src.poll(); src.changed()
        })
    }
    // operator refusal = the copy row with the one-time fix (same hint as the popup), anything else = the toggle row subtitle
    function tsFailed(text, code) {
        if (/access denied|operator/i.test(text)) tsNeedOp = true
        else tsError = Vpn.mvFirstLine(text) || ("tailscale exited with code " + code)
    }
    property var reconnectProc: Process {
        command: [src.mvBin, "reconnect"]
        stderr: StdioCollector { id: rcErr }
        onExited: (code, status) => Qt.callLater(() => {
            src.mvAct = ""
            if (code !== 0) src.mvError = Vpn.mvFirstLine(rcErr.text) || ("mullvad exited with code " + code)
            src.poll(); src.changed()
        })
    }
    property var connections: Connections {
        target: src.sw
        function onFinished(t, code, text) {
            const ts = t === "tailscale"
            if (ts) src.tsAct = ""; else src.mvAct = ""
            if (code !== 0) { if (ts) src.tsFailed(text, code); else src.mvError = Vpn.mvFirstLine(text) || ("exit code " + code) }
            src.poll(); src.changed()
        }
    }

    // a picked location: set it, then connect when the tunnel is not up (VpnSwitch); the daemon reconnects by itself while connected
    property string locLabel: ""
    property bool locConnect: false
    function setLocation(item) {
        if (locProc.running || !/^[a-z]{2}$/.test(item.cc || "") || !/^([a-z]{3})?$/.test(item.city || "")) return
        locLabel = item.label; locConnect = !mvOn; mvAct = "loc"
        locProc.command = [mvBin, "relay", "set", "location", item.cc].concat(item.city ? [item.city] : [])
        locProc.running = true
    }
    property var locProc: Process {
        stderr: StdioCollector { id: locErr }
        onExited: (code, status) => Qt.callLater(() => {
            src.mvAct = ""
            if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Launcher", "Mullvad", "Could not set the location: " + (Vpn.mvFirstLine(locErr.text) || "exit code " + code)])
                return
            }
            Quickshell.execDetached(["notify-send", "-a", "Launcher", "Mullvad", "Location: " + src.locLabel + (src.locConnect ? " (connecting)" : "")])
            if (src.locConnect && !sw.busy) sw.run("mullvad")
            src.settingsProc.running = true
        })
    }

    function copy(text, what) {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy; notify-send -a Launcher \"$2\" \"$1\"", "sh", text, what])
    }
    function hostOk(h) { return /^[A-Za-z0-9][A-Za-z0-9.:-]*$/.test(h || "") }

    // run (closes the launcher): peer = copy its MagicDNS name (else IP), location = set + connect, copy rows
    function run(item) {
        if (item.kind === "vpn-peer") { if (item.target) copy(item.target, "Copied name"); return true }
        if (item.kind === "vpn-copy") { copy(item.text, "Copied"); return true }
        if (item.kind === "vpn-city") { setLocation(item); return true }
        return false
    }
    // item actions (Launcher.doAction): true = done and close, false = not ours
    function action(id, item) {
        if (item.kind !== "vpn-peer") return false
        if (id === "vpn-copy-ip") { if (item.ipv4) copy(item.ipv4, "Copied IP"); return true }
        if (id === "vpn-copy-name") { if (item.target) copy(item.target, "Copied name"); return true }
        if (!hostOk(item.target)) return false
        if (id === "vpn-ssh") { Quickshell.execDetached(["kitty", "--title", "ssh " + item.target, "ssh", item.target]); return true }
        if (id === "vpn-web") { Quickshell.execDetached(["xdg-open", "http://" + item.target]); return true }
        return false
    }
}
