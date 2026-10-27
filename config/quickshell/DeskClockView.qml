pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io

// The desktop clock's picture (DeskClock.qml shows it on the desktop, DeskClockPreview in Settings): the time in glass
// lettering (one GlassText per character, as the lock clock) and the date in the UI font, refracting what the desktop
// shows under it: the play-once video wallpaper of `connector` (DeskClockVideo: the same clip in step with the desktop
// player, moving during a burst), else `wallpaper` (the still / image, cropped like hyprpaper's cover). Nothing else is
// drawn behind the lettering; all optics come from Settings > Glass (GlassTuneCtl.effective).
// This item is SCREEN sized (backdrop coordinates); the clock sits in `area` (DeskClockPrefs size / position), the caller
// shows only that part. Until a source has a frame the lettering is GlassTextFlat, then the glass forms (popup motion
// tokens; none = instant). Without Theme.glass GlassText is flat anyway.
// Idle: nothing animates; a minute change morphs the changed digits; with seconds a tick morphs only the changed digits
// (each GlassText renders its own mask and shape field again, nothing else); a burst redraws the clock with the video's frames.
Item {
    id: v
    property string wallpaper: ""
    property string connector: ""           // "" = no video (Settings preview)
    property var screen: null               // whose wallpaper (wallpapers.json entry: the video for the brightness sample)
    property bool preview: false            // Settings: the wallpaper is drawn too (on the desktop it is under the window)
    readonly property bool wallReady: img.status === Image.Ready && img.source !== ""
    readonly property bool videoOn: video.ready
    readonly property Item source: videoOn ? video.output : stage
    readonly property bool sourceReady: videoOn || wallReady

    readonly property real unit: Math.min(width, height)
    // the digit size (DeskClockPrefs.size); with seconds the clock is wider: it shrinks only if it would not fit the screen
    readonly property int pixelSize: face.fitSize(Math.max(24, Math.round(unit * DeskClockPrefs.size)), width - 2 * margin)
    readonly property real margin: Math.round(unit * 0.03)
    readonly property real pad: Math.round(pixelSize * 0.4)           // the glass's shadow / caustic around the glyphs
    readonly property real boxW: col.width
    readonly property real boxH: col.height
    readonly property real boxX: Math.round(margin + DeskClockPrefs.posX * Math.max(0, width - 2 * margin - boxW))
    readonly property real boxY: Math.round(margin + DeskClockPrefs.posY * Math.max(0, height - 2 * margin - boxH))
    // what the clock really paints, in screen coordinates: measured (nested, light and dark wallpapers, light glass, seconds)
    // the glass and its shadow stay within ~0.15 x pixelSize left / right of the glyph box and inside it vertically; the
    // date's soft shadow reaches ~26 px below it. The lock's clean rect (grabClean) and bin/lock-clock-cover use this, not
    // the window (`area`: the GlassText pads, mostly empty).
    readonly property real inkPadX: Math.round(pixelSize * 0.2)
    readonly property real inkPadY: Math.max(28, Math.round(pixelSize * 0.06))
    readonly property rect ink: Qt.rect(Math.max(area.x, boxX - inkPadX), Math.max(area.y, boxY - inkPadY),
                                        Math.min(area.x + area.width, boxX + boxW + inkPadX) - Math.max(area.x, boxX - inkPadX),
                                        Math.min(area.y + area.height, boxY + boxH + inkPadY) - Math.max(area.y, boxY - inkPadY))
    // the drawn part, in screen coordinates (the window's geometry)
    readonly property rect area: Qt.rect(Math.max(0, boxX - pad), Math.max(0, boxY - pad),
                                         Math.min(width, boxX + boxW + pad) - Math.max(0, boxX - pad),
                                         Math.min(height, boxY + boxH + pad) - Math.max(0, boxY - pad))

    // the time (HH:mm[:ss], DeskClockPrefs clock24h / seconds), the digits' morph time (morph) and the fit (ClockFace);
    // test hook QS_DESKCLOCK_CLOCK (as the lock's QS_LOCK_CLOCK): a fixed text, or several separated by spaces, cycled every 3 s
    ClockFace {
        id: face
        h24: DeskClockPrefs.clock24h
        seconds: DeskClockPrefs.seconds
        morphTime: DeskClockPrefs.morph
        testEnv: v.preview ? "" : Quickshell.env("QS_DESKCLOCK_CLOCK") || ""
    }
    readonly property string text: face.text
    function demo() { face.demo() }        // Settings preview: one minute ahead and back (the morph)

    // Reveal (GlassReveal, the lock clock's): nothing is shown until the backdrop has a frame, then the digits form left
    // to right. Not on minute changes (those morph) nor video bursts.
    GlassReveal { id: reveal }
    property bool formed: false
    function form(delayMs) { formed = true; reveal.form(glyphRepeater, delayMs) }
    onSourceReadyChanged: if (sourceReady && !formed) form()
    // flat <-> glass, only after the clock formed: 1 = flat lettering (the backdrop went missing, e.g. a new wallpaper
    // still loading), 0 = glass
    readonly property bool wantFlat: formed && !sourceReady
    property real flatT: 0
    onWantFlatChanged: {
        flatAnim.stop()
        flatAnim.to = wantFlat ? 1 : 0
        flatAnim.duration = wantFlat ? Theme.popupCloseMs : Theme.popupMs(Motion.baseMs * 3)
        if (flatAnim.duration <= 0) flatT = flatAnim.to
        else flatAnim.start()
    }
    Component.onCompleted: { reveal.dateShown = 0; if (sourceReady) Qt.callLater(form) }
    NumberAnimation { id: flatAnim; target: v; property: "flatT"; easing.type: Easing.InOutSine }

    // ---- wallpaper-aware glass (DeskClockPrefs adapt / adaptStrength) ----
    // The wallpaper under the clock box is sampled once per (wallpaper, video, screen size, box) by bin/region-luma (cover
    // crop like hyprpaper; a play-once video by its held frame, other videos by still plus a few clip frames averaged:
    // never per frame) into 16 columns of mean linear
    // luminance; each digit takes the columns under it, so a clock across a bright / dark edge gets light glass on the
    // bright side only. Lightness = smoothstep over the perceptual value (mean^(1/2.2): 0.42 -> 0.72) x adaptStrength =
    // the shader's `airy` (glasstext.frag): 0 keeps the Settings > Glass look (tint, darkening: the DARK-background values),
    // 1 = light clear glass. Changes animate (popup motion tokens; none = instant). Idle: nothing; a sample ~50 ms.
    function videoOf(sc) {
        if (!sc || LockWallpapers.override !== "") return ""
        const e = LockWallpapers.monitors[Appearance.monitorKey(sc)]
        const p = e && typeof e.video === "string" ? e.video : ""
        return p.replace(/^~/, Theme.home)
    }
    // a play-once video (DeskClockVideo) is judged by the frame it holds (re-sampled when a burst ended and it holds the
    // next one: the glass changes then, smoothly; never during the burst), any other video by still + clip average
    readonly property string heldFile: video.ready && !video.playing && video.info ? video.info.file : ""
    readonly property string heldAt: heldFile !== "" ? Number(video.bursts[video.idx]).toFixed(3) : ""
    readonly property string lumaKey: !DeskClockPrefs.adapt || v.wallpaper === "" || !(v.width > 0) || !(boxW > 0) ? ""
        : [v.wallpaper, heldFile !== "" ? heldFile : videoOf(v.screen), Math.round(v.width), Math.round(v.height), Math.round(boxX), Math.round(boxY), Math.round(boxW), Math.round(boxH), heldAt].join("|")
    property var lumaCols: []
    property var lumaCache: ({})
    onLumaKeyChanged: lumaWait.restart()
    Timer {
        id: lumaWait
        interval: 400          // a size / position slider drag settles first
        onTriggered: {
            const k = v.lumaKey
            if (k === "") { v.lumaCols = []; return }
            if (v.lumaCache[k]) { v.lumaCols = v.lumaCache[k]; return }
            if (lumaProc.running) { restart(); return }
            const p = k.split("|")
            lumaProc.key = k
            lumaProc.command = ["python3", "-I", "-S", Quickshell.shellDir + "/bin/region-luma", p[0], p[2], p[3], p[4], p[5], p[6], p[7]].concat(p[1] ? [p[1], p[8]] : [])
            lumaProc.running = true
        }
    }
    Process {
        id: lumaProc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null
                try { c = JSON.parse(text).cols } catch (e) { c = null }
                if (!Array.isArray(c) || c.length === 0) return
                const m = Object.assign({}, v.lumaCache); m[lumaProc.key] = c; v.lumaCache = m
                if (lumaProc.key === v.lumaKey) v.lumaCols = c
            }
        }
    }
    // airy (0..1) of the box part x0..x1 (box px)
    function airyAt(x0, x1) {
        const c = lumaCols
        if (!DeskClockPrefs.adapt || !c || c.length === 0 || !(boxW > 0)) return 0
        const n = c.length
        const a = Math.max(0, Math.min(n - 1, Math.floor(x0 / boxW * n)))
        const b = Math.max(a, Math.min(n - 1, Math.ceil(x1 / boxW * n) - 1))
        let m = 0
        for (let i = a; i <= b; i++) m += c[i]
        const val = Math.pow(Math.max(0, m / (b - a + 1)), 1 / 2.2)
        const t = Math.max(0, Math.min(1, (val - 0.42) / 0.3))
        return t * t * (3 - 2 * t) * DeskClockPrefs.adaptStrength
    }

    // ---- what the glass refracts ----
    Item {
        id: stage
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true      // sampled bent by the glass
        Image {
            id: img
            anchors.fill: parent
            source: v.wallpaper !== "" && v.width > 0 ? "file://" + v.wallpaper : ""
            sourceSize: Qt.size(v.width, v.height)
            fillMode: Image.PreserveAspectCrop        // = hyprpaper's cover
            asynchronous: true
        }
    }
    // the video copy: drawn (an invisible VideoOutput gets no frames), but all but transparent, so the window shows
    // only the lettering; the desktop's own player is right under it
    DeskClockVideo {
        id: video
        anchors.fill: parent
        connector: v.preview ? "" : v.connector
        opacity: 0.004
    }

    // Settings preview: the desktop under the clock
    ShaderEffectSource { anchors.fill: parent; visible: v.preview; sourceItem: stage; hideSource: false }

    // Lock: the desktop under `ink` WITHOUT the clock (what the glass refracts), grabbed when a lock is requested; the
    // lock surface lays it over the desktop snapshot (which still has the clock) and fades it in (LockClockPatch).
    // done(result | null): result.url is an in-memory image of `ink`; keep the result alive while it is shown.
    // The copy of the rect is live only for the grab, so it costs nothing while a video plays: it is updated in the
    // window's next frame (frameSwapped), and only then grabbed (a grab before that copied an unrendered texture: old
    // GPU memory). No frame within 250 ms (the window is not drawing) = no patch (Lock then skips the ring).
    function grabClean(done) {
        if (!sourceReady || !(cleanArea.width > 0) || !v.Window.window) { done(null); return }
        if (cleanGrab.done) cleanGrab.done(null)
        cleanGrab.done = done
        cleanGrab.frames = 0
        cleanSrc.live = true
        cleanSrc.scheduleUpdate()
        cleanGrab.restart()
    }
    function cleanFinish(res) {
        const done = cleanGrab.done
        cleanGrab.done = null
        cleanGrab.stop()
        cleanSrc.live = false
        if (done) done(res)
    }
    Timer { id: cleanGrab; interval: 250; property var done: null; property int frames: 0; onTriggered: v.cleanFinish(null) }
    Connections {
        target: cleanGrab.done ? v.Window.window : null
        function onFrameSwapped() {
            if (!cleanGrab.done || ++cleanGrab.frames !== 1) return
            const r = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
            if (!cleanArea.grabToImage(res => v.cleanFinish(res), Qt.size(Math.round(cleanArea.width * r), Math.round(cleanArea.height * r))))
                v.cleanFinish(null)
        }
    }
    Item {
        id: cleanArea
        x: v.ink.x; y: v.ink.y
        width: v.ink.width; height: v.ink.height
        opacity: 0          // only grabbed, never shown
        ShaderEffectSource { id: cleanSrc; anchors.fill: parent; sourceItem: v.source; sourceRect: v.ink; hideSource: false; live: false }
    }

    // ---- the clock ----
    Column {
        id: col
        x: v.boxX; y: v.boxY
        spacing: -Math.round(v.pixelSize * 0.04)     // the glyph box has room for descenders the digits do not use
        Row {
            id: glyphs
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(v.pixelSize * 0.03)
            Repeater {
                id: glyphRepeater
                model: v.text.length
                Item {
                    id: slot
                    required property int index
                    readonly property alias glyph: g
                    implicitWidth: g.implicitWidth
                    implicitHeight: g.implicitHeight
                    GlassGlyph {
                        id: g
                        // not there until the first form(); glyphs made later (seconds / 12-hour switched: another
                        // character count) are there at once
                        pop: v.formed ? 1 : 0
                        airy: v.airyAt(glyphs.x + slot.x, glyphs.x + slot.x + slot.width)
                        Behavior on airy { NumberAnimation { duration: Theme.popupMs(Motion.baseMs * 3); easing.type: Easing.InOutSine } }
                        text: v.text.charAt(slot.index)
                        pixelSize: v.pixelSize
                        morphMs: face.morphMs
                        backdrop: v.source
                        sharpBackdrop: v.source
                        backdropSize: Qt.size(v.width, v.height)
                        origin: Qt.point(col.x + glyphs.x + slot.x, col.y + glyphs.y + slot.y)
                        presence: 1 - v.flatT
                        visible: v.flatT < 1
                    }
                    GlassTextFlat {
                        x: -g.pad; y: -g.pad
                        visible: v.flatT > 0 && Theme.glass      // without Theme.glass GlassText shows this itself
                        opacity: v.flatT * Math.min(1, g.pop * 1.4)
                        text: g.text; pixelSize: g.pixelSize; weight: g.weight; pad: g.pad
                    }
                }
            }
        }
        // the date in the UI font: with `adapt` its ink follows the wallpaper under the clock like the bar's (BarInk sets:
        // dark text with a pale halo on a bright wallpaper, light text with a dark halo on a dark one), else the theme's
        Label {
            id: date
            readonly property bool onBright: v.airyAt(0, v.boxW) > 0.5
            readonly property var ink: !DeskClockPrefs.adapt ? null : onBright ? Theme.barInkDark : Theme.barInkLight
            anchors.horizontalCenter: parent.horizontalCenter
            visible: DeskClockPrefs.showDate
            opacity: reveal.dateShown
            text: face.dateText
            font.pixelSize: Math.max(Theme.fontTitle, Math.round(v.pixelSize * 0.09))
            font.weight: Font.Medium
            color: ink ? ink.fg : Theme.fg
            Behavior on color { ColorAnimation { duration: Theme.popupMs(Motion.baseMs * 3); easing.type: Easing.InOutSine } }
            layer.enabled: true
            // 2x on a scale-1 output (smooth halo, no colour fringes from the text in the layer), 1x on scaled outputs
            layer.smooth: true
            layer.textureSize: Screen.devicePixelRatio > 1 ? Qt.size(0, 0) : Qt.size(width * 2, height * 2)
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 1; shadowHorizontalOffset: 0; shadowColor: Theme.alpha(date.ink ? date.ink.bg : Theme.bg, 0.9) }
        }
    }
}
