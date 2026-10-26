pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bar layout: which widgets each bar shows, in which section (left / center / right) and in what order.
// Per monitor, keyed like BarConfig (model|serial); a monitor without its own entry uses `default`.
// Saved in ~/.local/state/quickshell/bar-widgets.json as
//   { "version": 2, "default": {left, center, right, hidden}, "monitors": { "<key>": {left, center, right, hidden} } }
// Older files ({ "<widget id>": false, ... } = hidden) are read as the default layout with those widgets hidden.
// Every layout is normalized on load: unknown ids are dropped, duplicates removed, and registry ids the
// layout doesn't mention yet are appended to their default section, so adding a widget never breaks a saved
// layout. The notifications / control-center chip (`controlcenter`) is a normal widget that can be moved and
// reordered, with one exception: it can never be hidden (it is the way into Settings), so `move` refuses
// "hidden" for it and `normalize` puts it back in its default section when a file lists it as hidden. Files
// that predate it get it appended at the right end, where it always was.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"

    // registry; `section` = where the widget goes by default, order = default order within that section
    readonly property var widgets: [
        { id: "workspaces", title: "Workspaces",   icon: "\uf00a", section: "left" },
        { id: "recording",  title: "Screen recording", icon: "\uf03d", section: "right" },   // visible only while recording
        { id: "vm",         title: "Virtual machines", icon: "\uf108", section: "right", before: "media" },   // visible only while a VM runs or a VM download is in progress
        { id: "media",      title: "Now playing",  icon: "\uf001", section: "right" },
        { id: "caffeine",   title: "Keep awake",   icon: "\uf0f4", section: "right" },
        { id: "cpu",        title: "CPU",          icon: "\uf2db", section: "right" },
        { id: "memory",     title: "Memory",       icon: "\uf538", section: "right" },
        { id: "homeassistant", title: "Home Assistant", icon: "\uf015", section: "right" },
        { id: "ai",         title: "AI usage",     icon: "\uf890", section: "right" },
        { id: "volume",     title: "Volume",       icon: "\uf028", section: "right" },
        { id: "network",    title: "Network",      icon: "\uf1eb", section: "right" },
        { id: "bluetooth",  title: "Bluetooth",    icon: "\uf293", section: "right" },
        { id: "tray",       title: "Tray",         icon: "\uf0c9", section: "right" },
        { id: "dnd",        title: "Do not disturb", icon: "\uf1f6", section: "right", before: "clock" },   // visible only while do-not-disturb is on
        { id: "calendar",   title: "Calendar",     icon: "\uf073", section: "right", before: "clock" },   // icon-only chip; a layout file without it gets it right before the clock
        { id: "clock",      title: "Clock",        icon: "\uf017", section: "right" },   // opens the notification center
        { id: "controlcenter", title: "Control center", icon: "\uf0f3", section: "right" }   // last = rightmost by default; never hideable
    ]
    readonly property string pinnedId: "controlcenter"
    readonly property var sections: ["left", "center", "right", "hidden"]

    function info(id) { return widgets.find(w => w.id === id) || { id: id, title: id, icon: "", section: "right" } }

    function normalize(l) {
        const out = { left: [], center: [], right: [], hidden: [] }
        const seen = {}
        if (l && typeof l === "object")
            for (const s of sections)
                for (const id of (Array.isArray(l[s]) ? l[s] : []))
                    if (typeof id === "string" && !seen[id] && widgets.some(w => w.id === id) && !(s === "hidden" && id === pinnedId)) { seen[id] = true; out[s].push(id) }
        // widgets the layout doesn't mention yet: appended to their default section; those with `before` go right
        // before that widget wherever it is (so a new widget sits next to its neighbour in an old layout file)
        for (const w of widgets) if (!seen[w.id] && !w.before) out[w.section].push(w.id)
        for (const w of widgets) if (!seen[w.id] && w.before) {
            const s = sections.find(k => out[k].indexOf(w.before) >= 0 && k !== "hidden")
            if (s) out[s].splice(out[s].indexOf(w.before), 0, w.id)
            else out[w.section].push(w.id)
        }
        return out
    }
    readonly property var defaultLayout: normalize(null)        // today's bar: workspaces left, the rest right

    // { default: layout, monitors: { key: layout } }, always normalized
    property var data: ({ default: defaultLayout, monitors: {} })

    function parse(raw) {
        if (!raw || typeof raw !== "object" || Array.isArray(raw)) return { default: defaultLayout, monitors: {} }
        if (raw.version === 2 || raw.default || raw.monitors) {
            const mons = {}
            if (raw.monitors && typeof raw.monitors === "object")
                for (const k in raw.monitors) mons[k] = normalize(raw.monitors[k])
            return { default: normalize(raw.default), monitors: mons }
        }
        // v1: { id: false } = hidden, everything else in its default place
        const d = normalize(null)
        for (const s of ["left", "center", "right"]) d[s] = d[s].filter(id => raw[id] !== false)
        d.hidden = widgets.filter(w => raw[w.id] === false).map(w => w.id)
        return { default: d, monitors: {} }
    }

    function keyOf(screen) { return BarConfig.keyOf(screen) }
    function hasOwn(key) { return data.monitors[key] !== undefined }
    function layoutFor(key) { return data.monitors[key] || data.default }

    // true while some bar that is actually showing has this widget (pollers like AiUsage / HomeAssistant idle otherwise)
    readonly property var shownIds: {
        const m = {}
        const add = l => { for (const s of ["left", "center", "right"]) for (const id of l[s]) m[id] = true }
        let any = false
        for (const s of Quickshell.screens) if (BarConfig.enabled(s)) { add(layoutFor(keyOf(s))); any = true }
        if (!any) add(data.default)
        return m
    }
    function shown(id) { return shownIds[id] === true }

    function sectionOf(l, id) { return sections.find(s => l[s].indexOf(id) >= 0) || "" }

    // Monitors linked in BarConfig (Settings > Bar) share one layout: a change to any of them is written to all of them
    // (also unplugged ones, so the group is still identical when they come back).
    function store(key, l) {
        const d = { default: data.default, monitors: Object.assign({}, data.monitors) }
        const n = l === null ? null : normalize(l)
        for (const k of BarConfig.groupKeys(key)) {
            if (n === null) delete d.monitors[k]; else d.monitors[k] = copy(n)
        }
        data = d
        saver.restart()
    }
    // a linked group takes `key`'s layout (used right after linking): its own, or the default one if it has none
    function syncGroup(key) { store(key, hasOwn(key) ? copy(layoutFor(key)) : null) }
    function copy(l) { return { left: l.left.slice(), center: l.center.slice(), right: l.right.slice(), hidden: l.hidden.slice() } }

    // put `id` into `section` at `index` (index counted in the list as it is before the move; -1 = end)
    function move(key, id, section, index) {
        if (sections.indexOf(section) < 0) return
        if (id === pinnedId && section === "hidden") return        // the way into Settings stays on the bar
        const l = copy(layoutFor(key))
        const from = sectionOf(l, id)
        if (!from) return
        const oldIdx = l[from].indexOf(id)
        l[from].splice(oldIdx, 1)
        let i = index < 0 || index === undefined ? l[section].length : index
        if (from === section && oldIdx < i) i--
        l[section].splice(Math.max(0, Math.min(i, l[section].length)), 0, id)
        store(key, l)
    }
    // reorder within its section by `delta` (-1 up / left, +1 down / right)
    function moveBy(key, id, delta) {
        const l = layoutFor(key)
        const s = sectionOf(l, id)
        const i = l[s].indexOf(id)
        const j = i + delta
        if (j < 0 || j >= l[s].length) return
        move(key, id, s, delta > 0 ? j + 1 : j)
    }
    // to the neighbouring section (left <-> center <-> right); hidden widgets come back in their default section
    function shift(key, id, dir) {
        const order = ["left", "center", "right"]
        const s = sectionOf(layoutFor(key), id)
        if (s === "hidden") { move(key, id, info(id).section, -1); return }
        const j = order.indexOf(s) + dir
        if (j >= 0 && j < order.length) move(key, id, order[j], dir > 0 ? 0 : -1)
    }
    function hide(key, id) { move(key, id, "hidden", -1) }
    function show(key, id) { if (sectionOf(layoutFor(key), id) === "hidden") move(key, id, info(id).section, -1) }
    function copyFrom(key, srcKey) { store(key, copy(layoutFor(srcKey))) }
    function reset(key) { store(key, null) }                         // back to the default layout

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])
    Timer {
        id: saver
        interval: 400
        onTriggered: file.setText(JSON.stringify({ version: 2, default: root.data.default, monitors: root.data.monitors }, null, 2))
    }

    FileView {
        id: file
        path: root.dir + "/bar-widgets.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.data = root.parse(JSON.parse(text())) }
            catch (e) { root.data = root.parse(null) }
        }
        onLoadFailed: root.data = root.parse(null)          // missing file: today's default bar
    }
}
