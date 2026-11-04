pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The dictation word lists (Settings > Voice): filler sounds to drop, per language, and replacements (heard -> typed,
// phrases allowed). Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/dictation-words.json (QS_DICTATION_WORDS_FILE
// overrides); this singleton is the only writer (atomic: temp file + rename), the file is watched (a hand edit shows
// here too) and the dictation service reads it at every key press, so an edit applies to the next dictation. Missing or
// malformed file = the defaults below (a bad field = that part's default, a bad entry is dropped); nothing is written
// until the user edits something.
//   { "version": 1,
//     "fillers": { "cs": ["ehm", ...], "en": ["um", ...] },
//     "replacements": [ { "heard": "century", "typed": "sentry", "lang": "any" } ],    lang: any | cs | en
//     "hints": false }
//   hints   a copy of dictation-prefs.json "prompt_hints" (DictationPrefs is the source of truth; this file is rewritten
//           whenever it changes, so the service finds both in step)
// The built-in fillers are the seed shown (and written on the first edit); conservative, never real words ("no", "tak").
// Entries are checked by checkFiller / checkReplacement before they are added: the Settings rows show the returned hint.
//   qs ipc call dictationwords get | reset
Singleton {
    id: dw

    readonly property string filePath: {
        const env = Quickshell.env("QS_DICTATION_WORDS_FILE")
        return env ? String(env) : Appearance.dir + "/dictation-words.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    readonly property var langs: ["cs", "en"]
    readonly property var replLangs: ["any", "cs", "en"]
    readonly property var replLabels: ["Any", "Czech", "English"]
    readonly property var defaultFillers: ({
        en: ["uh", "um", "uhm", "hmm", "er", "erm", "ah"],
        cs: ["ehm", "eh", "ee", "eee", "hm", "hmm", "mhm"]
    })
    readonly property int maxFillerLen: 24
    readonly property int maxFillers: 100
    readonly property int maxHeardLen: 60
    readonly property int maxTypedLen: 80
    readonly property int maxReplacements: 500

    property var fillers: copyFillers(defaultFillers)
    property var replacements: []
    readonly property bool hints: DictationPrefs.promptHints

    function copyFillers(f) { return { cs: f.cs.slice(), en: f.en.slice() } }
    function fillersOf(lang) { return fillers[lang] || [] }
    readonly property bool fillersCustom: langs.some(l => JSON.stringify(fillers[l]) !== JSON.stringify(defaultFillers[l]))
    readonly property bool changed: fillersCustom || replacements.length > 0

    // ---- checks (return { value, error }; error "" = fine) ----
    function squash(s) { return String(s).replace(/\s+/g, " ").trim() }
    function checkFiller(lang, text, list) {
        const v = squash(text).toLocaleLowerCase()
        const have = list || fillersOf(lang)
        if (langs.indexOf(lang) < 0) return { value: v, error: "Unknown language" }
        if (v === "") return { value: v, error: "Type a filler sound first" }
        if (v.indexOf(" ") >= 0) return { value: v, error: "One word only: use replacements for phrases" }
        if (v.length > maxFillerLen) return { value: v, error: "At most " + maxFillerLen + " characters" }
        if (!isFiller(v)) return { value: v, error: "Letters only" }
        if (have.indexOf(v) >= 0) return { value: v, error: "Already in the list" }
        if (have.length >= maxFillers) return { value: v, error: "The list is full (" + maxFillers + ")" }
        return { value: v, error: "" }
    }
    // letters (any alphabet with case: Czech diacritics included), then letters / ' / - / the typographic '
    function isFiller(v) {
        const letter = c => c.toLowerCase() !== c.toUpperCase()
        for (let i = 0; i < v.length; i++) {
            const c = v[i]
            if (!letter(c) && (i === 0 || "'\u2019-".indexOf(c) < 0)) return false
        }
        return v.length > 0
    }
    function sameHeard(a, b) { return a.toLocaleLowerCase() === b.toLocaleLowerCase() }
    // `skip` = the index being edited (it does not clash with itself)
    function checkReplacement(heard, typed, lang, skip, list) {
        const h = squash(heard), t = squash(typed)
        const have = list || replacements
        const out = e => ({ heard: h, typed: t, lang: lang, error: e })
        if (replLangs.indexOf(lang) < 0) return out("Unknown language")
        if (h === "") return out("Type what you say first")
        if (t === "") return out("Type the replacement first")
        if (h.length > maxHeardLen) return out("What you say: at most " + maxHeardLen + " characters")
        if (t.length > maxTypedLen) return out("Replacement: at most " + maxTypedLen + " characters")
        if (/[\u0000-\u001f\u007f]/.test(h + t)) return out("No control characters")
        if (h === t) return out("Nothing to change: both are the same")
        if (have.some((r, i) => i !== skip && r.lang === lang && sameHeard(r.heard, h))) return out("“" + h + "” is already replaced for this language")
        if (skip === undefined || skip < 0) { if (have.length >= maxReplacements) return out("The list is full (" + maxReplacements + ")") }
        return out("")
    }

    // ---- edits ("" = done, else the hint) ----
    function addFiller(lang, text) {
        const c = checkFiller(lang, text)
        if (c.error !== "") return c.error
        const f = copyFillers(fillers)
        f[lang].push(c.value)
        fillers = f
        save()
        return ""
    }
    function removeFiller(lang, word) {
        const f = copyFillers(fillers)
        f[lang] = f[lang].filter(w => w !== word)
        fillers = f
        save()
    }
    function restoreFillers() { fillers = copyFillers(defaultFillers); save() }
    function addReplacement(heard, typed, lang) {
        const c = checkReplacement(heard, typed, lang)
        if (c.error !== "") return c.error
        replacements = replacements.concat([{ heard: c.heard, typed: c.typed, lang: lang }])
        save()
        return ""
    }
    function updateReplacement(i, heard, typed, lang) {
        if (i < 0 || i >= replacements.length) return "Gone"
        const c = checkReplacement(heard, typed, lang, i)
        if (c.error !== "") return c.error
        const r = replacements.slice()
        r[i] = { heard: c.heard, typed: c.typed, lang: lang }
        replacements = r
        save()
        return ""
    }
    function removeReplacement(i) {
        replacements = replacements.filter((r, j) => j !== i)
        save()
    }
    function resetAll() {
        fillers = copyFillers(defaultFillers)
        replacements = []
        save()
    }

    // ---- file ----
    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const d = o !== null && typeof o === "object" && !Array.isArray(o) ? o : {}
        const f = copyFillers(defaultFillers)
        if (d.fillers && typeof d.fillers === "object") {
            for (const l of langs) {
                if (!Array.isArray(d.fillers[l])) continue
                const list = []
                for (const w of d.fillers[l]) {
                    if (typeof w !== "string") continue
                    const c = checkFiller(l, w, list)
                    if (c.error === "") list.push(c.value)
                }
                f[l] = list
            }
        }
        fillers = f
        const rs = []
        if (Array.isArray(d.replacements)) {
            for (const r of d.replacements) {
                if (!r || typeof r.heard !== "string" || typeof r.typed !== "string") continue
                const lang = typeof r.lang === "string" ? r.lang : "any"
                const c = checkReplacement(r.heard, r.typed, lang, undefined, rs)
                if (c.error === "") rs.push({ heard: c.heard, typed: c.typed, lang: lang })
            }
        }
        replacements = rs
        fileHints = typeof d.hints === "boolean" ? d.hints : null
    }
    property var fileHints: null
    function serialize() {
        return JSON.stringify({ version: 1, fillers: fillers, replacements: replacements, hints: hints }) + "\n"
    }
    property string lastText: ""
    property bool _dirtyHints: false
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
    // the hints switch (DictationPrefs) changed (or differs from the file's copy at load): keep this file in step
    onHintsChanged: if (loadedOnce && serialize() !== lastText) save()

    property bool loadedOnce: false
    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: dw.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            if (!saver.running && !writer.running && text() !== dw.lastText) { dw.parse(text()); dw.lastText = text() }
            dw.loadedOnce = true
            if (dw.fileHints !== null && dw.fileHints !== dw.hints) dw.save()
        }
        onLoadFailed: {
            if (!saver.running && !writer.running) dw.parse("")
            dw.loadedOnce = true
        }
    }

    IpcHandler {
        target: "dictationwords"
        function get(): string { return dw.serialize().trim() }
        function reset(): string { dw.resetAll(); return "ok" }
    }
}
