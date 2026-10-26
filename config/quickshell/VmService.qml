pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Virtual machines for the bar chip and its popup (VmChip in Bar.qml, VmPanel.qml). Data comes from one cheap
// `vm-ctl status DIR` call (launcher/bin/vm-ctl): the running quickemu VMs (qemu PID from <vm>.pid, RSS, CPU ticks,
// configured RAM / cores, uptime) and the background download jobs (`vm-ctl create-bg`, one JSON file each in
// $XDG_RUNTIME_DIR/launcher-vm/jobs). Polling only runs while a bar shows the "vm" widget: a slow scan while there is
// nothing to track, faster while a job runs, the panel is open or VMs are running.
// Env hooks: LAUNCHER_VM_DIR (VM folder, same as the launcher), QS_VM_STATE (job folder, tests).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string cfgDir: ""                       // ~/.config/launcher/config.json "vmDir"
    readonly property string dir: {
        const e = Quickshell.env("LAUNCHER_VM_DIR")
        const d = e ? String(e) : cfgDir !== "" ? cfgDir : "~/VMs"
        return d.replace(/^~(?=\/|$)/, home).replace(/\/+$/, "")
    }
    readonly property string helper: String(Qt.resolvedUrl("launcher/bin/vm-ctl")).replace(/^file:\/\//, "")
    readonly property string stateDir: Quickshell.env("QS_VM_STATE") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/launcher-vm")

    property var vms: []                             // [{name, pid, cpu (%), rss, ram, cores, uptime, monitor, ...}]
    property var jobs: []                            // [{id, label, state running|done|failed|cancelled, phase, pct (-1 unknown), speed, eta, bytes, total, error}]
    property bool panelOpen: false                   // VmPanel is showing: faster sampling
    property bool launcherOpen: false                // launcher shows the VM section (set by Launcher): jobs poll at 1 s there even without the chip
    // jobs just started here that the status feed does not list yet (the runner takes a moment to write its job file): key -> expiry ms
    property var starting: ({})
    // one entry per target (label): its running job, else the latest finished one; a just-started target is listed as "Starting"
    // until the runner's job file shows up. The panel keys its delegates by label, so Starting -> real job keeps the same row.
    readonly property var allJobs: {
        const by = {}
        for (const j of jobs) {
            const b = by[j.label]
            if (!b || j.state === "running" || (b.state !== "running" && j.started >= b.started)) by[j.label] = j
        }
        for (const k in starting)
            if (!by[k] || by[k].state !== "running")
                by[k] = { id: "starting:" + k, label: k, state: "running", phase: "Starting", pct: -1, speed: 0, eta: -1, bytes: 0, total: 0, name: "", error: "",
                          started: starting[k].t }
        return Object.keys(by).map(k => Object.assign({}, by[k], { detail: jobDetail(by[k]) }))
    }
    // Stable models for the panel's Repeaters: the id / name lists change only when a job or VM appears or goes, never on
    // a progress update, so the delegates live on and their bars keep their value (a new `jobs` array every second
    // would rebuild every delegate and restart its animation from 0).
    property var jobIds: []
    property var vmNames: []
    onAllJobsChanged: { const ids = allJobs.map(j => j.label); if (JSON.stringify(ids) !== JSON.stringify(jobIds)) jobIds = ids }
    onVmsChanged: { const n = vms.map(v => v.name); if (JSON.stringify(n) !== JSON.stringify(vmNames)) vmNames = n }
    function jobByKey(k) { return allJobs.find(j => j.label === k) || null }
    function vmByName(n) { return vms.find(v => v.name === n) || null }
    readonly property bool busy: vms.length > 0 || allJobs.length > 0     // the chip shows only then
    readonly property var runningJobs: allJobs.filter(j => j.state === "running")
    // the job of one target ("os release [edition]"): a running one first, else the latest finished one, else null
    function jobFor(key) {
        let best = null
        for (const j of allJobs) if (j.label === key && (best === null || (j.state === "running") || (best.state !== "running" && j.started >= best.started))) best = j
        return best
    }
    // quickget in the background; "" = started, else why not. One running job per target (same key = same quickget folder);
    // vm-ctl holds a lock per target too, so a second entry point or a second click cannot start a duplicate.
    function startJob(osid, rel, ed, ram, cores, disk) {
        const key = [osid, rel, ed].filter(x => x).join(" ")
        const j = jobFor(key)
        if (j && j.state === "running") return "Already downloading " + key
        const args = ["create-bg", dir, osid, rel].concat(ed ? [ed] : [])
        for (const [opt, v] of [["--ram", ram], ["--cores", cores], ["--disk", disk]]) if (v && v !== "auto") args.push(opt, v)
        const st = Object.assign({}, starting); st[key] = { until: Date.now() + 8000, t: Math.floor(Date.now() / 1000) }; starting = st
        ctl(args)
        Quickshell.execDetached(["notify-send", "-a", "Launcher", "Download started: " + key, "Progress is shown in the bar"])
        refreshSoon()
        return ""
    }
    Timer {
        interval: 1000; repeat: true; running: Object.keys(root.starting).length > 0
        onTriggered: {
            const now = Date.now(), st = {}
            for (const k in root.starting)
                // only a job of this start ends the stand-in (an older finished job of the same target may still be listed)
                if (root.starting[k].until > now && !root.jobs.some(j => j.label === k && j.started >= root.starting[k].t)) st[k] = root.starting[k]
            root.starting = st
        }
    }
    readonly property var activeJob: runningJobs.length > 0 ? runningJobs[0] : null

    function ctl(args) { Quickshell.execDetached([helper].concat(args)) }
    function stop(name) { ctl(["stop", dir, name]) }          // ACPI shutdown of the tracked PID (quickemu --monitor-cmd system_powerdown)
    function focus(name) { ctl(["focus", dir, name]) }
    function cancel(id) { if (id.startsWith("starting:")) return; ctl(["cancel", id]); refreshSoon() }
    function refreshSoon() { soon.restart() }

    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return Math.round(b / 1048576) + " MB"
        return Math.round(b / 1024) + " KB"
    }
    function fmtDuration(s) {
        s = Math.max(0, Math.round(s))
        if (s >= 86400) return Math.floor(s / 86400) + "d " + Math.floor(s % 86400 / 3600) + "h"
        if (s >= 3600) return Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m"
        if (s >= 60) return Math.floor(s / 60) + "m " + (s % 60) + "s"
        return s + "s"
    }
    // "42%  ·  3.1 MB/s  ·  2m 5s left" style detail of a job
    function jobDetail(j) {
        if (j.state === "failed") return j.error || "Failed"
        if (j.state === "cancelled") return "Cancelled"
        if (j.state === "done") return "Ready: " + j.name
        const p = []
        if (j.pct >= 0) p.push(Math.floor(j.pct) + "%")
        else p.push(j.phase || "Preparing")
        if (j.speed > 0) p.push(fmtBytes(j.speed) + "/s")
        if (j.eta >= 0 && j.speed > 0) p.push(fmtDuration(j.eta) + " left")
        return p.join("  ·  ")
    }

    Timer { id: soon; interval: 700; onTriggered: root.poll() }
    Timer {
        id: ticker
        // nothing to track: one cheap scan every few seconds; something running: faster
        interval: root.panelOpen ? 1500 : root.jobs.length > 0 || root.launcherOpen ? 1000 : root.vms.length > 0 ? 3000 : 5000
        repeat: true
        running: BarWidgets.shown("vm") || root.launcherOpen || Object.keys(root.starting).length > 0
        triggeredOnStart: true
        onTriggered: root.poll()
    }
    function poll() { if (!statusProc.running) statusProc.running = true }

    property var last: ({})                          // pid -> { ticks, t }: CPU % is the tick delta between two polls
    Process {
        id: statusProc
        command: [root.helper, "status", root.dir]
        stdout: StdioCollector { id: statusOut }
        onExited: (code, status) => {
            let d = null
            try { d = JSON.parse(statusOut.text) } catch (e) { d = null }
            if (code !== 0 || !d) return
            const now = Date.now(), prev = root.last, next = {}
            const vms = (d.vms || []).map(v => {
                const p = prev[v.pid]
                const cpu = p && now > p.t ? Math.max(0, (v.ticks - p.ticks) * 1000 / v.hz / (now - p.t) * 100) : -1
                next[v.pid] = { ticks: v.ticks, t: now }
                return Object.assign({}, v, { cpu: cpu })
            })
            root.last = next
            if (JSON.stringify(vms) !== JSON.stringify(root.vms)) root.vms = vms
            if (JSON.stringify(d.jobs || []) !== JSON.stringify(root.jobs)) root.jobs = d.jobs || []
        }
    }

    onPanelOpenChanged: { if (panelOpen) poll() }

    FileView {
        path: root.home + "/.config/launcher/config.json"
        printErrors: false
        onLoaded: { try { const c = JSON.parse(text()); if (c && typeof c.vmDir === "string") root.cfgDir = c.vmDir } catch (e) {} }
    }
}
