pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The diacritics corrections (Settings > Diacritics): misses the user recorded, typed -> correct (a word or a short
// phrase each). Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics-words.json (QS_DIACRITICS_WORDS_FILE
// overrides); this singleton is the only writer (atomic: temp file + rename), the file is watched (a hand edit shows
// here too) and the diacritics service reads it at every run, so an edit applies to the next run. Missing or malformed
// file = no entries; nothing is written until the user edits something.
//   { "entries": [ { "typed": "Zorvelka", "correct": "Zorvelká", "always": false } ] }
//   always   false = the entry is only a hint for the model; true = it is also replaced after the model
// Entries are checked by check() before they are added: the Settings rows show the returned hint.
//   qs ipc call diacriticswords get | reset
Singleton {
    id: dw

    readonly property string filePath: {
        const env = Quickshell.env("QS_DIACRITICS_WORDS_FILE")
        return env ? String(env) : Appearance.dir + "/diacritics-words.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    readonly property int maxLen: 80
    readonly property int maxEntries: 500

    property var entries: []
    readonly property bool changed: entries.length > 0

    function squash(s) { return String(s).replace(/\s+/g, " ").trim() }
    function same(a, b) { return a.toLocaleLowerCase() === b.toLocaleLowerCase() }
    function indexOfTyped(typed, skip, list) {
        const have = list || entries
        return have.findIndex((e, i) => i !== skip && same(e.typed, typed))
    }
    // { typed, correct, always, error }; `skip` = the index being edited (it does not clash with itself)
    function check(typed, correct, always, skip, list) {
        const t = squash(typed), c = squash(correct)
        const have = list || entries
        const out = e => ({ typed: t, correct: c, always: !!always, error: e })
        if (t === "") return out("Type the word as it came out first")
        if (c === "") return out("Type the correct word first")
        if (t.length > maxLen || c.length > maxLen) return out("At most " + maxLen + " characters")
        if (/[\u0000-\u001f\u007f]/.test(t + c)) return out("No control characters")
        if (t === c) return out("Nothing to change: both are the same")
        if (indexOfTyped(t, skip, have) >= 0) return out("“" + t + "” is already in the list")
        if ((skip === undefined || skip < 0) && have.length >= maxEntries) return out("The list is full (" + maxEntries + ")")
        return out("")
    }

    // ---- edits ("" = done, else the hint) ----
    // a typed word that is already listed updates that entry instead of adding a second one
    function add(typed, correct, always) {
        const i = indexOfTyped(squash(typed), -1)
        if (i >= 0) return update(i, typed, correct, always)
        const c = check(typed, correct, always)
        if (c.error !== "") return c.error
        entries = entries.concat([{ typed: c.typed, correct: c.correct, always: c.always }])
        save()
        return ""
    }
    function update(i, typed, correct, always) {
        if (i < 0 || i >= entries.length) return "Gone"
        const c = check(typed, correct, always, i)
        if (c.error !== "") return c.error
        const r = entries.slice()
        r[i] = { typed: c.typed, correct: c.correct, always: c.always }
        entries = r
        save()
        return ""
    }
    function remove(i) { entries = entries.filter((e, j) => j !== i); save() }
    function resetAll() { entries = []; save() }

    // ---- file ----
    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const list = o !== null && typeof o === "object" && Array.isArray(o.entries) ? o.entries : []
        const out = []
        for (const e of list) {
            if (!e || typeof e.typed !== "string" || typeof e.correct !== "string") continue
            const c = check(e.typed, e.correct, e.always === true, undefined, out)
            if (c.error === "") out.push({ typed: c.typed, correct: c.correct, always: c.always })
        }
        entries = out
    }
    function serialize() { return JSON.stringify({ entries: entries }) + "\n" }
    property string lastText: ""
    function save() { saver.restart() }
    Timer {
        id: saver
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", dw.dir])
            writer.restart()
        }
    }
    // mkdir runs detached: a moment before the write
    Timer {
        id: writer
        interval: 150
        onTriggered: { dw.lastText = dw.serialize(); fileView.setText(dw.lastText) }
    }

    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: dw.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: if (!saver.running && !writer.running && text() !== dw.lastText) { dw.parse(text()); dw.lastText = text() }
        onLoadFailed: if (!saver.running && !writer.running) dw.parse("")
    }

    IpcHandler {
        target: "diacriticswords"
        function get(): string { return dw.serialize().trim() }
        function reset(): string { dw.resetAll(); return "ok" }
    }
}
