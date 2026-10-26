pragma ComponentBehavior: Bound
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

// One glass bar on one screen. `atTop` picks the edge. Docked (Theme.barGap 0, radius 0): flush with the
// screen edge, square. Floating: Theme.barGap away from the edge and both sides, corner radius Theme.barRadius.
// With a fullscreen window on the monitor's workspace it animates to the docked look (compactState).
PanelWindow {
    id: bar

    required property var modelData
    property bool atTop: false
    screen: modelData

    anchors { left: true; right: true; top: atTop; bottom: !atTop }
    // Always full width and tall enough for the floating gap: the visible bar (`frame`, below) moves inside the window,
    // so compacting never resizes the layer surface. Only `frame` takes input.
    readonly property real barH: BarConfig.heightOf(bar.screen)        // the bar proper (Theme.barHeight, or the flush-mode height)
    readonly property real padSide: BarConfig.padSide(bar.screen)       // chip inset (Theme.barPad, or the flush-mode padding)
    readonly property real barGap: BarConfig.barGapOf(bar.screen)       // floating gap to the edges (0 docked), per bar
    implicitHeight: barH + barGap
    mask: Region { item: frame }
    // -1 = full width even next to a reserved strip (BarReserve.qml reserves the space); the bar's own height with "respect reserved area" (Settings > Bar; BarReserve then hides)
    exclusiveZone: BarConfig.respectReserved(bar.screen) ? BarConfig.reserveOf(bar.screen) : -1
    color: "transparent"
    WlrLayershell.namespace: "qs-bar"

    // Compact: while this monitor's active workspace has a fullscreen window the bar animates to the docked look (floating
    // gap and corner radius -> 0), like upstream's compactState. `hasfullscreen` is not a workspace property in quickshell
    // 0.3, so it comes from lastIpcObject; a fullscreen event makes the shell refresh it. Layout space is not involved:
    // BarReserve keeps its strip, so tiled windows never reflow. (A real fullscreen window covers this layer; the compact
    // look is visible with fullscreen mode 1 (maximize-style) and over partly covering surfaces.)
    readonly property var fsMonitor: Hyprland.monitorFor(bar.screen)
    readonly property bool compact: fsMonitor?.activeWorkspace?.lastIpcObject?.hasfullscreen ?? false
    property real compactState: compact ? 1 : 0
    Behavior on compactState { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseClose } }
    readonly property real gapNow: barGap * (1 - compactState)
    readonly property real radiusNow: BarConfig.radiusOf(bar.screen) * (1 - compactState)
    onGapNowChanged: Popups.setBarGap(bar.screen.name, gapNow)
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (["fullscreen", "workspacev2", "focusedmonv2", "movewindowv2", "closewindow", "openwindow"].includes(ev.name))
                fsRefresh.restart()
        }
    }
    Timer { id: fsRefresh; interval: 30; onTriggered: Hyprland.refreshWorkspaces() }

    // glass shape: Glass.qml declares the bar container below (docked: full width, square; floating: the inset window,
    // Theme.barRadius corners) as the blur region. The window itself is already inset by the floating gap, so the
    // transparent gap around a floating bar is never blurred. Chips sit flat on it (no glass of their own).
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    // Option "transparent when flush" (Settings > Bar, bars.json `transparentFlush`, per bar): the backdrop fades with the
    // floating gap, so it is gone exactly when gapNow is 0 (docked, or compacted); `hidden` then also drops the blur region.
    readonly property bool transparentFlush: BarConfig.transparentFlush(bar.screen)
    readonly property real backdropOpacity: !transparentFlush ? 1 : barGap > 0 ? Math.max(0, Math.min(1, gapNow / barGap)) : 0
    Glass { id: glass; root: bar.contentItem; hidden: bar.backdropOpacity <= 0.004 }
    // colours of everything on the bar: the palette, or in light mode while the bar has no backdrop the set that reads
    // on the wallpaper strip under it (Theme.inkOn: the dark palette's light text on a dark wallpaper)
    readonly property var ink: backdropOpacity < 0.5 ? Theme.inkOn(bar.screen?.name ?? "", atTop) : Theme

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
    // Popups.center is the chip's centre x in SCREEN coordinates (the window is full width, so window coordinates)
    property var chipItems: ({})
    function reg(name, item) { chipItems[name] = item }
    function centerOf(item) { return item.mapToItem(null, 0, 0).x + item.width / 2 }
    // -1 = chip unknown / hidden
    function chipCenter(name) {
        const it = chipItems[name]
        return it && it.visible ? centerOf(it) : -1
    }
    function pop(name, item) {
        reg(name, item)
        Popups.toggle(name, bar.screen.name, centerOf(item))
    }
    Component.onCompleted: { Popups.barObjs[bar.screen.name] = bar; Popups.setBarGap(bar.screen.name, gapNow) }

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
        interval: 1000; running: BarWidgets.shown("recording"); repeat: true
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

    function run(argv) { runner.command = argv; runner.startDetached() }
    Process { id: runner }

    IdleInhibitor { window: bar; enabled: bar.inhibit }

    // CPU / memory: pure QML (FileView on procfs + Timer), no child processes (a shell loop in a Process orphans
    // to systemd when qs exits). CPU needs the PREVIOUS /proc/stat sample for a percentage.
    property real cpuPrevBusy: 0
    property real cpuPrevTot: 0
    Timer {
        interval: 2000; running: BarWidgets.shown("cpu"); repeat: true; triggeredOnStart: true
        onTriggered: statFile.reload()
    }
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const a = text().split("\n")[0].trim().split(/\s+/).map(Number)   // cpu user nice system idle iowait irq softirq steal
            const busy = a[1] + a[2] + a[3]
            const tot = busy + a[4] + a[5] + a[6] + a[7] + a[8]
            if (bar.cpuPrevTot > 0 && tot > bar.cpuPrevTot) {
                const v = Math.trunc((busy - bar.cpuPrevBusy) * 100 / (tot - bar.cpuPrevTot))
                bar.cpu = v + "%"
                bar.cpuHist = bar.pushSample(bar.cpuHist, v)
            }
            bar.cpuPrevBusy = busy
            bar.cpuPrevTot = tot
        }
    }
    Timer {
        interval: 3000; running: BarWidgets.shown("memory"); repeat: true; triggeredOnStart: true
        onTriggered: memFile.reload()
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const t = text()
            const total = parseInt((t.match(/MemTotal:\s+(\d+)/) || [])[1])
            const avail = parseInt((t.match(/MemAvailable:\s+(\d+)/) || [])[1])
            if (total > 0 && avail >= 0) {
                const v = Math.trunc((total - avail) * 100 / total)
                bar.mem = v + "%"
                bar.memHist = bar.pushSample(bar.memHist, v)
            }
        }
    }
    // Not SystemClock: it re-arms a QTimer with a negative interval during the repeated local hour at the end of DST (fires every 1 ms, ~2000 warnings/s, ~9% CPU)
    property date clockNow: new Date()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: bar.clockNow = new Date() }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

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
    // hides, so a Row leaves no gap. The bell (control center) chip is a widget like the rest, but never hideable (BarWidgets.pinnedId).
    readonly property var layout: BarWidgets.layoutFor(BarWidgets.keyOf(bar.screen))
    readonly property var widgetComps: ({
        workspaces: wsComp, recording: recComp, media: mediaComp, caffeine: caffeineComp, cpu: cpuComp, memory: memComp,
        homeassistant: haComp, ai: aiComp, volume: volumeComp, network: netComp, bluetooth: btComp,
        tray: trayComp, dnd: dndComp, calendar: calComp, clock: clockComp, controlcenter: bellComp
    })


    // the bar proper: the window is always full width and barHeight + Theme.barGap tall (no layer-shell resize while
    // animating); `frame` is the visible bar inside it, inset by `gapNow` from the edges (see compactState)
    Item {
        id: frame
        x: bar.gapNow
        width: bar.width - 2 * bar.gapNow
        height: bar.barH
        y: bar.atTop ? bar.gapNow : bar.height - bar.barH - bar.gapNow

        // ---- visuals --------------------------------------------------------------
        Rectangle {
            anchors.fill: parent
            readonly property bool isGlassItem: true
            radius: bar.radiusNow
            opacity: bar.backdropOpacity
            color: Theme.alpha(Theme.bg, Theme.barFill)
            border.width: Theme.barBorder
            border.color: Theme.alpha(Theme.overlay, 0.55)
        }
        // empty bar space (the popup scrim has the bar cut out of its input region): a click closes any open popup
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: if (Popups.anyOpen) Popups.closeAll()
        }

        // a Repeater of Loaders over one section's id list (copied per section: an inline component here broke hot reload)
        Row {
            id: leftSec
            anchors { left: parent.left; leftMargin: bar.padSide; verticalCenter: parent.verticalCenter }
            spacing: 4
            Repeater {
                model: bar.layout.left
                Loader {
                    required property string modelData
                    sourceComponent: bar.widgetComps[modelData] || null
                    visible: item !== null && (item as Chip)?.show !== false
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
                return Math.round(Math.max(lo, Math.min((frame.width - width) / 2, hi)))
            }
            Repeater {
                model: bar.layout.center
                Loader {
                    required property string modelData
                    sourceComponent: bar.widgetComps[modelData] || null
                    visible: item !== null && (item as Chip)?.show !== false
                }
            }
        }
        Row {
            id: rightSec
            anchors { right: parent.right; rightMargin: bar.padSide; verticalCenter: parent.verticalCenter }
            spacing: 4
            Repeater {
                model: bar.layout.right
                Loader {
                    required property string modelData
                    sourceComponent: bar.widgetComps[modelData] || null
                    visible: item !== null && (item as Chip)?.show !== false
                }
            }
        }
    }

    // ---- widgets --------------------------------------------------------------
    Component {
        id: wsComp
        Row {
            spacing: 4
            Repeater {
                model: bar.shownWorkspaces
                Chip { ink: bar.ink;
                    id: wsChip
                    required property var modelData
                    visible: modelData.id > 0
                    active: modelData.focused
                    dim: !modelData.active && !modelData.focused
                    onClicked: bar.run(["hyprctl", "dispatch", "hl.dsp.focus({workspace=" + modelData.id + "})"])
                    BarIcon { text: String(bar.kana[wsChip.modelData.id] || wsChip.modelData.id); family: Theme.font; styleName: ""; pixelSize: Theme.fontSize; color: wsChip.modelData.focused ? bar.ink.accent : bar.ink.fg }
                }
            }
        }
    }

    // screen recording: only while one runs (see recState); pulsing red dot + elapsed time, click = stop
    Component {
        id: recComp
        Chip { ink: bar.ink;
            show: bar.recording
            onClicked: bar.run([bar.recScript, "stop"])
            Rectangle {
                implicitWidth: 8; implicitHeight: 8; radius: 4
                color: bar.ink.red
                SequentialAnimation on opacity {
                    running: bar.recording; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            BarLabel { text: bar.recElapsed; color: bar.ink.red }
            BarIcon { visible: bar.recording && bar.recState.audio === "1"; text: "\uf028"; color: bar.ink.fgDim }
        }
    }
    Component {
        id: mediaComp
        Chip { ink: bar.ink;
            id: mediaChip
            Component.onCompleted: bar.reg("media", mediaChip)
            show: bar.player !== null || bar.showTwitch
            active: bar.isOpen("media")
            onClicked: mouse => {
                if (bar.player === null) {   // Twitch player: raise its window
                    bar.run(["sh", "-c", "hyprctl clients -j | jq -r '.[]|select(.class==\"org.quickshell\" and (.title|startswith(\"Twitch - \")))|.address' | head -n1 | xargs -I{} hyprctl dispatch 'hl.dsp.focus({window=\"address:{}\"})'"])
                } else if (mouse.button === Qt.MiddleButton) bar.player.togglePlaying()
                else bar.pop("media", mediaChip)
            }
            BarIcon {
                text: bar.mediaBrand ? bar.mediaBrand : bar.player ? (bar.player.isPlaying ? "\uf04b" : "\uf04c") : "\uf04c"
                color: bar.player && !bar.player.isPlaying ? bar.ink.muted : bar.ink.accent
                family: bar.mediaBrand ? Theme.brandFont : Theme.iconFont
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
        Chip { ink: bar.ink;
            active: bar.inhibit
            onClicked: bar.inhibit = !bar.inhibit
            BarIcon { text: bar.inhibit ? "\uf7b6" : "\uf0f4"; color: bar.inhibit ? bar.ink.accent : bar.ink.muted }
        }
    }
    Component {
        id: cpuComp
        Chip { ink: bar.ink;
            BarIcon { text: "\uf2db"; color: bar.ink.fgDim }
            BarLabel { text: bar.cpu; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
            BarLabel { text: bar.spark(bar.cpuHist, 25, false); color: bar.ink.accent; Layout.preferredWidth: sparkMetrics.width }
        }
    }
    Component {
        id: memComp
        Chip { ink: bar.ink;
            BarIcon { text: "\uf538"; color: bar.ink.fgDim }
            BarLabel { text: bar.mem; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
            BarLabel { text: bar.spark(bar.memHist, 10, true); color: bar.ink.accent2; Layout.preferredWidth: sparkMetrics.width }
        }
    }
    // Home Assistant (HomeAssistant.qml): opens the control popup; shows how many lights are on
    Component {
        id: haComp
        Chip { ink: bar.ink;
            id: haChip
            Component.onCompleted: bar.reg("ha", haChip)
            active: bar.isOpen("ha")
            dim: !HomeAssistant.configured || (HomeAssistant.status !== "ok" && HomeAssistant.status !== "loading")
            onClicked: bar.pop("ha", haChip)
            BarIcon { text: HomeAssistant.lightsOn > 0 ? "\uf672" : "\uf015"; color: HomeAssistant.lightsOn > 0 ? bar.ink.accent : HomeAssistant.configured && HomeAssistant.status === "ok" ? bar.ink.fg : bar.ink.muted }
            BarLabel { visible: HomeAssistant.lightsOn > 0; text: HomeAssistant.lightsOn }
        }
    }
    // AI usage (AiUsage.qml): opens the accounts / limits popup; shows the short-window (daily / 5 h) limit of
    // the most recently used account with fresh values (AiUsage.currentPercent), muted when only stale values are known
    Component {
        id: aiComp
        Chip { ink: bar.ink;
            id: aiChip
            Component.onCompleted: bar.reg("ai", aiChip)
            active: bar.isOpen("ai")
            dim: AiUsage.loaded && AiUsage.profiles.length === 0 && AiUsage.others.length === 0
            onClicked: bar.pop("ai", aiChip)
            BarIcon { text: "\uf890"; color: AiUsage.anyExpired ? bar.ink.muted : bar.ink.accent }
            // limit reached: time until the agent is usable again (AiUsage.blockedUntil), fixed width so the
            // minute countdown does not make the chip jitter; else the percentage
            BarLabel {
                id: aiLbl
                readonly property bool blocked: AiUsage.blockedUntil > 0
                visible: blocked || AiUsage.currentPercent >= 0
                text: blocked ? AiUsage.until(AiUsage.blockedUntil) : Math.round(AiUsage.currentPercent) + "%"
                color: AiUsage.currentStale ? bar.ink.muted : bar.ink.fg
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: blocked ? Math.max(implicitWidth, aiTm.width) : implicitWidth
                TextMetrics { id: aiTm; font: aiLbl.font; text: "23h 59m" }
            }
        }
    }
    Component {
        id: volumeComp
        Chip { ink: bar.ink;
            id: audioChip
            Component.onCompleted: bar.reg("audio", audioChip)
            active: bar.isOpen("audio")
            dim: bar.muted
            // click: audio popup (volume, mic, devices) | middle: mute | right: pavucontrol | wheel: volume
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) bar.run(["pavucontrol"])
                else if (mouse.button === Qt.MiddleButton) { if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted }
                else bar.pop("audio", audioChip)
            }
            onWheel: dy => {
                if (bar.sink && bar.sink.audio)
                    bar.sink.audio.volume = Math.max(0, Math.min(1.0, bar.sink.audio.volume + (dy > 0 ? 0.03 : -0.03)))
            }
            BarIcon { measure: "\uf028"; text: Icons.volumeGlyph(bar.muted, bar.volume); color: bar.muted ? bar.ink.muted : bar.ink.accent }
            BarLabel { text: Math.round(bar.volume * 100) + "%"; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: pctMetrics.width }
        }
    }
    Component {
        id: netComp
        Chip { ink: bar.ink;
            id: netChip
            Component.onCompleted: bar.reg("net", netChip)
            active: bar.isOpen("net")
            dim: !bar.wiredUp && !bar.wifiUp
            onClicked: bar.pop("net", netChip)
            BarIcon { text: bar.wiredUp ? "\uf796" : bar.wifiUp ? "\uf1eb" : "\uf6ac"; color: bar.wiredUp || bar.wifiUp ? bar.ink.accent : bar.ink.muted }
        }
    }
    Component {
        id: btComp
        Chip { ink: bar.ink;
            id: btChip
            Component.onCompleted: bar.reg("bt", btChip)
            active: bar.isOpen("bt")
            dim: !bar.btOn
            onClicked: bar.pop("bt", btChip)
            // while AirPods are connected: a Font Awesome Pro Solid battery by level (bolt while charging) + their lowest bud level instead of the device count
            // (the count stays when something else is connected too); green while charging, red at 15 % and below
            readonly property bool pods: AirPods.lowest >= 0
            readonly property color podsColor: AirPods.lowestCharging ? bar.ink.green : AirPods.lowest <= 15 ? bar.ink.red : bar.ink.fgDim
            BarIcon { text: "\uf293"; color: bar.btConnected > 0 || btChip.pods ? bar.ink.accent : bar.btOn ? bar.ink.fg : bar.ink.muted }
            BarLabel { visible: bar.btConnected > (btChip.pods ? 1 : 0); text: bar.btConnected }
            BarIcon {
                visible: btChip.pods
                Layout.leftMargin: 2
                family: Theme.iconFontPro
                styleName: "Solid"
                measure: "\uf240"
                text: AirPods.lowestCharging ? "\uf376" : AirPods.lowest >= 88 ? "\uf240" : AirPods.lowest >= 63 ? "\uf241" : AirPods.lowest >= 38 ? "\uf242" : AirPods.lowest >= 13 ? "\uf243" : "\uf244"
                color: btChip.podsColor
            }
            BarLabel { visible: btChip.pods; text: AirPods.lowest + "%"; color: btChip.podsColor }
        }
    }
    Component {
        id: trayComp
        Chip { ink: bar.ink;
            show: SystemTray.items.values.some(i => !bar.isApplet(i))   // qmllint disable missing-property
            padX: 6
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    visible: !bar.isApplet(modelData)
                    implicitWidth: Theme.chipIcon
                    implicitHeight: Theme.chipIcon
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {      // highlight while this item's menu is open (same look as an active chip)
                        anchors { fill: parent; margins: -3 }
                        radius: Theme.radiusChip
                        visible: menu.visible
                        color: Theme.alpha(bar.ink.accent, 0.28)
                        border.width: 1
                        border.color: Theme.alpha(bar.ink.accent, 0.8)
                    }
                    Image {
                        anchors.fill: parent
                        source: trayItem.modelData.icon
                        sourceSize: Qt.size(2 * Theme.chipIcon, 2 * Theme.chipIcon)
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
        Chip { ink: bar.ink;
            id: clockChip
            // the clock opens the notification center; the calendar is its own chip (calComp)
            Component.onCompleted: bar.reg("notif", clockChip)
            active: bar.isOpen("notif")
            onClicked: mouse => mouse.button === Qt.RightButton ? Notifs.setDnd(!Notifs.dnd) : bar.pop("notif", clockChip)
            BarLabel { text: Qt.formatDateTime(bar.clockNow, "yyyy-MM-dd HH:mm"); color: Notifs.dnd ? bar.ink.muted : bar.ink.fg }
            BarIcon { visible: Notifs.dnd || Notifs.count > 0; Layout.leftMargin: Theme.chipGap; text: Notifs.dnd ? "\uf1f6" : "\uf8fa"; color: Notifs.dnd ? bar.ink.muted : bar.ink.accent }
            BarLabel { visible: Notifs.count > 0; text: Notifs.count; color: bar.ink.accent; font.pixelSize: Theme.fontCaption }
        }
    }

    // do-not-disturb: only while it is on (Notifs.dnd is event-driven); click = turn it off
    Component {
        id: dndComp
        Chip { ink: bar.ink;
            show: Notifs.dnd
            onClicked: Notifs.setDnd(false)
            BarIcon { text: "\uf1f6"; color: bar.ink.muted }
        }
    }

    Component {
        id: calComp
        Chip { ink: bar.ink;
            id: calChip
            Component.onCompleted: bar.reg("cal", calChip)
            active: bar.isOpen("cal")
            onClicked: mouse => mouse.button === Qt.RightButton ? bar.run(["thunderbird", "--calendar"]) : bar.pop("cal", calChip)
            BarIcon { text: "\uf073"; color: bar.ink.fg }
        }
    }

    Component {
        id: bellComp
        Chip { ink: bar.ink;
            id: bellChip               // opens the control center, whose gear opens Settings; popups centre on it wherever it sits
            Component.onCompleted: bar.reg("center", bellChip)
            active: bar.isOpen("center")
            onClicked: mouse => mouse.button === Qt.RightButton ? Notifs.setDnd(!Notifs.dnd) : bar.pop("center", bellChip)
            BarIcon { text: "\uf0c9"; color: Notifs.dnd ? bar.ink.muted : bar.ink.fg }
        }
    }
}
