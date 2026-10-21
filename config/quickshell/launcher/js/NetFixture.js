.pragma library
// Fake NetworkManager / BlueZ objects for testing the launcher Network / Bluetooth sections without touching the real
// network (launcher/NetSource.qml, enabled by $QS_LAUNCHER_NET_FIXTURE=<json file>). The fakes carry the same property
// and method names as Quickshell.Networking / Quickshell.Bluetooth objects, so NetSource runs one code path; they are
// plain JS (not reactive), NetSource polls them anyway. Actions only log the verb + name (never a password) and move the
// fake state after `delayMs`. Fixture JSON (all fields optional):
//   { "delayMs": 1200, "badPsk": "<password that fails>", "failConnect": ["<name>"], "nmMissing": false,
//     "net": { "wifiEnabled": true, "noWifi": false,
//              "wired": [{ "name": "eth0", "connected": true, "hasLink": true, "linkSpeed": 1000, "profile": true }],
//              "wifi":  [{ "name": "example-ssid", "signal": 0.8, "security": "psk|sae|open|eap|wep", "known": true, "connected": false }] },
//     "bt":  { "adapter": true, "enabled": true, "name": "hci0",
//              "devices": [{ "name": "Headphones", "address": "00:00:5E:00:53:01", "icon": "audio-headset",
//                            "paired": true, "connected": false, "battery": 0.8, "failPair": false,
//                            "sink": true }] } }      sink = an audio sink node shows up `delayMs` after the connect (bt.sinks)

