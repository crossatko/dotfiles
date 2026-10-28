pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Send to TV (TvCast): which TV (its Home Assistant entities) and how sending behaves. Saved in
// ${XDG_STATE_HOME:-~/.local/state}/quickshell/tv.json next to appearance.json (QS_TVCAST_FILE overrides the path), the
// LockPrefs / DeskClockPrefs pattern: a missing key = the default, this singleton is the only writer (debounced save).
//   tv            the TV: { name, entities: [{ id, adapter }] } (TvCast.tvGroups: one physical TV, its HA entities in
//                 adapter preference order); null = none. Written with `entity` = its first entity
//   entity        the TV's first entity id ("" = none: no button). A file with only `entity` (older) still works: TvCast
//                 sends to that entity and fills `tv` in once it has read HA's devices
//   pauseAfter    pause the player here once the TV opened it (default on)
//   autoDetect    show what the TV plays by itself (a remote, a phone's cast, its own app) as the TV card (TvSession; default on)
//   dryRun        log the calls (qs ipc call tvcast last) instead of sending them; default: on while no entity is set,
//                 off once one is (an explicit value always wins)
//   qs ipc call tvprefs get | set <key> <value> | unset <key> | reset
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_TVCAST_FILE")
        return env ? String(env) : Appearance.dir + "/tv.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    readonly property var spec: ({ tv: "tv", entity: "entity", pauseAfter: "bool", autoDetect: "bool", dryRun: "bool" })
    readonly property var keys: Object.keys(spec)
    function defaultOf(key) {
        if (key === "entity") return ""
        if (key === "tv") return null
        if (key === "pauseAfter") return true
        if (key === "autoDetect") return true
        if (key === "dryRun") return root.entity === ""
        return undefined
    }

    property var data: ({})
    function overridden(key) { return root.data[key] !== undefined }
    function value(key) { const v = root.data[key]; return v !== undefined ? v : root.defaultOf(key) }

    readonly property string entity: data.entity !== undefined ? data.entity : ""
    readonly property var tv: data.tv !== undefined ? data.tv : null
    readonly property string tvName: tv ? tv.name : ""
    readonly property bool pauseAfter: value("pauseAfter")
    readonly property bool autoDetect: value("autoDetect")
    readonly property bool dryRun: value("dryRun")

    function clean(key, v) {
        const s = spec[key]
        if (s === "bool") return typeof v === "boolean" ? v : undefined
        if (s === "entity") return typeof v === "string" && (v === "" || root.isEntity(v)) ? v : undefined
        if (s === "tv") {
            if (v === null || typeof v !== "object" || Array.isArray(v) || !Array.isArray(v.entities)) return undefined
            const ents = v.entities.filter(m => m && typeof m === "object" && root.isEntity(m.id) && typeof m.adapter === "string"
                                                  && /^[a-z_]{1,64}$/.test(m.adapter)).slice(0, 8).map(m => ({ id: m.id, adapter: m.adapter }))
            if (ents.length === 0) return undefined
            return { name: typeof v.name === "string" ? v.name.slice(0, 120) : "", entities: ents }
        }
        return undefined
    }
    function isEntity(v) { return typeof v === "string" && /^(remote|media_player)\.[a-z0-9_]{1,200}$/.test(v) }
    function parse(text) {
        const out = {}
        if (typeof text !== "string" || text.length > 8192) return out
        let o
        try { o = JSON.parse(text) } catch (e) { return out }
        if (o === null || typeof o !== "object" || Array.isArray(o)) return out
        for (const k of keys) {
            if (!Object.prototype.hasOwnProperty.call(o, k)) continue
            const v = clean(k, o[k])
            if (v !== undefined) out[k] = v
        }
        return out
    }
    function serialize(d) {
        const o = {}
        let any = false
        for (const k of keys) if (d[k] !== undefined) { if (!any) o.version = 1; o[k] = d[k]; any = true }
        return JSON.stringify(o) + "\n"
    }

    function set(key, v) {
        const c = clean(key, v)
        if (c === undefined || root.data[key] === c) return
        const d = Object.assign({}, root.data)
        if (key !== "dryRun" && c === root.defaultOf(key)) delete d[key]   // dryRun keeps an explicit choice (its default moves)
        else d[key] = c
        if (key === "entity" && d.tv && !d.tv.entities.some(m => m.id === c)) delete d.tv   // another entity: not that TV
        commit(d)
    }
    // pick a TV (a TvCast.candidates entry) or none (null): `tv` + `entity` in one save
    function setTv(t) {
        const c = t ? clean("tv", { name: t.name, entities: t.members || t.entities }) : undefined
        const d = Object.assign({}, root.data)
        if (c) { d.tv = c; d.entity = c.entities[0].id }
        else { delete d.tv; delete d.entity }
        if (serialize(d) !== serialize(root.data)) commit(d)
    }
    function unset(key) {
        if (root.data[key] === undefined) return
        const d = Object.assign({}, root.data)
        delete d[key]
        commit(d)
    }
    function reset() { commit({}) }
    function commit(d) {
        root.data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }
    property string lastText: ""
    Timer {
        id: saver
        interval: 300
        onTriggered: { const t = root.serialize(root.data); root.lastText = t; fileView.setText(t) }
    }
    function applyLoaded(t) {
        if (saver.running || t === root.lastText) return
        root.lastText = t
        const d = root.parse(t)
        if (root.serialize(d) !== root.serialize(root.data)) root.data = d
    }

    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: root.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyLoaded(text())
        onLoadFailed: root.applyLoaded("")
    }

    IpcHandler {
        target: "tvprefs"
        function get(): string { return root.serialize(root.data).trim() }
        function set(key: string, value: string): string {
            const s = root.spec[key]
            if (s === undefined) return "bad key"
            let v = value
            if (s === "bool") v = value === "true" ? true : value === "false" ? false : undefined
            else if (s === "tv") { try { v = JSON.parse(value) } catch (e) { v = undefined } }
            if (root.clean(key, v) === undefined) return "bad value"
            if (s === "tv") root.setTv(v)
            else root.set(key, v)
            return "ok"
        }
        function unset(key: string): string { root.unset(key); return "ok" }
        function reset(): string { root.reset(); return "ok" }
    }
}
