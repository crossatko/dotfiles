pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bitcoin price (bar chip). bin/btc (Python, CoinGecko, keyless) gives price and 24 h change; polled every minute only
// while the chip is shown, never otherwise. A failed poll (offline, rate limit) keeps the last answer, shown muted.
// QS_BTC_HELPER overrides the script (tests; the helper itself takes QS_BTC_MOCK).
// Quote currency: ${XDG_STATE_HOME:-~/.local/state}/quickshell/btc.json (QS_BTC_FILE overrides), read once at start,
// hand-edited, no Settings row:  { "currency": "USD" }   (any CoinGecko vs_currency: EUR, GBP, ...)
Singleton {
    id: btc

    readonly property string script: Quickshell.env("QS_BTC_HELPER") || (Quickshell.shellDir + "/bin/btc")
    readonly property string filePath: {
        const env = Quickshell.env("QS_BTC_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/quickshell/btc.json"
    }

    property string currency: "USD"
    property var data: null                  // the last good answer
    property bool failing: false             // the latest poll failed (data, if any, is old)
    property string error: ""
    readonly property bool has: data !== null
    readonly property bool stale: has && failing
    readonly property string label: has ? String(data.label) : "–"
    readonly property real changePct: has && typeof data.changePct === "number" ? data.changePct : 0
    readonly property bool up: changePct >= 0

    readonly property int pollMs: 60000
    readonly property bool chipShown: BarWidgets.shown("btc")

    function refresh() {
        if (proc.running) return
        proc.command = ["python3", "-I", script, "--currency", currency]
        proc.running = true
    }

    Component.onCompleted: { fileView.text(); if (chipShown) refresh() }   // singletons load lazily: with the chip shown this is its first moment
    FileView {
        id: fileView
        path: btc.filePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text()).currency
                if (typeof c === "string" && /^[A-Za-z]{2,10}$/.test(c)) btc.currency = c.toUpperCase()
            } catch (e) {}
        }
    }

    onChipShownChanged: if (chipShown) refresh()
    Timer { interval: btc.pollMs; repeat: true; running: btc.chipShown; onTriggered: btc.refresh() }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.ok === true) { btc.data = d; btc.failing = false; btc.error = "" }
                    else { btc.failing = true; btc.error = String(d.error || "failed") }
                } catch (e) {
                    btc.failing = true
                    btc.error = "btc helper failed"
                }
            }
        }
    }

    IpcHandler {
        target: "btc"
        function get(): string { return JSON.stringify({ label: btc.label, changePct: btc.changePct, stale: btc.stale, error: btc.error, currency: btc.currency }) }
        function refresh(): void { btc.refresh() }
    }
}