function make(fx, E, log) {
    var delay = fx.delayMs || 1200
    var timers = []                                  // {at, fn}
    function later(fn) { timers.push({ at: Date.now() + delay, fn: fn }) }
    function tick() {
        var now = Date.now(), due = timers.filter(function (t) { return t.at <= now })
        timers = timers.filter(function (t) { return t.at > now })
        due.forEach(function (t) { t.fn() })
    }
    var fails = fx.failConnect || []
    var nf = fx.net || {}
    var secMap = { psk: E.Wpa2Psk, wpa: E.WpaPsk, sae: E.Sae, open: E.Open, eap: E.Wpa2Eap, wep: E.StaticWep }

    var net = { backend: fx.nmMissing ? E.BackendNone : E.BackendNm, wifiEnabled: nf.wifiEnabled !== false, devices: { values: [] } }
    var wifiNets = []
    function setState(o, st) {
        o.state = st
        o.connected = st === E.Connected
        o.stateChanging = st === E.Connecting || st === E.Disconnecting
    }
    function wifiNet(w) {
        var o = { name: w.name, signalStrength: w.signal === undefined ? 0.5 : w.signal, security: secMap[w.security || "psk"],
                  known: !!w.known, failedHandlers: [] }
        setState(o, w.connected ? E.Connected : E.Disconnected)
        function fail(reason) { setState(o, E.Disconnected); o.failedHandlers.forEach(function (h) { h(reason) }) }
        function up(ok, reason) {
            setState(o, E.Connecting)
            later(function () {
                if (!ok) { fail(reason); return }
                wifiNets.forEach(function (n) { if (n !== o && n.connected) setState(n, E.Disconnected) })
                setState(o, E.Connected); o.known = true
            })
        }
        o.connect = function () { log("wifi connect " + o.name); up(fails.indexOf(o.name) < 0, E.NoSecrets) }
        o.connectWithPsk = function (psk) {
            log("wifi connectWithPsk " + o.name + " (" + psk.length + " chars)")
            o.known = true                                   // NM keeps the new profile even when the attempt fails
            up(psk !== fx.badPsk && fails.indexOf(o.name) < 0, E.NoSecrets)
        }
        o.disconnect = function () { log("wifi disconnect " + o.name); setState(o, E.Disconnecting); later(function () { setState(o, E.Disconnected) }) }
        o.forget = function () { log("wifi forget " + o.name); o.known = false; if (o.connected) setState(o, E.Disconnected) }
        o.connectionFailed = { connect: function (h) { o.failedHandlers.push(h) } }
        return o
    }
    ;(nf.wired || []).forEach(function (w) {
        var d = { type: E.Wired, name: w.name, hasLink: w.hasLink !== false, linkSpeed: w.linkSpeed || 0 }
        setState(d, w.connected ? E.Connected : E.Disconnected)
        d.network = w.profile === false ? null : { connect: function () {
            log("wired connect " + d.name); setState(d, E.Connecting)
            later(function () { setState(d, d.hasLink && fails.indexOf(d.name) < 0 ? E.Connected : E.Disconnected) })
        } }
        d.disconnect = function () { log("wired disconnect " + d.name); setState(d, E.Disconnecting); later(function () { setState(d, E.Disconnected) }) }
        net.devices.values.push(d)
    })
    if (!nf.noWifi) {
        wifiNets = (nf.wifi || []).map(wifiNet)
        var wd = { type: E.Wifi, name: "wlan0", scannerEnabled: false, networks: { values: wifiNets } }
        Object.defineProperty(wd, "connected", { get: function () { return wifiNets.some(function (n) { return n.connected }) } })
        net.devices.values.push(wd)
    }

    var bf = fx.bt || {}
    var bt = { defaultAdapter: null, sinks: [] }       // sinks: fake PipeWire audio sinks {name, address}
    bt.setDefaultSink = function (name) { log("audio default sink " + name + " (+ move streams)") }
    if (bf.adapter !== false) {
        var ad = { name: bf.name || "hci0", enabled: bf.enabled !== false, discovering: false, devices: { values: [] } }
        ad.state = ad.enabled ? E.AdEnabled : E.AdDisabled
        var hidden = []                                     // discovered only while discovering
        ;(bf.devices || []).forEach(function (b) {
            var d = { name: b.name || "", address: b.address || "", icon: b.icon || "", paired: !!b.paired, connected: !!b.connected,
                      trusted: !!b.paired, pairing: false, batteryAvailable: b.battery !== undefined, battery: b.battery || 0 }
            d.state = d.connected ? E.BtConnected : E.BtDisconnected
            d.connect = function () {
                log("bt connect " + d.name); d.state = E.BtConnecting
                later(function () {
                    var ok = fails.indexOf(d.name) < 0; d.connected = ok; d.state = ok ? E.BtConnected : E.BtDisconnected
                    if (ok && b.sink) later(function () { bt.sinks.push({ name: "bluez_output.fake_" + bt.sinks.length, address: d.address }) })
                })
            }
            d.disconnect = function () { log("bt disconnect " + d.name); d.state = E.BtDisconnecting; later(function () { d.connected = false; d.state = E.BtDisconnected }) }
            d.pair = function () { log("bt pair " + d.name); d.pairing = true; later(function () { d.pairing = false; d.paired = !b.failPair }) }
            d.forget = function () { log("bt forget " + d.name); ad.devices.values = ad.devices.values.filter(function (x) { return x !== d }) }
            ;(b.paired || b.connected ? ad.devices.values : hidden).push(d)
        })
        bt.defaultAdapter = ad
        bt.setDiscovering = function (on) {                 // NetSource uses this instead of the property on the fake
            log("bt discovering " + on); ad.discovering = on
            if (on) later(function () { hidden.forEach(function (d) { if (ad.devices.values.indexOf(d) < 0) ad.devices.values.push(d) }) })
        }
        bt.setEnabled = function (on) {
            log("bt power " + on); ad.state = on ? E.AdEnabling : E.AdDisabling
            later(function () { ad.enabled = on; ad.state = on ? E.AdEnabled : E.AdDisabled; if (!on) ad.discovering = false })
        }
    }
    net.setWifiEnabled = function (on) { log("wifi power " + on); net.wifiEnabled = on }
    return { net: net, bt: bt, tick: tick }
}
