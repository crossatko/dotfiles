pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The GPUs the dictation worker can run on: `dictation-whisper --list-devices` (one JSON line per GPU
// {index, name, type: discrete|integrated, free_mb, total_mb}), read once and cached; refresh() tries again while the last
// try failed. `state`: "idle" (not asked yet) | "loading" | "ok" | "unavailable" (worker missing, not executable or built before
// --list-devices, or it listed nothing). The index is what DictationPrefs.gpuDevice stores and the service passes to the worker.
//   qs ipc call gpudevices get | refresh
Singleton {
    id: gd

    // test hook QS_DICTATION_WORKER; else as the service: DICTATION_WORKER, else the build.sh output
    readonly property string worker: {
        const own = Quickshell.env("QS_DICTATION_WORKER") || Quickshell.env("DICTATION_WORKER")
        if (own) return String(own)
        const data = Quickshell.env("XDG_DATA_HOME")
        return (data ? String(data) : String(Quickshell.env("HOME")) + "/.local/share") + "/dictation/bin/dictation-whisper"
    }

    property string state: "idle"
    property var devices: []           // [{ index, name, type, freeMb, totalMb }]
    property var lines: []

    function refresh() {
        if (proc.running || state === "ok") return
        state = "loading"
        lines = []
        proc.running = true
    }
    function byIndex(i) { return devices.find(d => d.index === i) ?? null }

    function finish() {
        if (state !== "loading") return
        const out = []
        for (const l of lines) {
            try {
                const o = JSON.parse(l)
                if (Number.isInteger(o.index) && typeof o.name === "string")
                    out.push({ index: o.index, name: o.name, type: o.type === "integrated" ? "integrated" : "discrete",
                               freeMb: Number(o.free_mb) || 0, totalMb: Number(o.total_mb) || 0 })
            } catch (e) {}
        }
        devices = out
        state = out.length > 0 ? "ok" : "unavailable"
    }

    Process {
        id: proc
        command: [gd.worker, "--list-devices"]
        stdout: SplitParser { onRead: line => gd.lines = gd.lines.concat([line]) }
        onExited: gd.finish()
        onRunningChanged: if (!running) Qt.callLater(gd.finish)   // a binary that cannot start never exits normally
    }

    IpcHandler {
        target: "gpudevices"
        function get(): string { return JSON.stringify({ state: gd.state, devices: gd.devices }) }
        function refresh(): string { gd.refresh(); return gd.state }
    }
}
