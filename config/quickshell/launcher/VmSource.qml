import QtQuick
import Quickshell
import Quickshell.Io

// Source: the launcher "vms" section (quickemu virtual machines; the root row lives in SectionsSource, which delegates
// enter / header / glyph / headerSub here, and Launcher.refresh() asks listFor(q) for the rows). All work goes through
// launcher/bin/vm-ctl (python; argv only, toasts via notify-send). VM folder: $LAUNCHER_VM_DIR, else
// ~/.config/launcher/config.json "vmDir", else ~/VMs (created by `vm-ctl list`).
//   top level:  "New VM..." (nested levels: OS -> release -> edition from `quickget --list-csv`, cached a day in
//               ~/.cache/launcher/quickget.csv; typing digits or a space at the OS level also lists every "OS release edition"
//               leaf, so "ubuntu 24.04" finds it), then one row per <name>.conf: green dot = running (quickemu's
//               <vmdir>/<name>.pid holds a live qemu PID). Enter: stopped = `vm-ctl start` (GTK display, VirGL for Linux guests),
//               running = `vm-ctl focus` (Hyprland focus by qemu PID / SPICE viewer). Polled every 2 s while the section is shown.
//   Ctrl+K:     stopped: SPICE viewer / headless start, Snapshots (nested level), Open VM folder, Edit config, Delete VM (confirm,
//               gio trash); running: Shut down (ACPI), Force stop (confirm), Open VM folder, Edit config.
//   picking an OS leaf -> form -> "Download and create" runs `vm-ctl create-bg` in the background (progress in the bar's VM chip, VmService.qml;
//               toast at the end); Ctrl+K on that row: "Download in a terminal" (old `create-run`).
//   "From local ISO..." (first row of New VM): *.iso in isoDirs ($LAUNCHER_ISO_DIRS, colon list; else config.json "isoDirs"; else
//               ~/Downloads, ~/ISOs, the VM folder; 2 levels deep, newest first); typing "/..." or "~/..." browses paths instead
//               (`vm-ctl isopath`, unranked; folder rows descend). Picking one opens a form level (name, guest type, disk size,
//               "Create and boot the installer" / "Create only") -> `vm-ctl create-local` (the ISO is referenced in place).
//   Ctrl+K "Attach ISO..." reuses the picker (`vm-ctl attach`: iso= while the disk is unused, else fixed_iso=); "Detach ISO".
// `QS_QUICKEMU` / `QS_QUICKGET` (read by vm-ctl) replace the binaries in tests.
QtObject {
    id: src

    signal updated()
    property var pkgHint: null                      // hint row (kind "pkg-hint") while quickemu / quickget are missing; set by Launcher from OptionalPackages
    onPkgHintChanged: changed()
    signal finished()                               // close the launcher (a VM was created and is booting)
    // background downloads (the launcher folder cannot see the root singletons: Launcher.qml wires these to VmService.qml)
    property var jobs: []                           // VmService.allJobs: {id, label (= "os release [edition]"), state, phase, pct, detail, error, name}
    signal jobStart(string os, string rel, string ed, string ram, string cores, string disk)
    signal jobCancel(string id)
    property var startedKeys: ({})                  // targets started from the open form: when one is done the form closes and the VM is selected
    function jobOf(key) {
        let best = null
        for (const j of jobs) if (j.label === key && (best === null || j.state === "running" || (best.state !== "running" && j.started >= best.started))) best = j
        return best
    }
    function formKey(f) { return [f.os, f.rel, f.ed].filter(x => x).join(" ") }
    onJobsChanged: {
        for (const k in startedKeys) {
            const j = jobOf(k)
            if (j && j.state === "done" && form && form.mode === "quickget" && formKey(form) === k) {
                const n = j.name
                const s = Object.assign({}, startedKeys); delete s[k]; startedKeys = s
                stack = []; form = null
                selectAfter = nameRe.test(n) ? "vm:" + n : ""
                poll()
            } else if (j && j.state !== "running") { const s = Object.assign({}, startedKeys); delete s[k]; startedKeys = s }
        }
        changed()
    }
    function jobRow(j, id, title) {
        const run = j.state === "running"
        const sub = j.state === "failed" ? (j.error || "Failed") : run && j.pct >= 0 ? j.phase + "  ·  " + j.detail : j.detail
        return { id: id, name: (run ? "Downloading " : j.state === "failed" ? "Failed: " : "") + (title || j.label), subtitle: sub, kind: "vm-job", jobId: j.id, source: "",
                 glyph: "\uf019", iconColor: j.state === "failed" ? "red" : "", transient: true, private: true, vmNav: false,
                 progress: run ? Math.max(0, j.pct) / 100 : undefined, runLabel: "",
                 actions: [run ? act("vm-job-cancel", "Cancel download", "", "Stops quickget; the partial file is kept and resumes next time")
                               : act("vm-job-cancel", "Dismiss", "", "")] }
    }
    signal select(string id)                        // select this row once it is listed (a VM created with "Create only")

    property bool active: false                     // launcher shown
    property string section: ""                     // launcher section
    property string cfgDir: ""                      // config.json "vmDir" (set by Launcher)
    property var cfgIsoDirs: []                     // config.json "isoDirs" (set by Launcher)
    readonly property bool current: active && section === "vms"
    readonly property var items: []                 // root row: SectionsSource

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: {
        const e = Quickshell.env("LAUNCHER_VM_DIR")
        const d = e ? String(e) : cfgDir !== "" ? cfgDir : "~/VMs"
        return d.replace(/^~(?=\/|$)/, home).replace(/\/+$/, "")
    }
    readonly property string dirLabel: tilde(dir)
    readonly property var isoDirs: {
        const e = Quickshell.env("LAUNCHER_ISO_DIRS")
        const l = e ? String(e).split(":") : cfgIsoDirs.length ? cfgIsoDirs : ["~/Downloads", "~/ISOs", dir]
        return l.filter(d => typeof d === "string" && d !== "").map(d => d.replace(/^~(?=\/|$)/, home))
    }
    function tilde(p) { return p === home ? "~" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p }
    readonly property string helper: String(Qt.resolvedUrl("bin/vm-ctl")).replace(/^file:\/\//, "")
    readonly property string cache: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/launcher/quickget.csv"
    readonly property var nameRe: /^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$/
    readonly property var tagRe: /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/

    // ---- state ---------------------------------------------------------------------------------------------
    property var vms: []
    property bool loaded: false
    property string error: ""
    property var pending: ({})                      // name -> { text, until }: "shutting down..." etc. until the state changes
    property var oses: []
    property var leaves: []                         // every OS / release / edition as a create row (filtering at the OS level)
    property bool osLoading: false
    property string osError: ""
    property var stack: []                          // nested levels: { level: "new"|"rel"|"ed"|"snap", os, rel, vm, selId }
    readonly property int depth: stack.length
    readonly property var top: stack.length ? stack[stack.length - 1] : null
    property var snaps: []
    property bool snapLoading: false
    property bool snapInstalled: true
    property string snapError: ""
    property string snapBusy: ""                    // text of the running snapshot command
    property var isos: []                           // local ISO picker (level "iso")
    property bool isoLoading: false
    property var pathRes: null                      // { q, dirs, files } of the typed path ("/..." or "~/...")
    property string pathQ: ""
    property var form: null                         // level "form": { iso, isoName, name, guest, size }
    property string formBusy: ""
    property string formError: ""
    property bool formStart: false
    property string selectAfter: ""
    property int rev: 0                             // bumped on every visible change: headerSub() bindings depend on it

    onCurrentChanged: if (current) poll(); else stack = []
    function enter() { stack = []; error = ""; pending = ({}); poll(); if (!hostInfo.threads && !hostProc.running) hostProc.running = true }

    property var ticker: Timer {
        interval: 2000
        repeat: true
        running: src.current
        onTriggered: src.poll()
    }
    function poll() { if (!listProc.running) listProc.running = true }

    property var listProc: Process {
        command: [src.helper, "list", src.dir]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: (code, status) => Qt.callLater(() => src.parseList(code, listOut.text, listErr.text))
    }
    function parseList(code, text, err) {
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        loaded = true
        if (code !== 0 || !Array.isArray(d)) error = firstLine(err) || ("vm-ctl exited with code " + code)
        else {
            error = ""
            vms = d.filter(v => v && nameRe.test(v.name || ""))
            // a pending marker ends when the VM changed state (stopped / gone) or after its timeout
            const now = Date.now(), p = {}
            for (const n in pending) {
                const v = vms.find(x => x.name === n)
                if (pending[n].until > now && v && v.running === pending[n].running) p[n] = pending[n]
            }
            pending = p
        }
        changed()
        if (selectAfter !== "" && vms.some(v => "vm:" + v.name === selectAfter)) { const id = selectAfter; selectAfter = ""; select(id) }
    }
    function firstLine(t) { return (t || "").trim().split("\n")[0].slice(0, 160) }

    property string sig: ""
    function changed() {
        const s = JSON.stringify([vms, error, pending, loaded, osLoading, osError, oses.length, stack, snaps, snapLoading, snapError, snapBusy,
                                  isos, isoLoading, pathRes, form, formBusy, formError, hostInfo, jobs])
        if (s !== sig) { sig = s; rev++; updated() }
    }

    // ---- quickget OS list ------------------------------------------------------------------------------------
    property var osProc: Process {
        command: [src.helper, "oslist", src.cache]
        stdout: StdioCollector { id: osOut }
        stderr: StdioCollector { id: osErr }
        onExited: (code, status) => Qt.callLater(() => src.parseOs(code, osOut.text, osErr.text))
    }
    function loadOs() {
        if (osProc.running || (oses.length > 0 && osError === "")) return
        osLoading = true; osError = ""
        osProc.running = true
    }
    function parseOs(code, text, err) {
        osLoading = false
        let d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        if (code !== 0 || !Array.isArray(d)) { osError = code === 127 ? "quickget is not installed" : firstLine(err) || ("exit code " + code); changed(); return }
        oses = d
        const out = []
        for (const o of d)
            for (const r of o.releases) {
                if (r.editions.length === 0) out.push(createRow(o, r.release, ""))
                else for (const e of r.editions) out.push(createRow(o, r.release, e))
            }
        leaves = out
        changed()
    }

    // ---- rows ----------------------------------------------------------------------------------------------
    function info(id, name, sub, glyph, color) {
        return { id: "vm:info:" + id, name: name, subtitle: sub || "", kind: "info", source: "", glyph: glyph || "", iconColor: color || "muted",
                 transient: true, private: true }
    }
    function guestLabel(g) {
        const m = { "linux": "Linux", "linux_old": "Linux", "windows": "Windows", "windows-server": "Windows Server", "macos": "macOS", "freebsd": "FreeBSD",
                    "openbsd": "OpenBSD", "netbsd": "NetBSD", "dragonflybsd": "DragonFly BSD", "solaris": "Solaris", "reactos": "ReactOS", "haiku": "Haiku",
                    "freedos": "FreeDOS", "kolibrios": "KolibriOS", "batocera": "Batocera" }
        return m[g] || (g ? g.charAt(0).toUpperCase() + g.slice(1) : "Unknown OS")
    }
    readonly property string noAccel: "no GPU acceleration (Linux guests only)"
    function gb(n) { return n >= 1e9 ? (n / 1e9).toFixed(1) + " GB" : Math.max(1, Math.round(n / 1e6)) + " MB" }
    function act(id, label, glyph, sub, confirm, confirmText) {
        const a = { id: id, label: label, glyph: glyph, sub: sub || "" }
        if (confirm) { a.confirm = true; a.confirmText = confirmText }
        return a
    }
    function vmRow(v) {
        const p = pending[v.name]
        const parts = [guestLabel(v.guest)]
        if (!v.accel) parts.push(noAccel)
        parts.push(v.installed && !v.fresh ? gb(v.used) + " of " + v.size : "not installed yet")
        if (v.isoMissing) parts.push("installer ISO missing: " + v.iso)
        else if (v.fresh && v.iso) parts.push("ISO " + v.iso)
        if (v.fixedIso) parts.push("CD " + v.fixedIso)
        if (v.ram || v.cores) parts.push([v.ram, v.cores ? v.cores + (v.cores === "1" ? " core" : " cores") : ""].filter(x => x).join("  ·  "))
        if (p) parts.push(p.text)
        else if (v.running) {
            parts.push(v.display === "headless" ? "running headless" : v.display === "spice" ? "running (SPICE)" : "running")
            if (v.ssh) parts.push("ssh :" + v.ssh)
        }
        const a = v.running
            ? [act("vm-stop", "Shut down", "", "ACPI power button: the guest shuts down cleanly"),
               act("vm-kill", "Force stop", "", "Kill qemu, like pulling the plug", true, "Force stop " + v.name + "? Unsaved work in it is lost")]
            : [act("vm-start-spice", "Start with SPICE viewer", "", "Clipboard / folder sharing and USB redirection (needs spice-vdagent in the guest)"),
               act("vm-start-headless", "Start headless", "", "No window; SSH and SPICE on localhost"),
               act("vm-snaps", "Snapshots", "", "Create, restore or delete disk snapshots"),
               act("vm-attach", "Attach ISO...", "", v.fresh ? "Installer ISO (replaces " + (v.iso || "none") + ")" : "Extra CD-ROM, e.g. drivers (virtio-win)")]
        if (!v.running) a.push(act("vm-res", "Resources...", "", "RAM " + (v.ram || "auto") + "  ·  CPU cores " + (v.cores || "auto")))
        if (!v.running && (v.fixedIso || v.iso)) a.push(act("vm-detach", "Detach ISO", "", v.fixedIso || v.iso))
        a.push(act("vm-folder", "Open VM folder", "", v.vmdir))
        a.push(act("vm-edit", "Edit config", "", v.name + ".conf"))
        if (!v.running) a.push(act("vm-delete", "Delete VM", "", "Move the config and the VM folder to the trash", true, "Delete " + v.name + "? Moves it to the trash"))
        return { id: "vm:" + v.name, name: v.name, subtitle: parts.join("  ·  "), kind: "vm", source: v.running ? "Running" : "",
                 glyph: "", iconColor: v.running ? "green" : "muted", transient: true, private: true, vm: v.name, running: v.running,
                 vmdir: v.vmdir, conf: v.conf, runLabel: v.running ? "Show window" : "Start", keywords: [guestLabel(v.guest), v.guest], actions: a }
    }
    readonly property var newRow: ({ id: "vm:new", name: "New VM...", subtitle: "Download an OS with quickget into " + dirLabel, kind: "vm-new", vmNav: true,
                                     source: "", glyph: "", iconColor: "", transient: true, private: true, runLabel: "Choose OS",
                                     keywords: ["create", "add", "quickget", "download", "install"] })
    function osRow(o) {
        const n = o.releases.length
        return { id: "vm:os:" + o.os, name: o.name, subtitle: (n === 1 ? o.releases[0].release : n + " releases") + (o.accel ? "" : "  ·  " + noAccel),
                 kind: "vm-os", vmNav: true, os: o.os, source: "", glyph: "", iconColor: "muted", transient: true, private: true,
                 runLabel: "Choose release", keywords: [o.os].concat(o.releases.map(r => r.release)) }
    }
    function createRow(o, rel, ed) {
        const label = [o.name, rel, ed].filter(s => s).join(" ")
        return { id: "vm:mk:" + o.os + ":" + rel + ":" + ed, name: label, subtitle: "quickget " + [o.os, rel, ed].filter(s => s).join(" ") + (o.accel ? "" : "  ·  " + noAccel),
                 kind: "vm-create", vmNav: true, os: o.os, rel: rel, ed: ed, label: label, source: "", glyph: "", iconColor: "muted", transient: true, private: true,
                 runLabel: "Download and create", keywords: [o.os] }
    }
    function osOf(id) { return oses.find(o => o.os === id) || null }

    function rows() {
        const t = top
        if (!t) {
            const out = [pkgHint || newRow]
            for (const j of jobs) out.push(jobRow(j, "vm:job:" + j.label))
            if (error !== "") out.push(info("error", "Could not list VMs", error, "", "red"))
            else if (!loaded) out.push(info("load", "Loading...", ""))
            for (const v of vms) out.push(vmRow(v))
            return out
        }
        if (t.level === "iso") return isoRows()
        if (t.level === "form") return formRows()
        if (t.level === "new") {
            if (osLoading) return [localRow, info("os-load", "Loading the OS list from quickget...", "Takes about 10 s, then it is cached for a day")]
            if (osError !== "") return [localRow, info("os-error", "Could not get the OS list", osError, "", "red")]
            return [localRow].concat(oses.map(osRow))
        }
        const o = osOf(t.os)
        if (t.level === "rel") {
            if (!o) return []
            return o.releases.map(r => r.editions.length === 0 ? createRow(o, r.release, "")
                : { id: "vm:rel:" + o.os + ":" + r.release, name: o.name + " " + r.release, subtitle: r.editions.length + " editions" + (o.accel ? "" : "  ·  " + noAccel),
                    kind: "vm-rel", vmNav: true, os: o.os, rel: r.release, source: "", glyph: "", iconColor: "muted", transient: true, private: true,
                    runLabel: "Choose edition", keywords: r.editions })
        }
        if (t.level === "ed") {
            const r = o ? o.releases.find(x => x.release === t.rel) : null
            return r ? r.editions.map(e => createRow(o, r.release, e)) : []
        }
        if (t.level === "snap") return snapRows(t.vm)
        return []
    }
    // the OS level lists every leaf too once the filter has a digit or a space ("ubuntu 24.04", "fedora kde")
    function listFor(q) {
        if (unranked(q)) return pathRows(q)
        const base = rows()
        return top && top.level === "new" && !osLoading && osError === "" && /[0-9 ]/.test(q) ? base.concat(leaves) : base
    }

    function header() {
        const t = top
        if (!t) return "Virtual machines"
        if (t.level === "new") return "New VM"
        if (t.level === "snap") return "Snapshots"
        if (t.level === "iso") return t.mode === "attach" ? "Attach ISO" : "Local ISO"
        if (t.level === "form") return !form ? "" : form.mode === "res" ? "Resources" : form.mode === "quickget" ? form.label : "New VM from ISO"
        const o = osOf(t.os)
        return (o ? o.name : t.os) + (t.level === "ed" ? " " + t.rel : "")
    }
    function glyph() { const t = top; return !t ? "" : t.level === "form" && form && form.mode !== "iso" ? "" : t.level === "iso" || t.level === "form" ? "" : t.level === "new" ? "" : t.level === "snap" ? "" : t.level === "ed" ? "" : "" }
    function headerSub() {
        void rev
        const t = top
        if (!t) { const n = vms.filter(v => v.running).length; return dirLabel + (n ? "  ·  " + n + " running" : "") }
        if (t.level === "new") return "quickget"
        if (t.level === "rel") return "Choose a release"
        if (t.level === "ed") return "Choose an edition"
        if (t.level === "iso") return t.mode === "attach" ? t.vm : "Type / or ~/ for a path"
        if (t.level === "form") return !form ? "" : form.mode === "res" ? form.vm : form.mode === "quickget" ? "Before the download" : form.isoName
        return t.vm
    }

    // ---- levels (Launcher: runItem on a vmNav row / Right -> push, back() -> pop) -----------------------------------
    function push(item) {
        if (item.kind === "vm-new") { stack = stack.concat([{ level: "new", selId: item.id }]); loadOs() }
        else if (item.kind === "vm-os") stack = stack.concat([{ level: "rel", os: item.os, selId: item.id }])
        else if (item.kind === "vm-rel") stack = stack.concat([{ level: "ed", os: item.os, rel: item.rel, selId: item.id }])
        else if (item.kind === "vm-iso-pick") { stack = stack.concat([{ level: "iso", mode: "create", selId: item.id }]); loadIsos() }
        else if (item.kind === "vm-iso") pickIso(item)
        else if (item.kind === "vm-create") {
            form = { mode: "quickget", os: item.os, rel: item.rel, ed: item.ed || "", label: item.label, ram: "auto", cores: "auto", size: "auto",
                     guest: item.os.startsWith("windows") ? "windows" : item.os === "macos" ? "macos" : "linux" }
            formError = ""; formBusy = ""
            stack = stack.concat([{ level: "form", selId: item.id }])
        }
        changed()
    }
    // returns the id of the row to select in the parent level
    function pop() {
        const t = top
        stack = stack.slice(0, -1)
        if (t && t.level === "snap") { snaps = []; snapError = "" }
        if (t && t.level === "iso") { pathRes = null; pathQ = "" }
        if (t && t.level === "form") { form = null; formError = ""; formBusy = "" }
        changed()
        return t ? t.selId : ""
    }

    // ---- snapshots ------------------------------------------------------------------------------------------
    function vmOf(name) { return vms.find(v => v.name === name) || null }
    function snapRows(name) {
        const v = vmOf(name)
        const out = []
        if (snapBusy !== "") out.push(info("snap-busy", snapBusy, "", ""))
        if (!v) return out.concat([info("snap-gone", name + " no longer exists", "")])
        if (v.running) out.push(info("snap-running", name + " is running", "Shut it down to create or restore snapshots", ""))
        if (snapLoading && snaps.length === 0) return out.concat([info("snap-load", "Loading...", "")])
        if (snapError !== "") return out.concat([info("snap-error", "Could not read the snapshots", snapError, "", "red")])
        if (!snapInstalled) return out.concat([info("snap-none", "No disk yet", "Snapshots need an installed VM", "")])
        const d = new Date()
        if (!v.running) out.push({ id: "vm:snap-new:" + name, name: "New snapshot...", subtitle: "Saves the disk as it is now (VM must be off)", kind: "vm-snap-new", vm: name,
                   source: "", glyph: "", iconColor: "", transient: true, private: true, argument: "Snapshot name", argVerb: "create",
                   argInit: "snap-" + Qt.formatDateTime(d, "yyyyMMdd-HHmm") })
        for (const s of snaps)
            out.push({ id: "vm:snap:" + name + ":" + s.tag, name: s.tag, subtitle: (s.date ? Qt.formatDateTime(new Date(s.date * 1000), "d MMM yyyy, HH:mm") : "")
                           + (s.size > 0 ? "  ·  with RAM state" : ""), kind: v.running ? "info" : "vm-snap", vm: name, tag: s.tag, source: "", glyph: "", iconColor: "muted",
                       transient: true, private: true, runLabel: "Restore", confirm: true, confirmText: "Restore " + s.tag + "? Disk changes since then are lost",
                       confirmSub: "Press Enter again to restore " + name,
                       actions: [act("vm-snap-delete", "Delete snapshot", "", "", true, "Delete snapshot " + s.tag + "?")] })
        if (snaps.length === 0 && !snapLoading) out.push(info("snap-empty", "No snapshots yet", ""))
        return out
    }
    property var snapProc: Process {
        stdout: StdioCollector { id: snapOut }
        stderr: StdioCollector { id: snapErr }
        onExited: (code, status) => Qt.callLater(() => {
            src.snapLoading = false
            let d = null
            try { d = JSON.parse(snapOut.text) } catch (e) { d = null }
            if (code !== 0 || !d || !Array.isArray(d.snapshots)) src.snapError = src.firstLine(snapErr.text) || ("exit code " + code)
            else { src.snapError = ""; src.snapInstalled = d.installed !== false; src.snaps = d.snapshots.filter(s => s && src.tagRe.test(String(s.tag || ""))) }
            src.changed()
        })
    }
    function loadSnaps() {
        const t = top
        if (!t || t.level !== "snap" || snapProc.running) return
        snapLoading = true
        snapProc.command = [helper, "snapshots", dir, t.vm]
        snapProc.running = true
        changed()
    }
    property var snapOpProc: Process {
        stderr: StdioCollector { id: opErr }
        onExited: (code, status) => Qt.callLater(() => { src.snapBusy = ""; src.loadSnaps(); src.changed() })
    }
    function snapOp(name, op, tag, text) {
        if (snapOpProc.running || !nameRe.test(name) || !tagRe.test(tag)) return false
        snapBusy = text
        snapOpProc.command = [helper, "snapshot", dir, name, op, tag]
        snapOpProc.running = true
        changed()
        return true
    }

    // in-place rows (Launcher.runItem: the launcher stays open, progress shows on the list): snapshot create / restore
    function owns(item) { return !!item && (item.kind === "vm-job" || item.kind === "vm-snap-new" || item.kind === "vm-snap" || /^vm-form-/.test(item.kind || "")) }
    function activate(item, arg) {
        if (item.kind === "vm-job") return true
        if (/^vm-form-/.test(item.kind)) return formActivate(item, arg)
        if (item.kind === "vm-snap-new") {
            const tag = String(arg || "").trim()
            if (!tagRe.test(tag)) return "Letters, digits, . _ - only (up to 40)"
            if (snaps.some(s => s.tag === tag)) return "A snapshot with that name exists"
            if (!snapOp(item.vm, "create", tag, "Creating snapshot " + tag + "...")) return "Another snapshot command is running"
            return true
        }
        if (item.kind === "vm-snap") snapOp(item.vm, "apply", item.tag, "Restoring " + item.tag + "...")
        return true
    }

    // ---- local ISOs -------------------------------------------------------------------------------------------
    readonly property var localRow: ({ id: "vm:iso", name: "From local ISO...", subtitle: "An .iso from " + isoDirs.map(tilde).join(", ") + " or a typed path",
                                       kind: "vm-iso-pick", vmNav: true, source: "", glyph: "", iconColor: "", transient: true, private: true,
                                       runLabel: "Choose ISO", keywords: ["iso", "local", "file", "image", "installer", "own"] })
    property var isoProc: Process {
        stdout: StdioCollector { id: isoOut }
        onExited: (code, status) => Qt.callLater(() => {
            src.isoLoading = false
            let d = null
            try { d = JSON.parse(isoOut.text) } catch (e) { d = null }
            src.isos = Array.isArray(d) ? d : []
            src.changed()
        })
    }
    function loadIsos() {
        if (isoProc.running) return
        isoLoading = true
        isoProc.command = [helper, "isos"].concat(isoDirs)
        isoProc.running = true
    }
    function isoRow(x) {
        return { id: "vm:isof:" + x.path, name: x.name, subtitle: gb(x.size) + "  ·  " + Qt.formatDateTime(new Date(x.mtime * 1000), "d MMM yyyy") + "  ·  " + tilde(x.dir),
                 kind: "vm-iso", vmNav: true, path: x.path, isoName: x.name, source: "", glyph: "", iconColor: "muted", transient: true, private: true,
                 runLabel: top && top.mode === "attach" ? "Attach" : "Use this ISO", keywords: [tilde(x.dir)] }
    }
    function isoRows() {
        if (isoLoading && isos.length === 0) return [info("iso-load", "Looking for ISO files...", "")]
        if (isos.length === 0) return [info("iso-none", "No .iso files found", "Looked in " + isoDirs.map(tilde).join(", ") + "  ·  type / or ~/ to browse")]
        return isos.map(isoRow)
    }
    // typed path at the ISO level: "/..." or "~/..." lists folders and .iso files of that folder (not ranked)
    function unranked(q) { return !!top && top.level === "iso" && /^(\/|~(\/|$))/.test(q) }
    property var pathTimer: Timer {
        interval: 120
        onTriggered: { src.pathProc.running = false; src.pathProc.q = src.pathQ; src.pathProc.command = [src.helper, "isopath", src.pathQ]; src.pathProc.running = true }
    }
    property var pathProc: Process {
        property string q: ""
        stdout: StdioCollector { id: pathOut }
        onExited: (code, status) => Qt.callLater(() => {
            let d = null
            try { d = JSON.parse(pathOut.text) } catch (e) { d = null }
            src.pathRes = { q: src.pathProc.q, dirs: d && Array.isArray(d.dirs) ? d.dirs : [], files: d && Array.isArray(d.files) ? d.files : [] }
            src.changed()
        })
    }
    function pathRows(q) {
        const t = q === "~" ? "~/" : q
        if (t !== pathQ) { pathQ = t; pathTimer.restart() }
        if (!pathRes || pathRes.q !== t) return [info("path-load", "Looking...", tilde(t))]
        const keepTilde = t.startsWith("~")
        const out = pathRes.dirs.map(d => ({ id: "vm:dir:" + d, name: d.split("/").pop() + "/", subtitle: tilde(d), kind: "vm-dir", descend: (keepTilde ? tilde(d) : d) + "/",
                                              source: "", glyph: "", iconColor: "muted", transient: true, private: true }))
        for (const f of pathRes.files) out.push(isoRow(f))
        return out.length ? out : [info("path-none", "No folders or .iso files match", tilde(t))]
    }

    // picker -> create form, or attach to the VM the picker was opened for
    function pickIso(item) {
        const t = top
        if (t && t.mode === "attach") {
            if (nameRe.test(t.vm || "")) ctl(["attach", dir, t.vm, item.path])
            stack = []
            pollSoon.restart()
            return
        }
        form = { mode: "iso", iso: item.path, isoName: item.isoName, name: defaultName(item.isoName), guest: guessGuest(item.isoName), size: "64G", ram: "auto", cores: "auto" }
        formError = ""; formBusy = ""
        stack = stack.concat([{ level: "form", selId: item.id }])
    }
    // "Fedora-Workstation-Live-x86_64-43.iso" -> "fedora-workstation-live-x86_64-43" (unique in the VM folder)
    function defaultName(file) {
        let n = file.replace(/\.iso$/i, "").toLowerCase().replace(/[^a-z0-9._+-]+/g, "-").replace(/^[^a-z0-9]+/, "").replace(/-+$/, "").slice(0, 40).replace(/[-.]+$/, "")
        if (!nameRe.test(n)) n = "vm"
        let out = n, i = 2
        while (vms.some(v => v.name === out)) out = n + "-" + i++
        return out
    }
    function guessGuest(file) {
        const f = file.toLowerCase()
        if (/win(dows)?[ _-]?(1[01]|server|7|8)|^win|windows|virtio-win/.test(f)) return "windows"
        if (/bsd|haiku|reactos|freedos|kolibri|solaris|illumos|openindiana/.test(f)) return "other"
        return "linux"
    }
    readonly property var guestNames: ({ linux: "Linux", windows: "Windows", other: "Other" })
    // ---- RAM / CPU cores (quickemu's auto values from `vm-ctl host`) ---------------------------------------------
    property var hostInfo: ({ ram: 0, threads: 0, smt: false, autoRam: "auto", autoCores: "auto" })
    property var hostProc: Process {
        command: [src.helper, "host"]
        stdout: StdioCollector { id: hostOut }
        onExited: (code, status) => Qt.callLater(() => { try { const d = JSON.parse(hostOut.text); if (d && d.threads) src.hostInfo = d } catch (e) {} src.changed() })
    }
    function gbOf(v) { const m = /^([0-9]+)([GM])$/.exec(v); return m ? Number(m[1]) / (m[2] === "G" ? 1 : 1024) : 0 }
    function ramPicks() { return ["auto", "4G", "8G", "16G", "32G"].filter(v => v === "auto" || !hostInfo.ram || gbOf(v) <= hostInfo.ram - 4) }
    function corePicks() { return ["auto", "2", "4", "8", "16"].filter(v => v === "auto" || !hostInfo.threads || Number(v) <= hostInfo.threads) }
    function nextOf(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length] }
    // same rules as vm-ctl ram_error / cores_error
    function ramError(v, guest) {
        if (v === "auto") return ""
        const m = /^([1-9][0-9]{0,6})([GM])$/.exec(v)
        if (!m) return "RAM like 8G or 4096M (or auto)"
        if (m[2] === "M" && ["windows", "windows-server", "macos"].includes(guest)) return "Use whole GB (e.g. 8G) for this guest"
        const gb = gbOf(v)
        if (gb < 1) return "At least 1G"
        if (hostInfo.ram && gb > hostInfo.ram - 4) return "At most " + (hostInfo.ram - 4) + "G (host RAM minus 4G)"
        return ""
    }
    function coresError(v) {
        if (v === "auto") return ""
        if (!/^[1-9][0-9]{0,3}$/.test(v)) return "A whole number (or auto)"
        if (hostInfo.threads && Number(v) > hostInfo.threads) return "At most " + hostInfo.threads + " (host threads)"
        if (hostInfo.smt && Number(v) > 1 && Number(v) % 2) return "1 or an even number (quickemu pairs SMT threads)"
        return ""
    }

    function formRows() {
        const f = form
        if (!f) return []
        const out = []
        if (formBusy !== "") out.push(info("form-busy", formBusy, "", ""))
        const job = f.mode === "quickget" ? jobOf(formKey(f)) : null
        if (job && job.state === "failed") out.push(info("form-job-error", "Download failed", job.error || "Failed", "", "red"))
        if (formError !== "") out.push(info("form-error", f.mode === "res" ? "Could not save" : "Could not create the VM", formError, "", "red"))
        const row = (id, name, sub, kind, glyph, extra) => Object.assign({ id: "vm:form:" + id, name: name, subtitle: sub, kind: kind, source: "", glyph: glyph,
                                                                           iconColor: "", transient: true, private: true }, extra || {})
        const typeAct = [{ id: "vm-form-type", label: "Type a value...", glyph: "" }]
        const ramRow = row("ram", "RAM:  " + (f.ram === "auto" ? "auto (" + hostInfo.autoRam + ")" : f.ram), "Enter cycles " + ramPicks().join(" / ") + "  ·  → type a value",
                           "vm-form-ram", "", { runLabel: "Next value", actions: typeAct })
        const coreRow = row("cores", "CPU cores:  " + (f.cores === "auto" ? "auto (" + hostInfo.autoCores + ")" : f.cores), "Enter cycles " + corePicks().join(" / ") + "  ·  → type a value"
                            + (hostInfo.threads ? "  ·  host " + hostInfo.threads + " threads" : ""), "vm-form-cores", "", { runLabel: "Next value", actions: typeAct })
        if (f.mode === "res") {
            out.push(ramRow, coreRow)
            out.push(row("save", "Save", "Writes ram= / cpu_cores= in " + f.vm + ".conf (auto removes the line)", "vm-form-save", "", { runLabel: "Save" }))
            return out
        }
        if (f.mode === "quickget") {
            out.push(ramRow, coreRow)
            out.push(row("size", "Disk size:  " + (f.size === "auto" ? "auto (quickget's default)" : f.size), "Grows as it fills (qcow2)  ·  Enter to change",
                         "vm-form-size", "", { argument: "Disk size (e.g. 64G, or auto)", argInit: f.size === "auto" ? "" : f.size, argVerb: "set the size", runLabel: "Change size" }))
            if (job && job.state === "running") out.push(Object.assign(jobRow(job, "vm:form:download", f.label), { vmNav: false }))
            else out.push(row("download", "Download and create", "quickget " + [f.os, f.rel, f.ed].filter(x => x).join(" ") + " in the background (progress in the bar), then sets these values",
                         "vm-form-download", "", { runLabel: "Download",
                           actions: [act("vm-form-download-term", "Download in a terminal", "", "quickget in a terminal window instead of the background")] }))
            out.push(info("form-qg", "Name: " + [f.os, f.rel, f.ed].filter(x => x).join("-").replace(/ /g, "-").replace(/[()]/g, "") + " (set by quickget)",
                          f.guest === "linux" ? "GPU accelerated (VirGL)" : noAccel, ""))
            return out
        }
        const taken = vms.some(v => v.name === f.name)
        out.push(row("name", "Name:  " + f.name, taken ? "A VM with this name exists: Enter to change it" : "Config + folder in " + dirLabel + "  ·  Enter to change",
                     "vm-form-name", "", { argument: "VM name", argInit: f.name, argVerb: "set the name", runLabel: "Change name" }))
        out.push(row("guest", "Guest:  " + guestNames[f.guest], "Enter switches Linux / Windows / Other  ·  " + (f.guest === "linux" ? "GPU accelerated (VirGL)"
                     : f.guest === "windows" ? "TPM on, secure boot off; " + noAccel : noAccel), "vm-form-guest", "", { runLabel: "Switch" }))
        out.push(row("size", "Disk size:  " + f.size, "Grows as it fills (qcow2)  ·  Enter to change", "vm-form-size", "",
                     { argument: "Disk size (e.g. 64G)", argInit: f.size, argVerb: "set the size", runLabel: "Change size" }))
        out.push(ramRow, coreRow)
        out.push(row("start", "Create and boot the installer", f.isoName, "vm-form-start", "", { runLabel: "Create and start" }))
        out.push(row("create", "Create only", "Start it later from the list", "vm-form-create", "", { runLabel: "Create" }))
        out.push(info("form-iso", "Uses the ISO in place", "Moving or deleting it breaks the installer boot  ·  " + tilde(f.iso), ""))
        return out
    }
    function formActivate(item, arg) {
        const f = form
        if (!f || formBusy !== "") return true
        const k = item.kind
        if (k === "vm-form-name") {
            const v = String(arg || "").trim()
            if (!nameRe.test(v)) return "Letters, digits, . _ + - only, starting with a letter or digit"
            if (vms.some(x => x.name === v)) return "A VM called " + v + " exists"
            form = Object.assign({}, f, { name: v })
        } else if (k === "vm-form-size") {
            let v = String(arg || "").trim().toUpperCase().replace(/B$/, "")
            if (f.mode === "quickget" && (v === "" || v === "AUTO")) v = "auto"
            else {
                if (/^[0-9]+$/.test(v)) v += "G"
                if (!/^[1-9][0-9]{0,4}[MGT]$/.test(v)) return "A size like 64G (M, G or T)" + (f.mode === "quickget" ? ", or auto" : "")
            }
            form = Object.assign({}, f, { size: v })
        } else if (k === "vm-form-guest") {
            form = Object.assign({}, f, { guest: f.guest === "linux" ? "windows" : f.guest === "windows" ? "other" : "linux" })
            if (ramError(form.ram, form.guest) !== "") form = Object.assign({}, form, { ram: "auto" })
        } else if (k === "vm-form-ram") {
            let v = nextOf(ramPicks(), f.ram)
            form = Object.assign({}, f, { ram: v })
        } else if (k === "vm-form-cores") {
            form = Object.assign({}, f, { cores: nextOf(corePicks(), f.cores) })
        } else if (k === "vm-form-ram-set") {
            let v = String(arg || "").trim().toUpperCase().replace(/B$/, "")
            if (v === "AUTO" || v === "") v = "auto"
            else if (/^[0-9]+$/.test(v)) v += "G"
            const e = ramError(v, f.guest)
            if (e !== "") return e
            form = Object.assign({}, f, { ram: v })
        } else if (k === "vm-form-cores-set") {
            let v = String(arg || "").trim().toLowerCase()
            if (v === "") v = "auto"
            const e = coresError(v)
            if (e !== "") return e
            form = Object.assign({}, f, { cores: v })
        } else if (k === "vm-job") {
            return true                                  // Enter on a progress row: nothing (Ctrl+K: Cancel download)
        } else if (k === "vm-form-download" || k === "vm-form-download-term") {
            // background job (no terminal): `vm-ctl create-bg` writes its progress to a job file that VmService polls; the row
            // below turns into a progress row at once (VmService lists the job as "Starting" before its file exists)
            const term = k === "vm-form-download-term"
            const key = formKey(f)
            if (term) {
                const args = [helper, "create-run", dir, f.os, f.rel].concat(f.ed ? [f.ed] : [])
                for (const [opt, v] of [["--ram", f.ram], ["--cores", f.cores], ["--disk", f.size]]) if (v !== "auto") args.push(opt, v)
                Quickshell.execDetached(["ghostty", "--title=New VM: " + f.label, "--working-directory=" + dir, "-e"].concat(args))
                stack = []; form = null
                changed(); finished()
                return true
            }
            const cur = jobOf(key)
            if (cur && cur.state === "running") return "Already downloading " + f.label
            const st = Object.assign({}, startedKeys); st[key] = true; startedKeys = st
            jobStart(f.os, f.rel, f.ed, f.ram, f.cores, f.size)
        } else if (k === "vm-form-save") {
            formError = ""; formBusy = "Saving..."; formOp = "res"
            createProc.command = [helper, "resources", dir, f.vm, f.ram, f.cores]
            createProc.running = true
        } else {
            if (vms.some(x => x.name === f.name)) { formError = "A VM called " + f.name + " exists; change the name"; changed(); return true }
            formError = ""; formBusy = "Creating " + f.name + "..."; formStart = k === "vm-form-start"; formOp = "iso"
            createProc.command = [helper, "create-local", dir, f.name, f.guest, f.size, f.iso, f.ram, f.cores]
            createProc.running = true
        }
        changed()
        return true
    }
    property string formOp: ""
    property var createProc: Process {
        stderr: StdioCollector { id: createErr }
        onExited: (code, status) => Qt.callLater(() => {
            src.formBusy = ""
            if (code !== 0) { src.formError = src.firstLine(createErr.text) || ("exit code " + code); src.changed(); return }
            const n = src.form ? (src.formOp === "res" ? src.form.vm : src.form.name) : ""
            src.stack = []; src.form = null
            if (src.formOp === "iso" && src.formStart && src.nameRe.test(n)) { src.ctl(["start", src.dir, n, "gl"]); src.changed(); src.finished(); return }
            src.selectAfter = "vm:" + n
            src.poll(); src.changed()
        })
    }
    property var pollSoon: Timer { interval: 400; onTriggered: src.poll() }

    // ---- run / actions ----------------------------------------------------------------------------------------
    function ctl(args) { Quickshell.execDetached([helper].concat(args)) }
    // vm-ctl runs detached: the marker ends when the list shows the change, or after `ms` (a failure arrives as a toast)
    function mark(name, text, running, ms) {
        const p = Object.assign({}, pending)
        p[name] = { text: text, until: Date.now() + ms, running: running }
        pending = p
        changed()
    }

    function run(item) {
        if (item.kind === "vm") {
            if (!nameRe.test(item.vm || "")) return true
            ctl(item.running ? ["focus", dir, item.vm] : ["start", dir, item.vm, "gl"])
            return true
        }
        return false
    }
    // item actions (Launcher.doAction): true = done and close, "keep" = stay open, "enter" = a nested level was pushed, false = not ours
    function action(id, item) {
        if (id === "vm-form-type" && (item.kind === "vm-form-ram" || item.kind === "vm-form-cores")) {
            const ram = item.kind === "vm-form-ram", cur = ram ? form.ram : form.cores
            return Object.assign({}, item, { kind: item.kind + "-set", argument: ram ? "RAM, e.g. 12G or auto" : "CPU cores, e.g. 6 or auto",
                                             argInit: cur === "auto" ? (ram ? hostInfo.autoRam : String(hostInfo.autoCores)) : cur, argVerb: "set it" })
        }
        if (item.kind === "vm-job" && id === "vm-job-cancel") { jobCancel(item.jobId); return "keep" }
        if (id === "vm-form-download-term" && item.kind === "vm-form-download") return formActivate(Object.assign({}, item, { kind: "vm-form-download-term" }), "")
        if (item.kind === "vm-snap" && id === "vm-snap-delete") {
            snapOp(item.vm, "delete", item.tag, "Deleting snapshot " + item.tag + "...")
            return "keep"
        }
        if (item.kind !== "vm" || !nameRe.test(item.vm || "")) return false
        const n = item.vm
        switch (id) {
        case "vm-start-spice": ctl(["start", dir, n, "spice"]); return true
        case "vm-start-headless": ctl(["start", dir, n, "headless"]); return true
        case "vm-stop": ctl(["stop", dir, n]); mark(n, "shutting down...", true, 95000); return "keep"
        case "vm-kill": ctl(["kill", dir, n]); mark(n, "stopping...", true, 10000); return "keep"
        case "vm-delete": ctl(["delete", dir, n]); mark(n, "moving to the trash...", false, 15000); return "keep"
        case "vm-folder": Quickshell.execDetached(["xdg-open", item.vmdir || dir]); return true
        case "vm-edit":
            Quickshell.execDetached(["sh", "-c", "exec ghostty --working-directory=\"$(dirname -- \"$1\")\" -e \"${EDITOR:-nvim}\" \"$1\"", "sh", item.conf])
            return true
        case "vm-attach":
            stack = stack.concat([{ level: "iso", mode: "attach", vm: n, selId: item.id }])
            loadIsos()
            return "enter"
        case "vm-detach": ctl(["detach", dir, n]); pollSoon.restart(); return "keep"
        case "vm-res": {
            const v = vmOf(n)
            if (!v) return false
            form = { mode: "res", vm: n, guest: v.guest, ram: v.ram || "auto", cores: v.cores || "auto" }
            formError = ""; formBusy = ""
            stack = stack.concat([{ level: "form", selId: item.id }])
            return "enter"
        }
        case "vm-snaps":
            stack = stack.concat([{ level: "snap", vm: n, selId: item.id }])
            snaps = []; snapError = ""; snapInstalled = true
            loadSnaps()
            return "enter"
        }
        return false
    }
}
