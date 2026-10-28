pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The desktop wallpaper of each monitor as theme.py resolves it: the one source for the shell's wallpaper layer
// (WallpaperLayer) and for anything that needs "what does this monitor show" (LockWallpapers.stillFor delegates here).
// theme.py writes ~/.config/theme/out/wallpaper.json together with out/hyprpaper.conf (same blocks, theme.py
// write_wallpaper_json) on every apply / link / primary / clear / render, in the click's foreground:
//   { "version": 1, "backend": "quickshell" | "hyprpaper" | "engine",
//     "rules": [ { "monitor": "" | "<connector>" | "desc:<description prefix>", "path": "<absolute image>",
//                  "fit": "cover" | "contain" | "fill" | "tile", "w": px, "h": px (the file's own size, when known),
//                  "pending": true (file not there yet) } ] }
// Primary / links / "Follow primary" and machine-local blocks are already resolved into the rules by theme.py. A monitor
// takes the first rule naming its connector or whose desc: prefix starts its key (Appearance.monitorKey), else the
// last catch-all (monitor ""): theme.py hyprpaper_wanted. A video wallpaper's rule is its still (mpvpaper plays above).
// No file yet (a seeded out/, before the first theme.py render / apply) = the layer draws nothing and pathFor gives
// Theme.wallpaper, cover. backend "hyprpaper" = the shell draws nothing either (`drawn` false). QS_WALLPAPER_FILE overrides the path (tests).
// `qs ipc call wallpaper reload | status` (status: one line per screen: connector, wanted file, shown file, state).
Singleton {
    id: root

    readonly property string filePath: Quickshell.env("QS_WALLPAPER_FILE") || Theme.themeDir + "/out/wallpaper.json"
    property var rules: []
    property bool found: false                 // the file was read (else: Theme.wallpaper fallback)
    property string backend: "quickshell"
    // the shell draws only once theme.py has written the file (before that the hyprpaper era: hyprpaper's own config)
    readonly property bool drawn: found && backend === "quickshell"
    // backend "engine": the wallpaper engine (engine.qml, its own Quickshell instance) draws the wallpaper, videos and the
    // desktop clock; the main shell draws neither (WallpaperLayer: `drawn` false, DeskClock off)
    readonly property bool engine: found && backend === "engine"
    property int gen: 0                        // bumped by `reload`: layers re-load what they show

    function home(p) { return typeof p === "string" ? p.replace(/^~(?=\/|$)/, Theme.home) : "" }
    function fallback() { return { path: home(Theme.wallpaper), fit: "cover", w: 0, h: 0, pending: false } }

    // { path, fit, w, h, pending } for a ShellScreen (w / h 0 = unknown)
    function entryFor(screen) {
        if (!found || !screen) return fallback()
        const conn = screen.name ? String(screen.name) : ""
        const key = Appearance.monitorKey(screen)
        let hit = null, any = null
        for (const r of rules) {
            const m = r.monitor
            if (m === "") { any = r; continue }
            if (!hit && (m === conn || (m.startsWith("desc:") && m.length > 5 && key.startsWith(m.slice(5).trim())))) hit = r
        }
        const r = hit || any
        return r ? { path: r.path, fit: r.fit, w: r.w, h: r.h, pending: r.pending } : fallback()
    }
    // the still / image a consumer should use (lock, desktop clock, bar contrast, Settings thumbnails): while the entry is
    // `pending` (a new video's still not extracted yet) the one the layer still shows, so nobody loads a missing file and
    // gets stuck on the error; when theme.py drops the flag every consumer switches (a changed path: a re-sample / reload)
    function pathFor(screen) {
        const e = entryFor(screen)
        if (!e.pending || !screen) return e.path
        const r = shown[screen.name]
        return r && r.shown ? r.shown : e.path
    }

    function parse(text) {
        let j = null
        try { j = JSON.parse(text) } catch (e) { j = null }
        if (!j || typeof j !== "object" || !Array.isArray(j.rules)) { root.found = false; root.rules = []; return }
        const fits = ["cover", "contain", "fill", "tile"]
        root.rules = j.rules.filter(r => r && typeof r.path === "string" && r.path !== "").map(r => ({
            monitor: typeof r.monitor === "string" ? r.monitor.trim() : "",
            path: root.home(r.path),
            fit: fits.indexOf(r.fit) >= 0 ? r.fit : "cover",
            w: Number.isInteger(r.w) && r.w > 0 ? r.w : 0,
            h: Number.isInteger(r.h) && r.h > 0 ? r.h : 0,
            pending: r.pending === true
        }))
        root.backend = j.backend === "hyprpaper" || j.backend === "engine" ? j.backend : "quickshell"
        root.found = true
    }

    // what each layer shows (WallpaperLayer reports it; status / tests): connector -> { want, shown, state }
    property var shown: ({})
    function report(conn, want, shownPath, state) {
        const m = Object.assign({}, root.shown)
        m[conn] = { want: want, shown: shownPath, state: state }
        root.shown = m
    }

    // first read is synchronous: the layer's first frame is already the right image (no black / wrong-image start)
    Component.onCompleted: file.text()
    FileView {
        id: file
        path: root.filePath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: { root.found = false; root.rules = [] }
    }

    IpcHandler {
        target: "wallpaper"
        function reload(): void { file.reload(); root.gen += 1 }
        function status(): string {
            const base = p => p ? p.substring(p.lastIndexOf("/") + 1) : "-"
            return Quickshell.screens.filter(s => s && s.name).map(s => {
                const e = root.entryFor(s), r = root.shown[s.name] || {}
                return s.name + " " + base(e.path) + (e.pending ? " (pending)" : "") + " shown=" + base(r.shown) + " " + (r.state || (root.drawn ? "none" : "off"))
            }).join("\n")
        }
    }
}
