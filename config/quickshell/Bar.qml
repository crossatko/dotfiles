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
    // Wallpaper aware colours of everything on the bar (BarContrast.qml samples the wallpaper strip behind the bar once per
    // wallpaper / size change, BarInk.qml decides per section). Each section Row hands its set down as `barInk`; Chip, BarIcon
    // and BarLabel find it. Without a backdrop (flat) and with adaptive contrast on, the text is dark on a bright wallpaper and
    // light on a dark one, whatever the theme mode; otherwise the palette (light mode and no backdrop: Theme.inkOn as before).
    readonly property bool inkFlat: backdropOpacity < 0.5
    readonly property string inkMode: BarConfig.contrast(bar.screen)
    readonly property real inkSens: BarConfig.contrastSens(bar.screen)
    readonly property real inkFill: BarConfig.hoverFill(bar.screen) / 100
    readonly property var inkBase: inkFlat ? Theme.inkOn(bar.screen?.name ?? "", atTop) : Theme
    // the strip under the bar: its pixel height (the window's bar part) and edge pick the cache entry
    readonly property string lumaKey: inkFlat && inkMode === "auto" ? BarContrast.keyFor(bar.screen, atTop, barH + barGap) : ""
    onLumaKeyChanged: BarContrast.request(lumaKey)
    readonly property var lumaCols: lumaKey !== "" ? BarContrast.cols[lumaKey] ?? null : null
    Connections { target: BarContrast; function onBumpedChanged() { BarContrast.request(bar.lumaKey) } }
    // sections' extents as fractions of the screen width (chips appearing / hiding move them: only a recompute)
    function secSeg(sec, fallback) {
        if (!lumaCols) return null
        const w = Math.max(1, bar.width)
        const wide = sec.width > 0
        return BarContrast.segment(lumaCols, wide ? (frame.x + sec.x) / w : fallback[0], wide ? (frame.x + sec.x + sec.width) / w : fallback[1])
    }
    readonly property var inkLeft: inkL     // (IPC status of BarContrast)
    readonly property var inkCenter: inkC
    readonly property var inkRight: inkR
    BarInk { id: inkL; base: bar.inkBase; flat: bar.inkFlat; mode: bar.inkMode; sens: bar.inkSens; fill: bar.inkFill; seg: bar.secSeg(leftSec, [0, 0.33]) }
    BarInk { id: inkC; base: bar.inkBase; flat: bar.inkFlat; mode: bar.inkMode; sens: bar.inkSens; fill: bar.inkFill; seg: bar.secSeg(centerSec, [0.33, 0.66]) }
    BarInk { id: inkR; base: bar.inkBase; flat: bar.inkFlat; mode: bar.inkMode; sens: bar.inkSens; fill: bar.inkFill; seg: bar.secSeg(rightSec, [0.66, 1]) }

    // ---- shared state -------------------------------------------------------
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
    Component.onCompleted: { BarContrast.bars[bar.screen.name] = bar; BarContrast.request(lumaKey); Popups.barObjs[bar.screen.name] = bar; Popups.setBarGap(bar.screen.name, gapNow) }

    // the playing MPRIS player wins; a paused one only shows while the Twitch app isn't playing
    // (media chip only: nothing below runs while the widget is in no layout)
    readonly property bool mediaOn: BarWidgets.shown("media")
    readonly property var player: {
        if (!mediaOn) return null
        const ps = Mpris.players.values
        const twitchPlaying = twitchActive && twitchNow.playing
        return ps.find(p => p.isPlaying) || (twitchPlaying ? null : ps.find(p => p.trackTitle)) || null
    }
    // Twitch player (~/code/crossatko/twitch-qs-mpv): embedded libmpv has no MPRIS, so it publishes a status
    // file instead. Shown when no MPRIS player is active; ignored once it is older than 45 s (player gone).
    property var twitchNow: null
    property double twitchClock: Date.now()
    Timer {
        interval: 10000; running: bar.mediaOn; repeat: true
        onRunningChanged: if (running) bar.twitchClock = Date.now()
        onTriggered: bar.twitchClock = Date.now()
    }
    FileView {
        path: bar.mediaOn ? Quickshell.env("XDG_RUNTIME_DIR") + "/twitch-qs-mpv-now.json" : ""
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
    readonly property var services: [["spotify", Icons.spotify], ["youtube", Icons.youtube], ["youtu.be", Icons.youtube], ["twitch", Icons.twitch],
        ["soundcloud", Icons.soundcloud], ["deezer", Icons.deezer], ["tidal", Icons.tidal], ["apple music", Icons.apple], ["music.apple", Icons.apple],
        ["bandcamp", Icons.bandcamp], ["vimeo", Icons.vimeo], ["mixcloud", Icons.mixcloud], ["last.fm", Icons.lastfm], ["pandora", Icons.pandora],
        ["tiktok", Icons.tiktok], ["reddit", Icons.reddit]]
    readonly property var browsers: [["brave", Icons.brave], ["firefox", Icons.firefox], ["chrom", Icons.chrome], ["edge", Icons.edge]]
    function brandIn(list, s) { for (const m of list) if (s.indexOf(m[0]) >= 0) return m[1]; return "" }
    readonly property string mediaBrand: {
        if (!mediaOn) return ""
        if (!player) return twitchNow && twitchNow.playing ? Icons.twitch : ""
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
    readonly property bool showTwitch: mediaOn && twitchActive && player === null
    readonly property int mediaLabelMax: 460    // the media ticker's title never grows past this (elided)
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

    // an item that reports itself Passive asks not to be shown (omacal with its tray icon turned off)
    function trayHidden(i) { return bar.isApplet(i) || i.status === Status.Passive }

    function run(argv) { runner.command = argv; runner.startDetached() }
    Process { id: runner }

    IdleInhibitor { window: bar; enabled: bar.inhibit }

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
        workspaces: wsComp, recording: recComp, vm: vmComp, media: mediaComp, caffeine: caffeineComp, cpu: cpuComp, memory: memComp,
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
            GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass
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
            readonly property var barInk: inkL
            anchors { left: parent.left; leftMargin: bar.padSide; verticalCenter: parent.verticalCenter }
            spacing: Theme.gapTight
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
            readonly property var barInk: inkC
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gapTight
            x: {
                const lo = leftSec.x + leftSec.width + (leftSec.width > 0 ? Theme.gapRow : 0)
                const hi = rightSec.x - (rightSec.width > 0 ? Theme.gapRow : 0) - width
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
            readonly property var barInk: inkR
            anchors { right: parent.right; rightMargin: bar.padSide; verticalCenter: parent.verticalCenter }
            spacing: Theme.gapTight
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
    // Icon colours carry STATE (DESIGN.md "Colour"): `ink.accent` while the chip's feature is connected / on / live (a
    // wired or Wi-Fi link, a Bluetooth device, unmuted audio, a playing player, a running VM, a usable AI account,
    // caffeine on, lights on, the focused workspace), `ink.muted` while it is off / missing / muted, red / green where
    // they mean something (recording, battery), plain `ink.fg` only for always-present informational items (clock,
    // calendar, control center, a Bluetooth adapter that is merely on). Each BarInk set carries its own variant.
    Component {
        id: wsComp
        Row {
            spacing: Theme.gapTight
            Repeater {
                model: bar.shownWorkspaces
                Chip {
                    id: wsChip
                    required property var modelData
                    visible: modelData.id > 0
                    active: modelData.focused
                    dim: !modelData.active && !modelData.focused
                    onClicked: bar.run(["hyprctl", "dispatch", "hl.dsp.focus({workspace=" + modelData.id + "})"])
                    BarIcon { text: String(bar.kana[wsChip.modelData.id] || wsChip.modelData.id); family: Theme.font; styleName: ""; pixelSize: Theme.fontSize; color: wsChip.modelData.focused ? ink.accent : ink.fg }
                }
            }
        }
    }

    // screen recording: only while one runs (see recState); pulsing red dot + elapsed time, click = stop
    Component {
        id: recComp
        Chip {
            id: recChip
            show: Recording.recording
            onClicked: bar.run([Recording.script, "stop"])
            StatusDot { tint: recChip.ink.red; pulse: Recording.recording; Layout.alignment: Qt.AlignVCenter }
            BarLabel { text: Recording.elapsed; color: ink.red }
            BarIcon { visible: Recording.recording && Recording.state.audio === "1"; text: Icons.volumeHigh; color: ink.fgDim }
        }
    }
    // virtual machines (VmService.qml): only while a VM runs or a VM download / install prep is in progress; icon + count of
    // running VMs, while a job runs also a thin progress bar and the percentage (no name); click = the VM panel (VmPanel.qml)
    Component {
        id: vmComp
        VmChip {
            id: vmChip
            Component.onCompleted: bar.reg("vm", vmChip)
            active: bar.isOpen("vm")
            onClicked: bar.pop("vm", vmChip)
        }
    }
    Component {
        id: mediaComp
        Chip {
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
                text: bar.mediaBrand ? bar.mediaBrand : bar.player ? (bar.player.isPlaying ? Icons.play : Icons.pause) : Icons.pause
                color: bar.player && !bar.player.isPlaying ? ink.muted : ink.accent   // the brand mark follows the chip's role too
                family: bar.mediaBrand ? Theme.brandFont : Theme.iconFont
            }
            BarLabel {
                text: bar.player ? bar.player.trackTitle + (bar.player.trackArtist ? "  ·  " + bar.player.trackArtist : "")
                    : bar.showTwitch ? bar.twitchNow.channel + (bar.twitchNow.game ? "  ·  " + bar.twitchNow.game : "") : ""
                elide: Text.ElideRight
                Layout.maximumWidth: bar.mediaLabelMax
            }
        }
    }

    Component {
        id: caffeineComp
        Chip {
            active: bar.inhibit
            onClicked: bar.inhibit = !bar.inhibit
            BarIcon { text: bar.inhibit ? Icons.caffeineOn : Icons.caffeineOff; color: bar.inhibit ? ink.accent : ink.muted }
        }
    }
    Component {
        id: cpuComp
        Chip {
            BarIcon { text: Icons.cpu; color: ink.fgDim }
            BarLabel { text: SystemStats.cpu; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: SystemStats.pctWidth }
            BarLabel { text: SystemStats.cpuSpark; color: ink.accent; Layout.preferredWidth: SystemStats.sparkWidth }
        }
    }
    Component {
        id: memComp
        Chip {
            BarIcon { text: Icons.memory; color: ink.fgDim }
            BarLabel { text: SystemStats.mem; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: SystemStats.pctWidth }
            BarLabel { text: SystemStats.memSpark; color: ink.accent2; Layout.preferredWidth: SystemStats.sparkWidth }
        }
    }
    // Home Assistant (HomeAssistant.qml): opens the control popup; shows how many lights are on
    Component {
        id: haComp
        Chip {
            id: haChip
            Component.onCompleted: bar.reg("ha", haChip)
            active: bar.isOpen("ha")
            dim: !HomeAssistant.configured || (HomeAssistant.status !== "ok" && HomeAssistant.status !== "loading")
            onClicked: bar.pop("ha", haChip)
            // lights on = accent + count; connected = plain ink; not configured / unreachable = muted (and the chip dims)
            BarIcon { text: HomeAssistant.lightsOn > 0 ? Icons.lightOn : Icons.home; color: HomeAssistant.lightsOn > 0 ? ink.accent : HomeAssistant.configured && HomeAssistant.status === "ok" ? ink.fg : ink.muted }
            BarLabel { visible: HomeAssistant.lightsOn > 0; text: HomeAssistant.lightsOn }
        }
    }
    // AI usage (AiUsage.qml): opens the accounts / limits popup; shows the short-window (daily / 5 h) limit of
    // the most recently used account with fresh values (AiUsage.currentPercent), muted when only stale values are known
    Component {
        id: aiComp
        Chip {
            id: aiChip
            Component.onCompleted: bar.reg("ai", aiChip)
            active: bar.isOpen("ai")
            dim: AiUsage.loaded && AiUsage.profiles.length === 0 && AiUsage.others.length === 0
            onClicked: bar.pop("ai", aiChip)
            BarIcon { text: Icons.ai; color: AiUsage.anyExpired ? ink.muted : ink.accent }
            // limit reached: time until the agent is usable again (AiUsage.blockedUntil), fixed width so the
            // minute countdown does not make the chip jitter; else the percentage
            BarLabel {
                id: aiLbl
                readonly property bool blocked: AiUsage.blockedUntil > 0
                visible: blocked || AiUsage.currentPercent >= 0
                text: blocked ? AiUsage.until(AiUsage.blockedUntil) : Math.round(AiUsage.currentPercent) + "%"
                color: AiUsage.currentStale ? ink.muted : ink.fg
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: blocked ? Math.max(implicitWidth, aiTm.width) : implicitWidth
                TextMetrics { id: aiTm; font: aiLbl.font; text: "23h 59m" }
            }
        }
    }
    Component {
        id: volumeComp
        Chip {
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
            BarIcon { measure: Icons.volumeHigh; text: Icons.volumeGlyph(bar.muted, bar.volume); color: bar.muted ? ink.muted : ink.accent }
            BarLabel { text: Math.round(bar.volume * 100) + "%"; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: SystemStats.pctWidth }
        }
    }
    Component {
        id: netComp
        Chip {
            id: netChip
            Component.onCompleted: bar.reg("net", netChip)
            active: bar.isOpen("net")
            dim: !bar.wiredUp && !bar.wifiUp
            onClicked: bar.pop("net", netChip)
            BarIcon { text: bar.wiredUp ? Icons.ethernet : bar.wifiUp ? Icons.wifi : Icons.wifiOff; color: bar.wiredUp || bar.wifiUp ? ink.accent : ink.muted }
        }
    }
    Component {
        id: btComp
        Chip {
            id: btChip
            Component.onCompleted: bar.reg("bt", btChip)
            active: bar.isOpen("bt")
            dim: !bar.btOn
            onClicked: bar.pop("bt", btChip)
            // while AirPods are connected: a Font Awesome Pro Solid battery by level (bolt while charging) + their lowest bud level instead of the device count
            // (the count stays when something else is connected too); green while charging, red at 15 % and below
            readonly property bool pods: AirPods.lowest >= 0
            readonly property color podsColor: AirPods.lowestCharging ? ink.green : AirPods.lowest <= 15 ? ink.red : ink.fgDim
            BarIcon { text: Icons.bluetooth; color: bar.btConnected > 0 || btChip.pods ? ink.accent : bar.btOn ? ink.fg : ink.muted }
            BarLabel { visible: bar.btConnected > (btChip.pods ? 1 : 0); text: bar.btConnected }
            BarIcon {
                visible: btChip.pods
                Layout.leftMargin: 2
                family: Theme.iconFontPro
                styleName: "Solid"
                measure: Icons.batteryFull
                text: AirPods.lowestCharging ? Icons.batteryBolt : AirPods.lowest >= 88 ? Icons.batteryFull : AirPods.lowest >= 63 ? Icons.batteryThreeQuarters : AirPods.lowest >= 38 ? Icons.batteryHalf : AirPods.lowest >= 13 ? Icons.batteryQuarter : Icons.batteryEmpty
                color: btChip.podsColor
            }
            BarLabel { visible: btChip.pods; text: AirPods.lowest + "%"; color: btChip.podsColor }
        }
    }
    Component {
        id: trayComp
        Chip {
            id: trayChip
            show: SystemTray.items.values.some(i => !bar.trayHidden(i))   // qmllint disable missing-property
            padX: 6
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    visible: !bar.trayHidden(modelData)
                    implicitWidth: Theme.chipIcon
                    implicitHeight: Theme.chipIcon
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {      // highlight while this item's menu is open (same look as an active chip)
                        anchors { fill: parent; margins: -3 }
                        radius: Theme.radiusChip
                        visible: menu.visible
                        color: Theme.alpha(trayChip.ink.accent, 0.28)
                        border.width: 1
                        border.color: Theme.alpha(trayChip.ink.accent, 0.8)
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
        Chip {
            id: clockChip
            // the clock opens the notification center (not when it would be empty, unless it is already open);
            // the calendar is its own chip (calComp)
            Component.onCompleted: bar.reg("notif", clockChip)
            active: bar.isOpen("notif")
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) Notifs.setDnd(!Notifs.dnd)
                else if (Notifs.liveCount > 0 || bar.isOpen("notif")) bar.pop("notif", clockChip)
            }
            BarLabel { text: Qt.formatDateTime(SystemStats.clockNow, "yyyy-MM-dd HH:mm"); color: Notifs.dnd ? ink.muted : ink.fg }
            // unread badge: bell + count in accent; a muted bell-slash under do-not-disturb
            BarIcon { visible: Notifs.dnd || Notifs.count > 0; Layout.leftMargin: Theme.chipGap; text: Notifs.dnd ? Icons.bellOff : Icons.bellOn; color: Notifs.dnd ? ink.muted : ink.accent }
            BarLabel { visible: Notifs.count > 0; text: Notifs.count; color: ink.accent; font.pixelSize: Theme.fontCaption }
        }
    }

    // do-not-disturb: only while it is on (Notifs.dnd is event-driven); click = turn it off
    Component {
        id: dndComp
        Chip {
            show: Notifs.dnd
            onClicked: Notifs.setDnd(false)
            BarIcon { text: Icons.bellOff; color: ink.muted }
        }
    }

    Component {
        id: calComp
        Chip {
            id: calChip
            Component.onCompleted: bar.reg("cal", calChip)
            active: bar.isOpen("cal")
            onClicked: mouse => mouse.button === Qt.RightButton ? bar.run(["sh", "-c", "command -v omacal >/dev/null && exec omacal || notify-send omacal \"omacal is not installed\""]) : bar.pop("cal", calChip)
            BarIcon { text: Icons.calendar }
        }
    }

    Component {
        id: bellComp
        Chip {
            id: bellChip               // opens the control center, whose gear opens Settings; popups centre on it wherever it sits
            Component.onCompleted: bar.reg("center", bellChip)
            active: bar.isOpen("center")
            onClicked: mouse => mouse.button === Qt.RightButton ? Notifs.setDnd(!Notifs.dnd) : bar.pop("center", bellChip)
            BarIcon { text: Icons.menu; color: Notifs.dnd ? ink.muted : ink.fg }
        }
    }
}
