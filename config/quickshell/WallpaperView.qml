import QtQuick
import Quickshell.Hyprland

// A screen's wallpaper (Wallpaper.entryFor(screen)): two WallpaperImage slots; a new image loads in the hidden one and
// fades in over the shown one once decoded (Ready), so a switch never shows black or a half-loaded image. Latest wins:
// a newer pick replaces a load in progress; one that arrives during a fade waits for its end (a cut-short fade jumped),
// then the latest one fades in. A failed or
// `pending` file (a video still not extracted yet) keeps what is shown. Fade = Motion.emphasisMs with the colour easing
// (OutCubic: most of the change in the first frames, so the switch reads as instant; 0 with motion off). After the fade the old slot is emptied: at rest one static texture, nothing animating.
// `ready` = the first image is shown (or there is none to wait for): the window maps only then (WallpaperLayer).
// `hasImage` = an image is on screen (stays true through every later switch: the old one is kept until the new one is in).
// Also the desktop clock's refraction backdrop (DeskClockView: `path` = its wallpaper, `reporting` off), so the glass
// switches with the same fade as the desktop under it and never loses its backdrop while a new image decodes.
Item {
    id: root
    property var screen: null
    property string path: ""                      // explicit image ("" = the screen's Wallpaper entry)
    property bool reporting: true                 // the screen's own layer (Wallpaper.status); embedded copies: off
    readonly property var entry: Wallpaper.entryFor(screen)
    readonly property var want: path === "" ? entry
        : entry.path === path ? entry : { path: path, fit: "cover", w: 0, h: 0, pending: false }
    property bool hasImage: false
    readonly property int fadeMs: Motion.emphasisMs      // large surface; 0 with motion off
    property bool ready: false
    property int front: 0                         // the slot on screen (0 / 1)
    readonly property var slots: [s0, s1]
    readonly property var shownSlot: slots[front]
    readonly property var backSlot: slots[1 - front]
    readonly property string conn: screen ? String(screen.name) : ""
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    property real pixelScale: monitor && monitor.scale > 0 ? monitor.scale : 1    // physical px per logical px
    property Image fading: null                   // the slot fading in

    function report(state) { if (reporting) Wallpaper.report(conn, want.path, shownSlot.status === Image.Ready ? shownSlot.path : "", state) }

    function sync(force) {
        const w = root.want
        if (w.pending || w.path === "") {      // nothing loadable yet: keep what is shown
            if (!root.ready) root.ready = true
            report(w.pending ? "pending" : "none")
            return
        }
        if (fade.running) return              // a newer pick during a fade: it follows when this fade ends (no jump)
        const cur = shownSlot, back = backSlot
        cur.imageW = cur.path === w.path ? w.w : cur.imageW
        cur.imageH = cur.path === w.path ? w.h : cur.imageH
        if (!force && cur.path === w.path && cur.fit === w.fit && cur.status !== Image.Error) {
            back.path = ""                        // a load of something older: dropped
            report(cur.status === Image.Ready ? "ready" : "loading")
            return
        }
        if (!force && back.path === w.path && back.fit === w.fit && back.status === Image.Loading) return
        back.opacity = 0
        back.fit = w.fit
        back.imageW = w.w
        back.imageH = w.h
        if (force) back.path = ""
        back.path = w.path
        if (back.status === Image.Ready) show(back)   // (a cache hit can be Ready at once)
        else report("loading")
    }

    function show(slot) {
        if (slot !== backSlot || slot.path !== root.want.path || (fade.running && root.fading === slot)) return
        if (!root.ready || root.fadeMs <= 0) {   // first image (the window maps with it) / motion off: no fade
            slot.opacity = 1
            swap()
            root.ready = true
            return
        }
        root.fading = slot
        fade.restart()
    }
    function swap() {
        const old = shownSlot
        root.front = 1 - root.front
        old.opacity = 0
        old.path = ""
        root.hasImage = true
        report("ready")
    }
    function failed(slot) {
        if (slot !== backSlot) return
        console.warn("wallpaper: cannot load " + slot.path + " on " + root.conn)
        slot.path = ""
        if (!root.ready) root.ready = true      // black rather than nothing
        report("error")
    }

    onWantChanged: sync(false)
    onWidthChanged: if (width > 0 && height > 0 && shownSlot.path === "") sync(false)
    onHeightChanged: if (width > 0 && height > 0 && shownSlot.path === "") sync(false)
    Component.onCompleted: sync(false)
    Connections {
        target: Wallpaper
        function onGenChanged() { root.sync(true) }
    }

    WallpaperImage {
        id: s0
        anchors.fill: parent
        pixelScale: root.pixelScale
        z: root.front === 0 ? 0 : 1
        opacity: 0
        visible: opacity > 0
        onStatusChanged: if (status === Image.Ready) root.show(s0); else if (status === Image.Error) root.failed(s0)
    }
    WallpaperImage {
        id: s1
        anchors.fill: parent
        pixelScale: root.pixelScale
        z: root.front === 1 ? 0 : 1
        opacity: 0
        visible: opacity > 0
        onStatusChanged: if (status === Image.Ready) root.show(s1); else if (status === Image.Error) root.failed(s1)
    }
    NumberAnimation {
        id: fade
        target: root.fading
        property: "opacity"
        from: 0
        to: 1
        duration: root.fadeMs
        easing.type: Motion.easeHover
        onFinished: { root.swap(); root.sync(false) }   // a pick that came during the fade starts now
    }
}
