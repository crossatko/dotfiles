import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Pipewire

// Bluetooth profile / codec of the current output, under the output DevicePicker (same dropdown look). Shown only
// while the default sink is a bluez node. Quickshell's Pipewire service has no card-profile API, so the list comes
// from `pactl -f json list cards` (this card's profiles, `off` hidden) and a choice runs `pactl set-card-profile`;
// WirePlumber saves it (default-profile state) and restores it on the next connect. A2DP entries are named by codec,
// best first; headset (HSP/HFP) entries are last and marked "mic on, low quality".
ColumnLayout {
    id: bp

    property bool open: false
    property bool busy: false
    property var profiles: []                  // [{id, label, headset}]
    property string active: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string address: sink && sink.properties ? (sink.properties["api.bluez5.address"] || "") : ""
    readonly property string card: address !== "" ? "bluez_card." + address.replace(/:/g, "_") : ""
    readonly property var current: profiles.find(p => p.id === active) || null

    visible: card !== "" && profiles.length > 0
    spacing: 4

    function codec(desc) { const m = /codec ([^)]+)\)/.exec(desc || ""); return m ? m[1] : (desc || "") }
    function refresh() { if (card !== "" && !list.running) list.running = true }
    function choose(p) {
        open = false
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

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusItem
        color: head.containsMouse ? Theme.alpha(Theme.fg, 0.13) : Theme.alpha(Theme.fg, 0.07)
        border.width: bp.open ? 1 : 0
        border.color: Theme.alpha(Theme.accent, 0.8)
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            Icon { text: ""; font.pixelSize: 12; color: Theme.fgDim }
            Label {
                text: bp.busy ? "Switching…" : bp.current ? bp.current.label : bp.active
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSmall
            }
            Label {
                visible: !bp.busy && bp.current !== null && bp.current.headset
                text: "mic on, low quality"
                color: Theme.yellow
                font.pixelSize: Theme.fontCaption
            }
            Icon {
                text: ""
                font.pixelSize: 12
                color: Theme.fgDim
                rotation: bp.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { id: head; anchors.fill: parent; hoverEnabled: true; onClicked: { bp.open = !bp.open; if (bp.open) bp.refresh() } }
    }

    // dropdown list; collapses to zero height so the panel resizes around it
    Item {
        Layout.fillWidth: true
        implicitHeight: bp.open ? opts.implicitHeight : 0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: opts
            width: parent.width
            spacing: 3
            Repeater {
                model: bp.profiles
                Rectangle {
                    id: optRow
                    required property var modelData
                    readonly property bool isCurrent: modelData.id === bp.active
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.radiusItem
                    color: isCurrent ? Theme.alpha(Theme.accent, 0.22) : opt.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Label { text: optRow.modelData.label; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: optRow.isCurrent ? Theme.accent : Theme.fg }
                        Label { visible: optRow.modelData.headset; text: "mic on, low quality"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                        Icon { visible: optRow.isCurrent; text: ""; font.pixelSize: 12; color: Theme.accent }
                    }
                    MouseArea { id: opt; anchors.fill: parent; hoverEnabled: true; onClicked: bp.choose(optRow.modelData) }
                }
            }
        }
    }
}
