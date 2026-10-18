pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// AI accounts and their usage limits (AI chip + AiPanel). All the work happens in bin/ai-usage (Python):
// it finds the Claude Code profiles (~/.claude*, one per CLAUDE_CONFIG_DIR), reads plan / account, asks the
// usage endpoint (GET api.anthropic.com/api/oauth/usage: UNOFFICIAL, what Claude Code's /usage uses, may
// change or vanish without notice), caches answers ~60 s, backs off on 429 / offline, never refreshes tokens,
// and falls back to local estimates from the session logs. Tokens never pass through QML.
// Runs: on popup open (rescan), every 3 min while open, every 10 min for the chip, never while the chip is
// hidden and the popup closed. QS_AI_HELPER overrides the script (tests).
Singleton {
    id: ai

    readonly property string script: Quickshell.env("QS_AI_HELPER") || (Quickshell.shellDir + "/bin/ai-usage")

    property var profiles: []
    property var others: []
    property bool loaded: false
    property bool loading: proc.running
    property string error: ""                // helper failed / printed garbage (the previous data stays)
    property double generatedAt: 0
    property double now: Date.now()          // ticks for the "resets in" countdowns

    readonly property bool panelOpen: Popups.name === "ai"
    readonly property bool chipShown: BarWidgets.shown("ai")

    // highest percent of any limit window (all Claude profiles + other tools); -1 = nothing known
    readonly property real worst: {
        let m = -1
        for (const p of profiles.concat(others))
            for (const w of (p.windows || []))
                if (typeof w.percent === "number") m = Math.max(m, w.percent)
        return m
    }
    // the bar chip's account: the most recently used one (lastUsed = newest session log) whose values are fresh
    // (stale = expired / lapsed token, rate limited, offline, error, or older than 15 min); when none is fresh,
    // the most recently used one that has values, shown dimmed. Accounts without limit windows are skipped.
    readonly property var current: {
        const c = profiles.concat(others).filter(p => (p.windows || []).some(w => typeof w.percent === "number"))
        c.sort((a, b) => (b.lastUsed || 0) - (a.lastUsed || 0))
        return c.find(p => p.stale !== true) || c[0] || null
    }
    readonly property real currentPercent: current
        ? Math.max(...current.windows.filter(w => typeof w.percent === "number").map(w => w.percent)) : -1
    readonly property bool currentStale: current !== null && current.stale === true
    readonly property bool anyExpired: profiles.some(p => p.status === "expired")

    property bool _again: false
    function refresh(force) {
        if (proc.running) { if (force) _again = true; return }
        proc.command = ["python3", "-I", script].concat(force ? ["--force"] : [])
        proc.running = true
    }

    // "2h 14m", "3d 5h", "12m", "now"
    function until(epochSec) {
        if (!epochSec) return ""
        const s = Math.max(0, epochSec - now / 1000)
        if (s < 60) return "now"
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m"
    }
    function ago(epochSec) {
        if (!epochSec) return ""
        const s = Math.max(0, now / 1000 - epochSec)
        return s < 90 ? "just now" : s < 5400 ? Math.round(s / 60) + " min ago" : s < 172800 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago"
    }
    function compact(n) {
        return n >= 1e9 ? (n / 1e9).toFixed(1) + "B" : n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e4 ? Math.round(n / 1e3) + "k" : n >= 1e3 ? (n / 1e3).toFixed(1) + "k" : String(n)
    }
    // calm grey normally (the accent can itself be red with some wallpapers), orange from 80 %, red from 90 %
    function levelColor(pct) { return pct >= 90 ? Theme.red : pct >= 80 ? Theme.orange : Theme.fgDim }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    ai.profiles = Array.isArray(d.profiles) ? d.profiles : []
                    ai.others = Array.isArray(d.others) ? d.others : []
                    ai.generatedAt = d.generatedAt || 0
                    ai.error = ""
                    ai.loaded = true
                } catch (e) {
                    ai.error = "ai-usage helper failed"
                }
                ai.now = Date.now()
            }
        }
        onExited: if (ai._again) { ai._again = false; ai.refresh(true) }
    }

    onPanelOpenChanged: if (panelOpen) refresh(false)        // rescan the profiles on every open (cache keeps it cheap)
    Component.onCompleted: if (chipShown) starter.start()
    onChipShownChanged: if (chipShown) refresh(false)
    Timer { id: starter; interval: 6000; onTriggered: ai.refresh(false) }   // after login, not in the startup rush

    // 3 min while open or while a limit is >= 80 % (the chip should catch the crossing), else 10 min
    Timer {
        interval: ai.panelOpen || ai.worst >= 80 ? 180000 : 600000
        repeat: true
        running: ai.panelOpen || ai.chipShown
        onTriggered: ai.refresh(false)
    }
    // offline right after login (network not up yet): one sooner try instead of waiting out the interval
    Timer {
        interval: 150000
        running: (ai.panelOpen || ai.chipShown) && ai.profiles.some(p => p.status === "offline")
        onTriggered: ai.refresh(false)
    }
    Timer {
        interval: 30000
        repeat: true
        running: ai.panelOpen || ai.chipShown
        triggeredOnStart: true
        onTriggered: ai.now = Date.now()
    }
}
