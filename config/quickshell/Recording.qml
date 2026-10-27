pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen recording (~/.config/hypr/scripts/screenrec.sh, SHIFT+Print & co.): the script writes key=value
// lines (pid, comm, started, file, mode, audio) to $XDG_RUNTIME_DIR/screenrec/state while its recorder runs
// and removes the file when it exits. Polled once a second (the file comes and goes, so a watch alone
// misses its creation) while a recording chip is in a bar layout, one poller for all bars; the recorder's
// /proc/<pid>/comm is checked too, so a recorder that died without its wrapper cleaning up doesn't leave
// the chip on. SCREENREC_RUNTIME_DIR = the script's test override.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/screenrec.sh"
    readonly property string dir: Quickshell.env("SCREENREC_RUNTIME_DIR") || (Quickshell.env("XDG_RUNTIME_DIR") + "/screenrec")
    property var state: null                 // parsed state file, null = no recording
    property bool alive: false
    readonly property bool recording: state !== null && alive
    property double clock: Date.now()
    readonly property string elapsed: {
        if (!recording) return ""
        const s = Math.max(0, Math.floor(clock / 1000) - (parseInt(state.started) || 0))
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0")
    }
    Timer {
        interval: 1000; running: BarWidgets.shown("recording"); repeat: true
        onTriggered: { stateFile.reload(); if (root.state) comm.reload(); root.clock = Date.now() }
    }
    FileView {
        id: stateFile
        path: root.dir + "/state"
        printErrors: false
        onLoaded: {
            const o = {}
            for (const l of text().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1) }
            root.state = o.pid ? o : null
        }
        onLoadFailed: root.state = null
    }
    FileView {
        id: comm
        path: root.state ? "/proc/" + root.state.pid + "/comm" : ""
        printErrors: false
        onLoaded: root.alive = root.state !== null && text().trim() === root.state.comm
        onLoadFailed: root.alive = false
    }
}
