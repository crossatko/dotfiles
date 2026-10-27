pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// Bluetooth profile / codec of the current output, under the output DevicePicker (same dropdown look). Shown only
// while the default sink is a bluez node. Quickshell's Pipewire service has no card-profile API, so the list comes
// from `pactl -f json list cards` (this card's profiles, `off` hidden) and a choice runs `pactl set-card-profile`;
// WirePlumber saves it (default-profile state) and restores it on the next connect. A2DP entries are named by codec,
// best first; headset (HSP/HFP) entries are last and marked "mic on, low quality".
DropSelect {
    id: bp

    property bool busy: false
    property var profiles: []                  // [{id, label, headset}]
    property string active: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string address: sink && sink.properties ? (sink.properties["api.bluez5.address"] || "") : ""
    readonly property string card: address !== "" ? "bluez_card." + address.replace(/:/g, "_") : ""
    readonly property var profile: profiles.find(p => p.id === active) || null

    visible: card !== "" && profiles.length > 0
    options: profiles.map(p => ({ label: p.label, note: p.headset ? "mic on, low quality" : undefined, noteTint: Theme.yellow }))
    currentIndex: profiles.findIndex(p => p.id === active)
    headIcon: Icons.bluetooth
    headText: busy ? "Switching…" : (profile ? "" : active)
    onToggled: o => { if (o) refresh() }
    onPicked: i => choose(profiles[i])

    function codec(desc) { const m = /codec ([^)]+)\)/.exec(desc || ""); return m ? m[1] : (desc || "") }
    function refresh() { if (card !== "" && !list.running) list.running = true }
    function choose(p) {
        if (p.id === active || busy) return
        busy = true
        set.command = ["pactl", "set-card-profile", card, p.id]
        set.running = true
    }
    function _parse(text) {
        let cards = []
        try { cards = JSON.parse(text) } catch (e) { return }
        const c = cards.find(x => x.name === card)
        if (!c) { profiles = []; active = ""; return }
        const out = []
        for (const id in c.profiles) {
            const p = c.profiles[id]
            if (id === "off" || p.available === false) continue
            const headset = id.startsWith("headset")
            out.push({ id: id, headset: headset, prio: p.priority || 0, label: (headset ? "Headset · " : "") + codec(p.description) })
        }
        // A2DP before headset, then by WirePlumber's priority; `a2dp-sink` (= the best codec) can repeat a named one
        out.sort((a, b) => (a.headset - b.headset) || (b.prio - a.prio))
        const byLabel = {}
        for (const p of out) if (!byLabel[p.label] || p.id === c.active_profile) byLabel[p.label] = p
        profiles = out.filter(p => byLabel[p.label] === p)
        active = c.active_profile || ""
    }

    // the sink node is replaced on every profile switch (also WirePlumber's own autoswitch), so its id is the trigger
    onCardChanged: { profiles = []; active = ""; refresh() }
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { bp.refresh() }
    }
    Component.onCompleted: refresh()

    Process {
        id: list
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector { onStreamFinished: bp._parse(text) }
    }
    Process {
        id: set
        onExited: { bp.busy = false; bp.refresh(); later.restart() }
    }
    Timer { id: later; interval: 1500; onTriggered: bp.refresh() }   // the new node settles a moment after pactl returns
}
