pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / memory percentages with sparkline history and the bar clock, shared by every bar: one set of timers however many
// screens there are, each running only while its chip is in a bar layout (BarWidgets.shown). Pure QML (FileView on procfs +
// Timer), no child processes (a shell loop in a Process orphans to systemd when qs exits).
Singleton {
    id: root

    property string cpu: "0%"
    property string mem: "0%"
    property var cpuHist: []                 // last histN samples, 0..100
    property var memHist: []
    readonly property int histN: 14

    // reserve the width of the widest value / full graph so chips never resize as numbers or history change
    readonly property real pctWidth: pctMetrics.width
    readonly property real sparkWidth: sparkMetrics.width
    TextMetrics { id: pctMetrics; text: "100%"; font.family: Theme.font; font.pixelSize: Theme.fontSize }
    TextMetrics { id: sparkMetrics; text: "▁".repeat(root.histN); font.family: Theme.font; font.pixelSize: Theme.fontSize }

    function pushSample(arr, v) {
        const a = arr.concat([v])
        return a.length > histN ? a.slice(a.length - histN) : a
    }
    // ▁▂▃▄▅▆▇█ sparkline. floor = smallest top-of-scale, so an idle CPU stays a flat low line instead of
    // being stretched to full height; memory passes a `lo` (its own minimum) since its changes are tiny.
    function spark(arr, floorSpan, useMin) {
        const blocks = "▁▂▃▄▅▆▇█"
        const hi0 = Math.max.apply(null, arr)
        const lo = useMin ? Math.min.apply(null, arr) : 0
        const span = Math.max(floorSpan, hi0 - lo)
        let s = " ".repeat(histN - arr.length)        // not enough history yet: pad on the left, graph grows in from the right
        for (const v of arr) s += blocks[Math.max(0, Math.min(7, Math.floor((v - lo) / span * 7.999)))]
        return s
    }
    readonly property string cpuSpark: spark(cpuHist, 25, false)
    readonly property string memSpark: spark(memHist, 10, true)

    // CPU needs the PREVIOUS /proc/stat sample for a percentage.
    property real cpuPrevBusy: 0
    property real cpuPrevTot: 0
    Timer {
        interval: 2000; running: BarWidgets.shown("cpu"); repeat: true; triggeredOnStart: true
        onTriggered: statFile.reload()
    }
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const a = text().split("\n")[0].trim().split(/\s+/).map(Number)   // cpu user nice system idle iowait irq softirq steal
            const busy = a[1] + a[2] + a[3]
            const tot = busy + a[4] + a[5] + a[6] + a[7] + a[8]
            if (root.cpuPrevTot > 0 && tot > root.cpuPrevTot) {
                const v = Math.trunc((busy - root.cpuPrevBusy) * 100 / (tot - root.cpuPrevTot))
                root.cpu = v + "%"
                root.cpuHist = root.pushSample(root.cpuHist, v)
            }
            root.cpuPrevBusy = busy
            root.cpuPrevTot = tot
        }
    }
    Timer {
        interval: 3000; running: BarWidgets.shown("memory"); repeat: true; triggeredOnStart: true
        onTriggered: memFile.reload()
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const t = text()
            const total = parseInt((t.match(/MemTotal:\s+(\d+)/) || [])[1])
            const avail = parseInt((t.match(/MemAvailable:\s+(\d+)/) || [])[1])
            if (total > 0 && avail >= 0) {
                const v = Math.trunc((total - avail) * 100 / total)
                root.mem = v + "%"
                root.memHist = root.pushSample(root.memHist, v)
            }
        }
    }

    // The bar clock, one timer for all bars (running only while a clock chip is in a layout). Not SystemClock: it re-arms a
    // QTimer with a negative interval during the repeated local hour at the end of DST (fires every 1 ms, ~2000 warnings/s, ~9% CPU)
    property date clockNow: new Date()
    Timer {
        interval: 5000; running: BarWidgets.shown("clock"); repeat: true
        onRunningChanged: if (running) root.clockNow = new Date()
        onTriggered: root.clockNow = new Date()
    }
}
