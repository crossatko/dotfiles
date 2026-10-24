pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Declares the glass surfaces of one layer window to the compositor (ext-background-effect blur region), so the
// solid_glass blur variant draws a lens / rim / frost per surface (popup card, bar chip, toast, OSD, modal card).
//
// Usage in a PanelWindow:   BackgroundEffect.blurRegion: Region { regions: glass.instances }
//                           Glass { id: glass; root: contentItem }
// A surface is any Item under `root` with `isGlassItem: true` (and optionally a `radius`). Only standalone surfaces
// are marked: everything inside a panel (rows, tiles, buttons) sits flat on the panel's glass, so a glass item's
// subtree is not searched, and neither is a scrolling view.
//
// Each surface gets a Region slot whose geometry is a BINDING to the item (its position, size, transforms, opacity
// and those of its ancestors), so it changes in the same frame as the content: a popup sliding / scaling / fading in
// has its glass from its first visible frame, with no per-frame scans. A slot is empty while its item is invisible
// or fully transparent. The tree is only searched to find the items: when the window is shown, on `refresh()`
// (call it when items are created, e.g. a Repeater's onItemAdded) and every `interval` ms for anything else.
// Slots are a fixed pool updated in place: rebuilding Region objects per change committed an EMPTY region on every
// frame in which they changed.
// Without solid_glass (Theme.glass false: stock Hyprland, other blur variant) the whole window is declared instead, so
// the blur stays what the qs-.* layer rule (blur + ignore_alpha) gave before: an empty region would disable it.
Item {
    id: g
    required property Item root
    property bool active: true
    property int interval: 250
    property var items: []
    property var transforms: []   // per item: the Transform objects on it and its ancestors (collected at search time)
    property var pool: Array.from({ length: 8 }, (_, i) => i)
    readonly property alias instances: vars.instances

    function find(item, out) {
        for (const c of item.children) {
            if (c.contentY !== undefined)
                continue
            if (c.isGlassItem === true)
                out.push(c)
            else
                find(c, out)
        }
    }
    function refresh() {
        if (!g.active)
            return
        const found = []
        if (Theme.glass)
            g.find(g.root, found)
        else if (Theme.glassKnown)          // nothing until known: a whole-window region would flash as glass
            found.push(g.root)
        if (found.length !== g.items.length || found.some((c, i) => c !== g.items[i])) {
            if (found.length > g.pool.length)
                g.pool = Array.from({ length: Math.ceil(found.length / 8) * 8 }, (_, i) => i)
            const ts = []
            for (const it of found) {
                const l = []
                for (let a = it; a && a !== g.root; a = a.parent)
                    for (const t of a.transform) l.push(t)
                ts.push(l)
            }
            g.transforms = ts
            g.items = found
        }
    }

    // Rect of `it` in root coordinates. Reads every property the mapping depends on, so a binding calling this is
    // re-evaluated whenever the item or an ancestor moves, resizes, transforms, hides or fades.
    readonly property var none: ({ x: 0, y: 0, w: 0, h: 0, r: 0 })
    function rectOf(it, ts) {
        if (!it || !it.visible || it.width <= 1 || it.height <= 1)
            return g.none
        let alpha = 1
        for (let a = it; a && a !== g.root; a = a.parent) {
            alpha *= a.opacity
            void (a.x + a.y + a.width + a.height + a.scale + a.rotation)
        }
        for (const t of ts || [])
            void [t.xScale, t.yScale, t.origin, t.x, t.y, t.angle]
        if (alpha <= 0.004)
            return g.none
        const p0 = it.mapToItem(g.root, 0, 0)
        const p1 = it.mapToItem(g.root, it.width, it.height)
        // optional `glassScale` on the item (0..1): the region shrinks about its centre (Theme.glassScaleAt: a card in
        // motion on a compositor whose glass cannot fade)
        const k = it.glassScale !== undefined ? Math.max(0, Math.min(1, it.glassScale)) : 1
        const cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2
        const hw = (p1.x - p0.x) * k / 2, hh = (p1.y - p0.y) * k / 2
        const x = Math.round(cx - hw), y = Math.round(cy - hh)
        const w = Math.round(cx + hw) - x, h = Math.round(cy + hh) - y
        if (w <= 1 || h <= 1)
            return g.none
        const r = Math.round((it.radius !== undefined ? it.radius : 0) * w / it.width)
        return { x: x, y: y, w: w, h: h, r: Math.max(0, Math.min(r, Math.floor(Math.min(w, h) / 2))) }
    }

    onActiveChanged: refresh()
    Connections { target: Theme; function onGlassChanged() { g.refresh() } function onGlassKnownChanged() { g.refresh() } }
    Component.onCompleted: refresh()
    Timer { interval: g.interval; repeat: true; running: g.active; onTriggered: g.refresh() }

    Variants {
        id: vars
        model: g.pool
        Region {
            required property int modelData
            readonly property var r: g.rectOf(g.items[modelData], g.transforms[modelData])
            x: r.x
            y: r.y
            width: r.w
            height: r.h
            radius: r.r
        }
    }
}
