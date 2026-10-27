import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "js/NetFixture.js" as NetFixture

// Source: the launcher "network" and "bluetooth" sections (root rows live in SectionsSource, which delegates rows /
// header / enter here). Same services as NetPanel / BtPanel: Quickshell.Networking (NetworkManager over D-Bus) and
// Quickshell.Bluetooth (BlueZ over D-Bus), no nmcli / bluetoothctl processes, nothing blocks the UI.
//   network:   wired devices (Enter = connect / disconnect), Wi-Fi networks (connected, then saved, then by signal;
//              Enter on a saved or open one connects, on a new WPA/WPA2/WPA3-Personal one the launcher asks for the
//              password in its own masked search field and hands it to WifiNetwork.connectWithPsk(): D-Bus only, never
//              argv / logs / files of ours; NetworkManager stores it in its own profile), Wi-Fi on / off row.
//   bluetooth: paired + discovered devices (Enter = disconnect / connect / pair, then trust + connect), power row,
//              scan row. Discovery starts when the section opens and is stopped on leave / close (only if we started it).
// Rows are rebuilt every 700 ms while a section is shown; updated() fires only when the visible rows change.
// Progress / failure is shown on the row itself ("Connecting...", red "Could not connect"); a failed secured Wi-Fi row
// asks for the password again. Disconnects / power-off need a second Enter (Launcher confirm, see confirmText).
// Launcher.runItem calls activate(item, arg) for kinds net-* / bt-* and stays open.
// Test hook: $QS_LAUNCHER_NET_FIXTURE=<json> replaces both services by fakes (launcher/js/NetFixture.js).
QtObject {
    id: src

    signal updated()
    signal finished()                               // a connect started here succeeded: the launcher closes (Launcher: onFinished)

    property bool active: false                     // launcher shown
    property string section: ""                     // launcher section
    readonly property string current: active && (section === "network" || section === "bluetooth") ? section : ""
    readonly property var items: []                 // root rows: SectionsSource

    // ---- backends (real services, or the fixture fakes) ------------------------------------------------------
    readonly property string fixturePath: Quickshell.env("QS_LAUNCHER_NET_FIXTURE") || ""
    property var fx: null
    readonly property var nm: fx ? fx.net : Networking
    readonly property var bz: fx ? fx.bt : Bluetooth
    property var fxFile: FileView {
        path: src.fixturePath
        printErrors: false
        onLoaded: {
            try {
                src.fx = NetFixture.make(JSON.parse(text()), {
                    Wifi: DeviceType.Wifi, Wired: DeviceType.Wired,
                    Connected: ConnectionState.Connected, Connecting: ConnectionState.Connecting,
                    Disconnecting: ConnectionState.Disconnecting, Disconnected: ConnectionState.Disconnected,
                    Open: WifiSecurityType.Open, WpaPsk: WifiSecurityType.WpaPsk, Wpa2Psk: WifiSecurityType.Wpa2Psk,
                    Sae: WifiSecurityType.Sae, Wpa2Eap: WifiSecurityType.Wpa2Eap, StaticWep: WifiSecurityType.StaticWep,
                    NoSecrets: ConnectionFailReason.NoSecrets,
                    BackendNone: NetworkBackendType.None, BackendNm: NetworkBackendType.NetworkManager,
                    BtConnected: BluetoothDeviceState.Connected, BtConnecting: BluetoothDeviceState.Connecting,
                    BtDisconnecting: BluetoothDeviceState.Disconnecting, BtDisconnected: BluetoothDeviceState.Disconnected,
                    AdEnabled: BluetoothAdapterState.Enabled, AdDisabled: BluetoothAdapterState.Disabled,
                    AdEnabling: BluetoothAdapterState.Enabling, AdDisabling: BluetoothAdapterState.Disabling
                }, m => console.info("net fixture: " + m))
            } catch (e) { console.warn("net fixture: " + e) }
            src.poll()
        }
    }
    function setWifiEnabled(on) { if (fx) fx.net.setWifiEnabled(on); else Networking.wifiEnabled = on }
    function setBtEnabled(a, on) { if (fx) fx.bt.setEnabled(on); else a.enabled = on }
    function setDiscovering(a, on) {
        try { if (fx) fx.bt.setDiscovering(on); else a.discovering = on } catch (e) { console.warn("bluetooth discovery: " + e) }
    }

    // ---- enter / leave -------------------------------------------------------------------------------------
    property string scanned: ""                     // section whose scanner we switched on
    property bool btScanOwned: false                // we started BlueZ discovery (so we stop it again)
    property bool btAutoScan: false                 // start discovery once the adapter is on (cleared by "Stop scanning")
    onCurrentChanged: {
        if (scanned === "network" && current !== "network") { const w = wifiDev(); if (w) w.scannerEnabled = false; scanned = "" }
        if (current !== "bluetooth") {
            const a = bz.defaultAdapter
            if (btScanOwned && a && a.discovering) setDiscovering(a, false)
            btScanOwned = false; btAutoScan = false
        }
        if (current !== "") {
            pending = ({})
            if (current === "network") { const w = wifiDev(); if (w) { w.scannerEnabled = true; scanned = "network" } }
            if (current === "bluetooth") btAutoScan = true
            poll()
        }
    }
    property var ticker: Timer {
        interval: 700
        repeat: true
        running: src.current !== ""
        onTriggered: src.poll()
    }
    property string sig: ""
    property int rev: 0                             // bumped on every visible change: headerSub() bindings depend on it (the fixture fakes do not notify)
    property var cache: []
    property string cacheFor: ""
    function poll() {
        if (fx) fx.tick()
        if (current === "") return
        rebuild(current)
        const s = JSON.stringify(cache)
        if (s !== sig) { sig = s; rev++; updated() }
        if (succeeded.length > 0) {                 // a connect of ours went through: Bluetooth audio becomes the default output, launcher closes
            for (const id of succeeded)
                if (id.startsWith("bt:dev:") && objs[id] && audioLike(objs[id].icon)) watchSink(objs[id].address)
            succeeded = []
            finished()
        }
    }

    // ---- Bluetooth audio: make the new sink the default output ------------------------------------------------
    // Only after a connect started from the launcher. The PipeWire node appears a moment after the BlueZ connect, so it is
    // looked for every 500 ms (up to 15 s, also after the launcher closed) by its api.bluez5.address. Default = the same as
    // the Audio popup's DevicePicker (Pipewire.preferredDefaultAudioSink, i.e. wpctl set-default); playing streams are moved
    // like the launcher's Sound output section (pactl move-sink-input).
    property var succeeded: []
    property string sinkAddr: ""
    property real sinkUntil: 0
    function audioLike(icon) { return !icon || /audio|headset|headphone|earbud|speaker/.test(icon) }
    function watchSink(addr) { sinkAddr = addr; sinkUntil = Date.now() + 15000; sinkTimer.restart() }
    property var sinkTracker: PwObjectTracker { objects: src.sinkAddr !== "" && !src.fx ? Pipewire.nodes.values : [] }   // properties only fill in for bound nodes
    property var sinkTimer: Timer {
        interval: 500
        repeat: true
        onTriggered: {
            if (src.fx) src.fx.tick()
            const addr = src.sinkAddr.toLowerCase()
            if (addr === "" || Date.now() > src.sinkUntil) { if (addr !== "") console.info("launcher: no audio sink appeared for the Bluetooth device"); src.sinkAddr = ""; stop(); return }
            if (src.fx) {
                const f = src.fx.bt.sinks.find(n => n.address.toLowerCase() === addr)
                if (f) { src.fx.bt.setDefaultSink(f.name); src.sinkAddr = ""; stop() }
                return
            }
            const n = Pipewire.nodes.values.find(n => !n.isStream && n.isSink && n.properties && n.properties["media.class"] === "Audio/Sink"
                                                      && String(n.properties["api.bluez5.address"] || "").toLowerCase() === addr)
            if (!n) return
            src.sinkAddr = ""; stop()
            Pipewire.preferredDefaultAudioSink = n
            Quickshell.execDetached(["sh", "-c", "pactl list short sink-inputs | cut -f1 | while read -r i; do [ -n \"$i\" ] && pactl move-sink-input \"$i\" \"$1\"; done", "sh", n.name])
        }
    }

    // ---- rows (SectionsSource delegates) ---------------------------------------------------------------------
    function rows(name) { if (cacheFor !== name) rebuild(name); return cache }
    function headerSub(name) {
        void rev
        if (name === "network") {
            const w = wifiDev()
            return w && nm.wifiEnabled ? w.networks.values.filter(n => n.name).length + " Wi-Fi networks" : ""
        }
        const a = bz.defaultAdapter
        return a && a.enabled ? (a.discovering ? "Scanning..." : a.name || "") : ""
    }

    property var objs: ({})                         // row id -> service object (rows stay plain data)
    property var pending: ({})                      // row id -> {op, t0, saw, failed}: an action of ours still in flight / its failure
    property var hooked: []                         // Wi-Fi networks whose connectionFailed signal we listen to
    function rebuild(name) {
        objs = ({})
        cache = fixturePath !== "" && !fx ? [info("loading", "Loading test fixture...", "")] : name === "network" ? netRows() : btRows()
        cacheFor = name
    }
    function info(id, name, sub, glyph) {
        return { id: "net:info:" + id, name: name, subtitle: sub || "", kind: "info", source: "", glyph: glyph || "", iconColor: "muted",
                 transient: true, private: true }
    }
    function row(id, obj, f) {
        objs[id] = obj
        return Object.assign({ id: id, source: "", transient: true, private: true }, f)
    }
    function failText(reason) {
        return reason === ConnectionFailReason.NoSecrets ? "Wrong or missing password"
             : reason === ConnectionFailReason.WifiAuthTimeout ? "Authentication timed out"
             : reason === ConnectionFailReason.WifiNetworkLost ? "Network lost" : "Could not connect"
    }
    // a started action: progress until the object reaches the target, failure when it falls back (or after a timeout)
    function track(id, op) { pending[id] = { op: op, t0: Date.now(), saw: false, failed: "" } }
    function settle(id, done, busy, idle, limit) {
        const p = pending[id]
        if (!p || p.failed) return p
        if (done) {
            delete pending[id]
            if (p.op === "connect" || p.op === "psk") succeeded.push(id)
            return null
        }
        if (busy) p.saw = true
        else if (idle && (p.saw || Date.now() - p.t0 > limit)) p.failed = p.op === "pair" ? "Pairing failed" : "Could not connect"
        return p
    }

    // ---- network ---------------------------------------------------------------------------------------------
    function wifiDev() { return nm.devices ? nm.devices.values.find(d => d.type === DeviceType.Wifi) || null : null }
    function bars(s) { return s > 0.66 ? "\uf1eb" : s > 0.33 ? "\uf6ab" : "\uf6aa" }   // wifi, wifi-fair, wifi-weak
    readonly property var pskTypes: [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae]
    function secLabel(t) {
        return t === WifiSecurityType.Open ? "Open" : t === WifiSecurityType.Owe ? "Enhanced open" : t === WifiSecurityType.WpaPsk ? "WPA"
             : t === WifiSecurityType.Wpa2Psk ? "WPA2" : t === WifiSecurityType.Sae ? "WPA3"
             : t === WifiSecurityType.Wpa2Eap || t === WifiSecurityType.WpaEap || t === WifiSecurityType.Wpa3SuiteB192 ? "Enterprise"
             : t === WifiSecurityType.StaticWep || t === WifiSecurityType.DynamicWep ? "WEP" : "Secured"
    }
    function stateText(st) {
        return st === ConnectionState.Connected ? "Connected" : st === ConnectionState.Connecting ? "Connecting..."
             : st === ConnectionState.Disconnecting ? "Disconnecting..." : "Disconnected"
    }
    function hookFail(id, n) {
        if (hooked.indexOf(n) >= 0 || !n.connectionFailed) return
        hooked.push(n)
        n.connectionFailed.connect(reason => {
            const p = src.pending["net:wifi:" + n.name]
            if (p && !p.failed && p.op !== "disconnect") { p.failed = src.failText(reason); src.poll() }
        })
    }

    function netRows() {
        if (nm.backend === NetworkBackendType.None)
            return [info("nm", "NetworkManager is not running", "Network and Wi-Fi need NetworkManager", "\uf071")]   // triangle-exclamation
        const devs = nm.devices.values
        const wired = devs.filter(d => d.type === DeviceType.Wired)
        const w = wifiDev()
        const nets = w && nm.wifiEnabled ? w.networks.values.filter(n => n.name) : []
        const up = wired.filter(d => d.connected).length + nets.filter(n => n.connected).length
        const out = wired.map(d => wiredRow(d, up))
        if (!w) { out.push(info("nowifi", "No Wi-Fi adapter", "")); return out }
        if (!nm.wifiEnabled) { out.push(wifiPowerRow(false, up)); return out }
        nets.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength) || a.name.localeCompare(b.name))
        if (nets.length === 0) out.push(info("scan", "Scanning for Wi-Fi networks...", ""))
        for (const n of nets) out.push(wifiRow(n, up))
        out.push(wifiPowerRow(true, up, w.connected))
        return out
    }
    function lastLink(up) { return up <= 1 ? "It is your only active connection. Press Enter again to disconnect" : "Press Enter again to disconnect" }

    function wiredRow(d, up) {
        const id = "net:wired:" + d.name
        const on = d.state === ConnectionState.Connected
        const busy = d.state === ConnectionState.Connecting || d.state === ConnectionState.Disconnecting
        const pd = pending[id]
        const p = pd && pd.op === "disconnect" ? settle(id, d.state === ConnectionState.Disconnected, busy, false, 0)
                : settle(id, on, busy, d.state === ConnectionState.Disconnected, 20000)
        const parts = ["Wired"]
        if (p && p.failed) parts.push(p.failed)
        else if (!d.hasLink && !on) parts.push("Cable unplugged")
        else parts.push(p && !busy ? (p.op === "disconnect" ? "Disconnecting..." : "Connecting...") : stateText(d.state))
        if (on && d.linkSpeed > 0) parts.push(d.linkSpeed + " Mb/s")
        const can = on || (!!d.network && d.hasLink && !busy)
        return row(id, d, {
            name: d.name, subtitle: parts.join("  ·  "), kind: can ? "net-wired" : "info", glyph: "\uf796",   // ethernet
            iconColor: p && p.failed ? "red" : !on ? "muted" : "", source: on ? "Connected" : "",
            runLabel: on ? "Disconnect" : "Connect", keywords: ["wired", "ethernet", "cable", "lan"],
            confirm: on, confirmText: "Disconnect " + d.name + "?", confirmSub: lastLink(up)
        })
    }
    function wifiPowerRow(on, up, wifiUp) {
        return row("net:wifi-power", null, {
            name: on ? "Turn Wi-Fi off" : "Turn Wi-Fi on", subtitle: on ? "Wireless radio" : "Wi-Fi is off", kind: "net-wifi-power",
            glyph: on ? "\uf6ac" : "\uf1eb", keywords: ["wifi", "wi-fi", "wireless", "radio", "airplane"], want: !on,   // wifi-slash, wifi
            confirm: on && wifiUp, confirmText: "Turn Wi-Fi off?", confirmSub: lastLink(up).replace("disconnect", "turn it off")
        })
    }
    function wifiRow(n, up) {
        const id = "net:wifi:" + n.name
        hookFail(id, n)
        const pd = pending[id]
        const busy = n.stateChanging
        const p = pd && pd.op === "disconnect" ? settle(id, !n.connected && !busy, busy, false, 0)
                : settle(id, n.connected, busy, !n.connected && !busy, 25000)
        const secured = n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
        const psk = pskTypes.indexOf(n.security) >= 0
        const pct = Math.round(n.signalStrength * 100) + "%"
        const sec = secLabel(n.security)
        let sub, kind = "net-wifi", argument = "", runLabel = "Connect"
        if (n.connected && !(p && p.op === "disconnect")) { sub = ["Connected", sec, pct]; runLabel = "Disconnect" }
        else if (busy || (p && !p.failed)) sub = [n.state === ConnectionState.Disconnecting || (p && p.op === "disconnect") ? "Disconnecting..." : "Connecting..."]
        else if (p && p.failed) {
            sub = [p.failed, psk ? "Enter to type the password again" : "Enter to try again"]
            if (psk) { argument = "Password"; runLabel = "Enter password" }
        }
        else if (n.known) sub = ["Saved", sec, pct]
        else if (!secured) sub = [sec, pct]
        else if (psk) { sub = [sec, pct, "Enter asks for the password"]; argument = "Password"; runLabel = "Enter password" }
        else { sub = [sec, pct, "Set it up with nmtui first"]; kind = "info" }
        const acts = []
        if (n.known && !(n.connected && up <= 1)) acts.push({ id: "net-forget", label: "Forget network", glyph: "\uf1f8" })   // trash
        return row(id, n, {
            name: n.name, subtitle: sub.join("  ·  "), kind: kind, glyph: bars(n.signalStrength),
            iconColor: p && p.failed ? "red" : "", source: n.connected ? "Connected" : n.known ? "Saved" : "",
            keywords: ["wifi", "wi-fi", "wireless", sec.toLowerCase()], runLabel: runLabel, actions: acts,
            argument: argument, secret: argument !== "", argGlyph: argument !== "" ? "\uf023" : "", argVerb: "connect", confirm: n.connected, confirmText: "Disconnect " + n.name + "?", confirmSub: lastLink(up)   // lock
        })
    }

    // ---- bluetooth -------------------------------------------------------------------------------------------
    // BlueZ names unnamed devices after their address; that is discovery noise (same rule as BtPanel)
    function named(d) { return d.name && d.name !== "" && !/^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(d.name) }
    function devGlyph(icon) {
        const i = icon || ""
        return /headset|headphone|earbud/.test(i) ? "\uf025" : /speaker|audio-card|audio/.test(i) ? "\uf8df" : /keyboard/.test(i) ? "\uf11c"   // headphones, speaker, keyboard
             : /mouse|tablet/.test(i) ? "\uf8cc" : /gaming|joystick/.test(i) ? "\uf11b" : /phone/.test(i) ? "\uf3cd"   // computer-mouse, gamepad, mobile-screen-button
             : /computer|laptop/.test(i) ? "\uf109" : /video|display|tv/.test(i) ? "\uf26c" : /printer/.test(i) ? "\uf02f"   // laptop, tv, print
             : /camera/.test(i) ? "\uf030" : "\uf293"   // camera, bluetooth
    }
    function btRows() {
        const a = bz.defaultAdapter
        if (!a) return [info("noadapter", "No Bluetooth adapter", "")]
        const busy = a.state === BluetoothAdapterState.Enabling || a.state === BluetoothAdapterState.Disabling
        if (!a.enabled) {
            if (a.state === BluetoothAdapterState.Blocked) return [info("blocked", "Bluetooth is blocked", "Unblock it with rfkill", "\uf071")]   // triangle-exclamation
            return [row("bt:power", a, { name: busy ? "Turning Bluetooth on..." : "Turn Bluetooth on", subtitle: "Bluetooth is off", kind: busy ? "info" : "bt-power",
                                         glyph: "\uf293", want: true, keywords: ["bluetooth", "power", "on"] })]   // bluetooth
        }
        if (btAutoScan && !a.discovering && !btScanOwned) { btScanOwned = true; setDiscovering(a, true) }   // scan on entry / once powered on
        const devs = a.devices.values.filter(d => d.paired || d.connected || named(d))
        devs.sort((x, y) => (y.connected - x.connected) || (y.paired - x.paired) || (x.name || "").localeCompare(y.name || ""))
        const out = devs.map(d => devRow(d))
        const anyOn = devs.some(d => d.connected)
        if (devs.length === 0) out.push(info("empty", a.discovering ? "Looking for devices..." : "No devices", a.discovering ? "Put the device in pairing mode" : ""))
        out.push(row("bt:scan", a, { name: a.discovering ? "Stop scanning" : "Scan for devices", subtitle: a.discovering ? "Discovering nearby devices" : "Find new devices to pair",
                                     kind: "bt-scan", glyph: a.discovering ? "\uf04d" : "\uf002", want: !a.discovering, keywords: ["scan", "discover", "pair"] }))   // stop, magnifying-glass
        out.push(row("bt:power", a, { name: busy ? "Turning Bluetooth off..." : "Turn Bluetooth off", subtitle: "Bluetooth radio", kind: busy ? "info" : "bt-power",
                                      glyph: "\uf293", want: false, keywords: ["bluetooth", "power", "off"],   // bluetooth
                                      confirm: anyOn, confirmText: "Turn Bluetooth off?", confirmSub: "Connected devices will disconnect. Press Enter again" }))
        return out
    }
    function devRow(d) {
        const id = "bt:dev:" + d.address
        const connecting = d.state === BluetoothDeviceState.Connecting, disconnecting = d.state === BluetoothDeviceState.Disconnecting
        const pp = pending[id]
        if (pp && pp.op === "pair" && !pp.failed && d.paired) {        // paired: trust it (reconnects on its own later) and connect
            try { if (!d.trusted) d.trusted = true } catch (e) {}
            d.connect()
            track(id, "connect")
        }
        const pd = pending[id]
        const p = pd && pd.op === "pair" ? settle(id, false, d.pairing, !d.pairing, 30000)
                : pd && pd.op === "disconnect" ? settle(id, !d.connected, disconnecting, false, 0)
                : settle(id, d.connected, connecting, !d.connected && !connecting, 20000)
        const parts = []
        if (p && p.failed) parts.push(p.failed, "Enter to try again")
        else if (d.pairing || (p && p.op === "pair")) parts.push("Pairing...")
        else if (connecting || (p && p.op === "connect")) parts.push("Connecting...")
        else if (disconnecting || (p && p.op === "disconnect")) parts.push("Disconnecting...")
        else if (d.connected) parts.push("Connected")
        else parts.push(d.paired ? "Paired" : "Not paired  ·  Enter pairs and connects")
        if (d.batteryAvailable && (d.connected || d.paired)) parts.push("Battery " + Math.round(d.battery * 100) + "%")
        const acts = []
        if (d.paired) acts.push({ id: "bt-forget", label: "Forget device", glyph: "\uf1f8" })   // trash
        return row(id, d, {
            name: d.name || d.address, subtitle: parts.join("  ·  "), kind: "bt-dev", glyph: devGlyph(d.icon),
            iconColor: p && p.failed ? "red" : !d.connected && !d.paired ? "muted" : "",
            source: d.connected ? "Connected" : d.paired ? "Paired" : "", keywords: ["bluetooth", d.icon || ""],
            runLabel: d.connected ? "Disconnect" : d.paired ? "Connect" : "Pair and connect", actions: acts,
            confirm: d.connected, confirmText: "Disconnect " + (d.name || d.address) + "?", confirmSub: "Press Enter again to disconnect"
        })
    }

    // ---- actions ---------------------------------------------------------------------------------------------
    function owns(item) { return !!item && /^(net|bt)-/.test(item.kind || "") }
    // Enter on a row (the launcher stays open). arg = the typed password for a row with `argument`.
    // Returns a footer note when a password is too short / long for WPA (the prompt stays), else true.
    function activate(item, arg) {
        if (item.kind === "net-wifi-power") { setWifiEnabled(item.want); return true }
        const o = objs[item.id]
        if (!o) return true
        if (item.kind === "net-wired") {
            if (o.state === ConnectionState.Connected) { track(item.id, "disconnect"); o.disconnect() }
            else if (o.network) { track(item.id, "connect"); o.network.connect() }
        } else if (item.kind === "net-wifi") {
            if (o.connected) { track(item.id, "disconnect"); o.disconnect() }
            else if (arg !== undefined) {
                if (arg.length < 8 || arg.length > 63) return "A Wi-Fi password has 8 to 63 characters"
                track(item.id, "psk"); o.connectWithPsk(arg)
            } else { track(item.id, "connect"); o.connect() }
        } else if (item.kind === "bt-power") setBtEnabled(o, item.want)
        else if (item.kind === "bt-scan") {
            if (item.want) { btScanOwned = true; btAutoScan = true } else btAutoScan = false
            setDiscovering(o, item.want)
        } else if (item.kind === "bt-dev") {
            if (o.connected) { track(item.id, "disconnect"); o.disconnect() }
            else if (o.paired) { track(item.id, "connect"); o.connect() }
            else { track(item.id, "pair"); o.pair() }
        }
        poll()
        return true
    }
    // Ctrl+K item actions (Launcher.doAction): "keep" = the launcher stays open and redraws
    function action(id, item) {
        if (id !== "net-forget" && id !== "bt-forget") return false
        const o = objs[item.id]
        if (o) { delete pending[item.id]; o.forget() }
        poll()
        return "keep"
    }
}
