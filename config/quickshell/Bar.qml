import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth

// One floating glass bar on one screen. `atTop` picks the edge.
PanelWindow {
    id: bar

    required property var modelData
    property bool atTop: false
    screen: modelData

    anchors { left: true; right: true; top: atTop; bottom: !atTop }
    margins { left: Theme.barGap; right: Theme.barGap; top: atTop ? Theme.barGap : 0; bottom: atTop ? 0 : Theme.barGap }
    implicitHeight: Theme.barHeight
    exclusiveZone: -1                  // full width even next to a reserved strip; BarReserve.qml reserves the space
    color: "transparent"
    WlrLayershell.namespace: "qs-bar"

    // ---- shared state -------------------------------------------------------
    property string cpu: "0%"
    property string mem: "0%"
    property var cpuHist: []                 // last HIST_N samples, 0..100
    property var memHist: []
    readonly property int histN: 14

    // reserve the width of the widest value / full graph so chips never resize as numbers or history change
    TextMetrics { id: pctMetrics; text: "100%"; font.family: Theme.font; font.pixelSize: Theme.fontSize }
    TextMetrics { id: sparkMetrics; text: "▁".repeat(bar.histN); font.family: Theme.font; font.pixelSize: Theme.fontSize }

    function pushSample(arr, v) {
        const a = arr.concat([v])
        return a.length > histN ? a.slice(a.length - histN) : a
    }
    // ▁▂▃▄▅▆▇█ sparkline. floor = smallest top-of-scale, so an idle CPU stays a flat low line instead of
    // being stretched to full height; memory passes a `lo` (its own minimum) since its changes are tiny.
    function spark(arr, floorSpan, useMin) {
        const blocks = "▁▂▃▄▅▆▇█"
        const hi0 = Math.max.apply(null, arr)
        const lo = useMin ? Math.min.apply(null, arr) : 0
        const span = Math.max(floorSpan, hi0 - lo)
        let s = " ".repeat(histN - arr.length)        // not enough history yet: pad on the left, graph grows in from the right
        for (const v of arr) s += blocks[Math.max(0, Math.min(7, Math.floor((v - lo) / span * 7.999)))]
        return s
    }
    property bool inhibit: false

    readonly property var kana: ({
        1: "ち", 2: "と", 3: "し", 4: "は", 5: "た", 6: "て",
        7: "い", 8: "す", 9: "つ", 10: "さ", 11: "そ", 12: "ひ"
    })

    // open a popup hung off `item` (a chip); toggles if it is already the open one
    // true while this bar's popup of that name is showing: the chip that opened it stays highlighted
    function isOpen(name) { return Popups.name === name && Popups.screen === bar.screen.name }
    function pop(name, item) {
        const p = item.mapToItem(null, 0, 0)
        Popups.toggle(name, bar.screen.name, Math.max(8, bar.width - (p.x + item.width)))
    }

    // the playing MPRIS player wins; a paused one only shows while the Twitch app isn't playing
    readonly property var player: {
        const ps = Mpris.players.values
        const twitchPlaying = twitchActive && twitchNow.playing
        return ps.find(p => p.isPlaying) || (twitchPlaying ? null : ps.find(p => p.trackTitle)) || null
    }
    // Twitch player (~/code/crossatko/twitch-qs-mpv): embedded libmpv has no MPRIS, so it publishes a status
    // file instead. Shown when no MPRIS player is active; ignored once it is older than 45 s (player gone).
    property var twitchNow: null
    property double twitchClock: Date.now()
    Timer { interval: 10000; running: true; repeat: true; onTriggered: bar.twitchClock = Date.now() }
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/twitch-qs-mpv-now.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { bar.twitchNow = JSON.parse(text()) } catch (e) { bar.twitchNow = null } }
        onLoadFailed: bar.twitchNow = null
    }
    readonly property bool twitchActive: twitchNow !== null && twitchClock - twitchNow.updated < 45000
    // Brand glyph (Font Awesome Brands) for whatever is playing; "" = fall back to plain play/pause.
    // The service (YouTube, Twitch, ...) wins over the browser playing it. Browsers' MPRIS has no URL, so
    // the service comes from the browser window title minus the track title ("<track> - YouTube - Brave").
    readonly property var services: [["spotify", "\uf1bc"], ["youtube", "\uf167"], ["youtu.be", "\uf167"], ["twitch", "\uf1e8"],
        ["soundcloud", "\uf1be"], ["deezer", "\ue077"], ["tidal", "\ue7dc"], ["apple music", "\uf179"], ["music.apple", "\uf179"],
        ["bandcamp", "\uf2d5"], ["vimeo", "\uf40a"], ["mixcloud", "\uf289"], ["last.fm", "\uf202"], ["pandora", "\ue7da"],
        ["tiktok", "\ue07b"], ["reddit", "\uf1a1"]]
    readonly property var browsers: [["brave", "\ue63c"], ["firefox", "\uf269"], ["chrom", "\uf268"], ["edge", "\uf282"]]
    function brandIn(list, s) { for (const m of list) if (s.indexOf(m[0]) >= 0) return m[1]; return "" }
    readonly property string mediaBrand: {
        if (!player) return twitchNow && twitchNow.playing ? "\uf1e8" : ""
        const md = player.metadata || {}
        const app = ((player.identity || "") + " " + (player.desktopEntry || "")).toLowerCase()
        const title = player.trackTitle || ""
        let win = ""
        if (title) {
            const t = ToplevelManager.toplevels.values.find(w => w.title && w.title.indexOf(title) >= 0)
            if (t) win = t.title.replace(title, "")
        }
        const where = (app + " " + (md["xesam:url"] || "") + " " + win).toLowerCase()
        return brandIn(services, where) || brandIn(services, title.toLowerCase()) || brandIn(browsers, app)
    }
    readonly property bool showTwitch: twitchActive && player === null
    // Screen recording (~/.config/hypr/scripts/screenrec.sh, SHIFT+Print & co.): the script writes key=value
    // lines (pid, comm, started, file, mode, audio) to $XDG_RUNTIME_DIR/screenrec/state while its recorder runs
    // and removes the file when it exits. Polled once a second (the file comes and goes, so a watch alone
    // misses its creation); the recorder's /proc/<pid>/comm is checked too, so a recorder that died without
    // its wrapper cleaning up doesn't leave the chip on. SCREENREC_RUNTIME_DIR = the script's test override.
    readonly property string recScript: Quickshell.env("HOME") + "/.config/hypr/scripts/screenrec.sh"
    readonly property string recDir: Quickshell.env("SCREENREC_RUNTIME_DIR") || (Quickshell.env("XDG_RUNTIME_DIR") + "/screenrec")
    property var recState: null              // parsed state file, null = no recording
    property bool recAlive: false
    readonly property bool recording: recState !== null && recAlive
    property double recClock: Date.now()
    readonly property string recElapsed: {
        if (!recording) return ""
        const s = Math.max(0, Math.floor(recClock / 1000) - (parseInt(recState.started) || 0))
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0")
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { recStateFile.reload(); if (bar.recState) recComm.reload(); bar.recClock = Date.now() }
    }
    FileView {
        id: recStateFile
        path: bar.recDir + "/state"
        printErrors: false
        onLoaded: {
            const o = {}
            for (const l of text().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1) }
            bar.recState = o.pid ? o : null
        }
        onLoadFailed: bar.recState = null
    }
    FileView {
        id: recComm
        path: bar.recState ? "/proc/" + bar.recState.pid + "/comm" : ""
        printErrors: false
        onLoaded: bar.recAlive = bar.recState !== null && text().trim() === bar.recState.comm
        onLoadFailed: bar.recAlive = false
    }
    // network: wired link wins, else Wi-Fi; dimmed when nothing is connected
    readonly property var netDevs: Networking.devices.values
    readonly property bool wiredUp: netDevs.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool wifiUp: netDevs.some(d => d.type === DeviceType.Wifi && d.connected)
    readonly property bool btOn: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property int btConnected: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values.filter(d => d.connected).length : 0
    // the applets stay running (they are the bluez / NetworkManager secret agents) but their tray icons are redundant
    function isApplet(i) {
        const s = ((i.id || "") + " " + (i.title || "")).toLowerCase()
        return s.includes("blueman") || s.includes("nm-applet") || s.includes("networkmanager")
    }

    function run(cmd) { runner.command = ["sh", "-c", cmd]; runner.startDetached() }
    Process { id: runner }

    IdleInhibitor { window: bar; enabled: bar.inhibit }

    Process {
        running: true
        // one long-lived awk: it needs the PREVIOUS /proc/stat sample to compute a percentage (starting a new
        // awk per sample, as before, never had one, so the chip stayed at 0%)
        command: ["awk", "BEGIN { while (1) { getline l < \"/proc/stat\"; close(\"/proc/stat\"); split(l, a, \" \"); busy = a[2] + a[3] + a[4]; tot = busy + a[5] + a[6] + a[7] + a[8] + a[9]; if (pt > 0 && tot > pt) printf \"%d\\n\", (busy - pb) * 100 / (tot - pt); pb = busy; pt = tot; fflush(); system(\"sleep 2\") } }"]
        stdout: SplitParser { onRead: line => { if (line) { bar.cpu = line + "%"; bar.cpuHist = bar.pushSample(bar.cpuHist, parseInt(line)) } } }
    }
    Process {
        running: true
        command: ["sh", "-c", "while :; do awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\\n\",(t-a)*100/t}' /proc/meminfo; sleep 3; done"]
        stdout: SplitParser { onRead: line => { if (line) { bar.mem = line + "%"; bar.memHist = bar.pushSample(bar.memHist, parseInt(line)) } } }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    // ---- visuals --------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.alpha(Theme.bg, Theme.barOpacity)
        border.width: Theme.barBorder
        border.color: Theme.alpha(Theme.overlay, 0.55)
    }

    // workspaces widget: with a bar on every monitor each bar shows its own monitor's workspaces; with a
    // single bar it shows all of them (it is the only place to switch workspaces on the other monitors).
    readonly property bool soloBar: BarConfig.enabledCount <= 1
    readonly property var shownWorkspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (soloBar || (w.monitor !== null && w.monitor.name === bar.screen.name)))
        .sort((a, b) => a.id - b.id)

    // ---- layout ---------------------------------------------------------------
    // Which widget sits in which section is BarWidgets' per-monitor layout (edited in Settings -> Bar).
    // Every widget is a Component below, keyed by its id; each section is a Row of Loaders over its id list.
    // A widget that has nothing to show right now (no player, empty tray) sets `show: false` and its Loader
    // hides, so a Row leaves no gap. The bell (control center) chip is not in the layout: always last on the right.
    readonly property var layout: BarWidgets.layoutFor(BarWidgets.keyOf(bar.screen))
    readonly property var widgetComps: ({
        workspaces: wsComp, recording: recComp, media: mediaComp, caffeine: caffeineComp, cpu: cpuComp, memory: memComp,
        homeassistant: haComp, ai: aiComp, volume: volumeComp, network: netComp, bluetooth: btComp,
        tray: trayComp, clock: clockComp
    })

    // a Repeater of Loaders over one section's id list (copied per section: an inline component here broke hot reload)
    Row {
        id: leftSec
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 4
        Repeater {
            model: bar.layout.left
            Loader {
                required property string modelData
                sourceComponent: bar.widgetComps[modelData] || null
                visible: item !== null && item.show !== false
            }
        }
    }
    // truly centered on the bar; only pushed aside when it would run into the left / right section
    Row {
        id: centerSec
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        x: {
            const lo = leftSec.x + leftSec.width + (leftSec.width > 0 ? 8 : 0)
            const hi = rightSec.x - (rightSec.width > 0 ? 8 : 0) - width
            return Math.round(Math.max(lo, Math.min((bar.width - width) / 2, hi)))
        }
        Repeater {
            model: bar.layout.center
            Loader {
                required property string modelData
                sourceComponent: bar.widgetComps[modelData] || null
                visible: item !== null && item.show !== false
            }
        }
    }
    Row {
        id: rightSec
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 4
        Repeater {
            model: bar.layout.right
            Loader {
                required property string modelData
                sourceComponent: bar.widgetComps[modelData] || null
                visible: item !== null && item.show !== false
            }
        }

        Chip {
            id: bellChip               // always shown: it opens the control center, whose gear opens Settings
            active: bar.isOpen("center")
            implicitWidth: Notifs.count > 0 ? 50 : 34
            onClicked: mouse => mouse.button === Qt.RightButton ? Notifs.setDnd(!Notifs.dnd) : bar.pop("center", bellChip)
            BarLabel { text: Notifs.dnd ? "\uf1f6" : Notifs.count > 0 ? "\uf8fa" : "\uf0c9"; color: Notifs.dnd ? Theme.muted : Notifs.count > 0 ? Theme.accent : Theme.fg; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { visible: Notifs.count > 0; text: Notifs.count; color: Theme.accent; font.pixelSize: 11 }
        }
    }

    // ---- widgets --------------------------------------------------------------
    Component {
        id: wsComp
        Row {
            spacing: 4
            Repeater {
                model: bar.shownWorkspaces
                Chip {
                    required property var modelData
                    visible: modelData.id > 0
                    active: modelData.focused
                    dim: !modelData.active && !modelData.focused
                    implicitWidth: 34
                    onClicked: bar.run("hyprctl dispatch 'hl.dsp.focus({workspace=" + modelData.id + "})'")
                    BarLabel { text: bar.kana[modelData.id] || modelData.id; color: modelData.focused ? Theme.accent : Theme.fg }
                }
            }
        }
    }

    // screen recording: only while one runs (see recState); pulsing red dot + elapsed time, click = stop
    Component {
        id: recComp
        Chip {
            property bool show: bar.recording
            onClicked: bar.run("'" + bar.recScript + "' stop")
            Rectangle {
                implicitWidth: 9; implicitHeight: 9; radius: 4.5
                color: Theme.red
                SequentialAnimation on opacity {
                    running: bar.recording; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            BarLabel { text: bar.recElapsed; color: Theme.red }
            BarLabel { visible: bar.recording && bar.recState.audio === "1"; text: ""; color: Theme.fgDim; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
        }
    }
    Component {
        id: mediaComp
        Chip {
            id: mediaChip
            property bool show: bar.player !== null || bar.showTwitch
            active: bar.isOpen("media")
            onClicked: mouse => {
                if (bar.player === null) {   // Twitch player: raise its window
                    bar.run("hyprctl clients -j | jq -r '.[]|select(.class==\"org.quickshell\" and (.title|startswith(\"Twitch - \")))|.address' | head -n1 | xargs -I{} hyprctl dispatch 'hl.dsp.focus({window=\"address:{}\"})'")
                } else if (mouse.button === Qt.MiddleButton) bar.player.togglePlaying()
                else bar.pop("media", mediaChip)
            }
            BarLabel {
                text: bar.mediaBrand ? bar.mediaBrand : bar.player ? (bar.player.isPlaying ? "\uf04b" : "\uf04c") : "\uf04c"
                color: bar.player && !bar.player.isPlaying ? Theme.muted : Theme.accent
                font.family: bar.mediaBrand ? "Font Awesome 7 Brands" : Theme.iconFont
                font.styleName: "Regular"; font.pixelSize: Theme.iconSize
            }
            BarLabel {
                text: bar.player ? bar.player.trackTitle + (bar.player.trackArtist ? "  ·  " + bar.player.trackArtist : "")
                    : bar.showTwitch ? bar.twitchNow.channel + (bar.twitchNow.game ? "  ·  " + bar.twitchNow.game : "") : ""
                elide: Text.ElideRight
                Layout.maximumWidth: 460
            }
        }
    }

    Component {
        id: caffeineComp
        Chip {
            active: bar.inhibit
            implicitWidth: 34
            onClicked: bar.inhibit = !bar.inhibit
            BarLabel { text: bar.inhibit ? "\uf7b6" : "\uf0f4"; color: bar.inhibit ? Theme.accent : Theme.muted; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
        }
    }
    Component {
        id: cpuComp
        Chip {
            BarLabel { text: "\uf2db"; color: Theme.fgDim; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { text: bar.cpu; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
            BarLabel { text: bar.spark(bar.cpuHist, 25, false); color: Theme.accent; Layout.preferredWidth: sparkMetrics.width }
        }
    }
    Component {
        id: memComp
        Chip {
            BarLabel { text: "\uf538"; color: Theme.fgDim; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { text: bar.mem; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
            BarLabel { text: bar.spark(bar.memHist, 10, true); color: Theme.accent2; Layout.preferredWidth: sparkMetrics.width }
        }
    }
    // Home Assistant (HomeAssistant.qml): opens the control popup; shows how many lights are on
    Component {
        id: haComp
        Chip {
            id: haChip
            active: bar.isOpen("ha")
            dim: !HomeAssistant.configured || (HomeAssistant.status !== "ok" && HomeAssistant.status !== "loading")
            onClicked: bar.pop("ha", haChip)
            BarLabel { text: HomeAssistant.lightsOn > 0 ? "\uf672" : "\uf015"; color: HomeAssistant.lightsOn > 0 ? Theme.accent : HomeAssistant.configured && HomeAssistant.status === "ok" ? Theme.fg : Theme.muted; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { visible: HomeAssistant.lightsOn > 0; text: HomeAssistant.lightsOn }
        }
    }
    // AI usage (AiUsage.qml): opens the accounts / limits popup; shows the fullest limit window of the most
    // recently used account with fresh values (AiUsage.current), muted when only stale values are known
    Component {
        id: aiComp
        Chip {
            id: aiChip
            active: bar.isOpen("ai")
            dim: AiUsage.loaded && AiUsage.profiles.length === 0 && AiUsage.others.length === 0
            onClicked: bar.pop("ai", aiChip)
            BarLabel { text: "\uf890"; color: AiUsage.anyExpired ? Theme.muted : Theme.accent; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { visible: AiUsage.currentPercent >= 0; text: Math.round(AiUsage.currentPercent) + "%"; color: AiUsage.currentStale ? Theme.muted : Theme.fg }
        }
    }
    Component {
        id: volumeComp
        Chip {
            id: audioChip
            active: bar.isOpen("audio")
            dim: bar.muted
            // click: audio popup (volume, mic, devices) | middle: mute | right: pavucontrol | wheel: volume
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) bar.run("pavucontrol")
                else if (mouse.button === Qt.MiddleButton) { if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted }
                else bar.pop("audio", audioChip)
            }
            onWheel: dy => {
                if (bar.sink && bar.sink.audio)
                    bar.sink.audio.volume = Math.max(0, Math.min(1.0, bar.sink.audio.volume + (dy > 0 ? 0.03 : -0.03)))
            }
            BarLabel { text: bar.muted ? "\uf6a9" : bar.volume < 0.01 ? "\uf026" : bar.volume < 0.5 ? "\uf027" : "\uf028"; color: bar.muted ? Theme.muted : Theme.accent; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: Theme.iconSize + 4; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { text: Math.round(bar.volume * 100) + "%"; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
        }
    }
    Component {
        id: netComp
        Chip {
            id: netChip
            active: bar.isOpen("net")
            dim: !bar.wiredUp && !bar.wifiUp
            onClicked: bar.pop("net", netChip)
            BarLabel { text: bar.wiredUp ? "\uf796" : bar.wifiUp ? "\uf1eb" : "\uf6ac"; color: bar.wiredUp || bar.wifiUp ? Theme.accent : Theme.muted; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
        }
    }
    Component {
        id: btComp
        Chip {
            id: btChip
            active: bar.isOpen("bt")
            dim: !bar.btOn
            onClicked: bar.pop("bt", btChip)
            BarLabel { text: "\uf293"; color: bar.btConnected > 0 ? Theme.accent : bar.btOn ? Theme.fg : Theme.muted; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: Theme.iconSize }
            BarLabel { visible: bar.btConnected > 0; text: bar.btConnected }
        }
    }
    Component {
        id: trayComp
        Chip {
            property bool show: SystemTray.items.values.some(i => !bar.isApplet(i))
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    visible: !bar.isApplet(modelData)
                    implicitWidth: 18
                    implicitHeight: 18
                    Rectangle {      // highlight while this item's menu is open (same look as an active chip)
                        anchors { fill: parent; margins: -4 }
                        radius: Theme.rounding
                        visible: menu.visible
                        color: Theme.alpha(Theme.accent, 0.28)
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.8)
                    }
                    Image {
                        anchors.fill: parent
                        source: trayItem.modelData.icon
                        sourceSize: Qt.size(36, 36)
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) trayItem.modelData.activate()
                            else if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate()
                            else if (trayItem.modelData.hasMenu) { menu.anchorX = trayItem.mapToItem(null, 0, 0).x; menu.show() }
                        }
                    }
                    TrayMenu {
                        id: menu
                        handle: trayItem.modelData.menu
                        host: bar
                        atTop: bar.atTop
                    }
                }
            }
        }
    }
    Component {
        id: clockComp
        Chip {
            id: clockChip
            active: bar.isOpen("cal")
            onClicked: mouse => mouse.button === Qt.RightButton ? bar.run("thunderbird --calendar") : bar.pop("cal", clockChip)
            BarLabel { text: Qt.formatDateTime(clock.date, "yyyy-MM-dd HH:mm") }
        }
    }
}
