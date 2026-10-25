pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "launcher/js/BtNotify.js" as Bt

// Connect / disconnect notifications for every Bluetooth device (replaces blueman's ConnectionNotifier, which shows
// a generic headphones icon for AirPods). Source: Quickshell.Bluetooth, the `connected` flag of each device.
//  - A device seen for the first time is only remembered (`announced`), so a shell start or reload says nothing about
//    devices that are already connected.
//  - A change is not announced at once: it waits in `pending` and is judged when its wait is over, against the state
//    last announced. Disconnect waits `offMs`, so a disconnect followed by a reconnect (flapping, a codec switch)
//    ends up equal to what was announced and stays silent. Connect waits `onMs`, or for AirPods until the librepods
//    daemon reports a battery (at most `podsMs`), so the notice carries the battery and is posted once.
//  - Powering the adapter off drops every connection: those disconnects are not announced.
//  - The notice is a plain `notify-send` (argv) into the shell's own notification server, so DND, the toast stack and
//    the center treat it like any other. Env hook for tests: QS_BTNOTIF_FIXTURE (JSON file, see `loadFixture`), which
//    replaces Quickshell.Bluetooth and is re-read on every change.
Item {
    id: root
    visible: false

    readonly property string fixturePath: Quickshell.env("QS_BTNOTIF_FIXTURE") ? String(Quickshell.env("QS_BTNOTIF_FIXTURE")) : ""
    readonly property int onMs: 800
    readonly property int podsMs: 2500
    readonly property int offMs: 3000
    property bool fixtureAdapterOn: true
    readonly property bool adapterOn: fixturePath !== "" ? fixtureAdapterOn : (Bluetooth.defaultAdapter?.enabled ?? true)   // qmllint disable unresolved-type

    property var announced: ({})        // address -> connected, as last announced (or first seen)
    property var pending: ({})          // address -> {dev, since}

    function observe(dev) {
        const key = String(dev.address)
        if (!(key in announced)) {
            announced[key] = dev.connected === true
            return
        }
        if (dev.connected === announced[key] && !(key in pending)) return
        pending[key] = { dev: dev, since: Date.now() }
        tick.start()
    }

    function ready(e, now) {
        const waited = now - e.since
        if (!e.dev.connected) return waited >= offMs
        if (Bt.isAirPods(e.dev, AirPods)) return Bt.podsReady(AirPods) ? waited >= onMs : waited >= podsMs
        return waited >= onMs
    }

    function settle() {
        const now = Date.now()
        for (const key of Object.keys(pending)) {
            const e = pending[key]
            if (!ready(e, now)) continue
            delete pending[key]
            const cur = e.dev.connected === true
            if (cur === announced[key]) continue            // flapped back: nothing happened
            announced[key] = cur
            if (!cur && !adapterOn) continue                // adapter switched off
            post(e.dev, cur)
        }
        if (Object.keys(pending).length === 0) tick.stop()
    }

    function post(dev, connected) {
        Quickshell.execDetached(Bt.argv(dev, AirPods, connected, Quickshell.shellDir + "/assets"))
    }

    Timer { id: tick; interval: 200; repeat: true; onTriggered: root.settle() }

    // real devices: one observer per device object
    Instantiator {
        model: root.fixturePath === "" ? Bluetooth.devices : null   // qmllint disable unresolved-type
        delegate: QtObject {
            id: watch
            required property var modelData
            Component.onCompleted: root.observe(watch.modelData)
            property Connections c: Connections {
                target: watch.modelData
                function onConnectedChanged() { root.observe(watch.modelData) }
            }
        }
    }

    // {"adapter": true, "devices": [{"address", "name", "icon", "connected", "batteryAvailable", "battery"}]}
    FileView {
        path: root.fixturePath
        watchChanges: root.fixturePath !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text())
                root.fixtureAdapterOn = j.adapter !== false
                for (const d of j.devices ?? []) root.observe(d)
            } catch (e) {}
        }
    }
}
