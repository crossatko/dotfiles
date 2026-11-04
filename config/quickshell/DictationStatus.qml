pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Dictation status record: the LAST error of the dictation pill / service, persisted for the Voice settings page (the pill
// itself only says "An error occurred"). This singleton is the one reader and writer of
// dictation-last-error.json next to appearance.json (QS_DICTATION_ERROR_FILE overrides the path), written atomically;
// VoiceLastError shows `lastError`. Schema (readers may rely on exactly these keys):
//   { "time": "<ISO 8601 local time with offset>", "message": "<detail text>", "code": "<short code or empty>",
//     "count": <errors since the last clear> }
// No file, cleared, malformed or no message = no error recorded (`lastError` null). The file is watched; `reload()`
// re-reads it (a writer that replaces or deletes the file can drop the watch).
//   qs ipc call dictation-status last (prints the JSON, "{}" when none) | clear
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_DICTATION_ERROR_FILE")
        return env ? String(env) : Appearance.dir + "/dictation-last-error.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    property var lastError: null

    // local time with its UTC offset, e.g. 2026-11-04T03:41:07+01:00
    function isoLocal(d) {
        const p = n => String(n).padStart(2, "0")
        const off = -d.getTimezoneOffset(), a = Math.abs(off)
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "T" + p(d.getHours()) + ":" + p(d.getMinutes())
            + ":" + p(d.getSeconds()) + (off >= 0 ? "+" : "-") + p(Math.floor(a / 60)) + ":" + p(a % 60)
    }
    function record(message, code) {
        const prev = root.lastError
        root.lastError = { time: isoLocal(new Date()), message: String(message ?? ""), code: String(code ?? ""),
                           count: (prev && Number.isInteger(prev.count) ? prev.count : 0) + 1 }
        Quickshell.execDetached(["mkdir", "-p", root.dir])
        fileView.setText(JSON.stringify(root.lastError) + "\n")
    }
    function clear() {
        root.lastError = null
        fileView.setText("{}\n")
    }
    function reload() { fileView.reload() }
    // file text -> { time (ISO string or ""), message, code, count } or null
    function parse(t) {
        if (typeof t !== "string" || t.trim() === "" || t.length > 65536) return null
        let j
        try { j = JSON.parse(t) } catch (e) { return null }
        if (!j || typeof j !== "object" || Array.isArray(j) || typeof j.message !== "string" || j.message.trim() === "") return null
        const n = Number(j.count)
        return { time: typeof j.time === "string" ? j.time : "", message: j.message.trim(),
                 code: typeof j.code === "string" ? j.code.trim() : "", count: Number.isInteger(n) && n > 0 ? n : 1 }
    }

    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: root.filePath
        blockLoading: true
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lastError = root.parse(text())
        onLoadFailed: root.lastError = null
    }

    IpcHandler {
        target: "dictation-status"
        function last(): string { return root.lastError ? JSON.stringify(root.lastError) : "{}" }
        function clear(): void { root.clear() }
    }
}
