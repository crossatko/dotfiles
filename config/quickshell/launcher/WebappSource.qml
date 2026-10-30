import QtQuick
import Quickshell
import Quickshell.Io

// Source: the launcher "Install webapp" section (root row in SectionsSource, which delegates rows / headerSub here).
// Flow: enter -> address prompt (opens by itself) -> `webapp-install probe <url>` (async: title, manifest name, icon
// candidates) -> name prompt prefilled with the suggestion -> `webapp-install install <url> --name <name>` -> toast
// "Installed <name>" and the launcher closes (finished()); errors stay as a red row with "Try again".
// All the network / file work is in bin/webapp-install (python3 -I); this file only drives it. The new
// webapp_<slug>.desktop shows up in the app list through DesktopEntries' own directory watch.
// Test hook: $QS_WEBAPP_HELPER replaces bin/webapp-install.
QtObject {
    id: src

    signal updated()
    signal prompt(var item)                         // the launcher opens this row's text prompt (Launcher: onPrompt), replacing an open webapp prompt
    signal suggest(var item, string text)           // probe done: the open name prompt becomes `item`; `text` fills the field ONLY while it is empty
    signal finished()                               // installed: the launcher closes

    readonly property var items: []                 // root row: SectionsSource
    readonly property string helper: Quickshell.env("QS_WEBAPP_HELPER") || (Quickshell.shellDir + "/bin/webapp-install")

    property string phase: "url"                    // url | probing | name | installing | error
    property string url: ""
    property string host: ""
    property string suggestion: ""
    property string iconNote: ""
    property string warn: ""                        // probe: page not reachable (install still works, letter tile)
    property string error: ""
    property string lastName: ""
    property string pendingName: ""                 // name typed and confirmed while the lookup was still running: installed as soon as it ends
    property int token: 0                           // stale process exits are ignored

    function enter() {
        token++; probeProc.running = false; installProc.running = false
        phase = "url"; url = ""; host = ""; suggestion = ""; iconNote = ""; warn = ""; error = ""; pendingName = ""
        Qt.callLater(() => src.prompt(urlRow()))
    }
    function headerSub() { return phase === "name" || phase === "installing" ? host : "" }

    function base(id, f) { return Object.assign({ id: "webapp:" + id, source: "", transient: true, private: true }, f) }
    function info(id, name, sub, glyph, red) {
        return base(id, { name: name, subtitle: sub || "", kind: "info", glyph: glyph || "", iconColor: red ? "red" : "muted" })
    }
    function urlRow() {
        return base("url", { name: url === "" ? "Enter the web app address" : "Change the address", subtitle: url === "" ? "e.g. example.com or https://example.com/app" : url,
                             kind: "webapp-url", glyph: "\ue0c2", argument: "Address", argInit: url, argVerb: "look it up", runLabel: "Enter address" })   // globe
    }
    // The name prompt opens right after the address (the lookup runs meanwhile), so whatever the user types there is never
    // replaced: the suggestion only fills an empty field (Launcher: onSuggest). Bug 2026-10-21: the prompt used to open
    // when the lookup ended and set its text to the suggestion, overwriting a name typed during a slow lookup.
    function nameRow() {
        const looking = phase === "probing"
        // the row title is the prompt header: never the suggestion, so it cannot read as if a different name would be used
        return base("name", { name: "Name the web app",
                              subtitle: looking ? "Looking up " + host + "...  \u00b7  type a name now or wait for a suggestion"   // zero-width-space
                                                : (suggestion !== "" ? ["Suggested: " + suggestion] : []).concat([url, iconNote], warn ? [warn] : []).join("  \u00b7  "),   // zero-width-space
                              kind: "webapp-name", glyph: "\ue0b7", argument: looking ? "Name (looking up a suggestion...)" : "Name",   // download
                              argInit: looking ? "" : suggestion, argVerb: "install", runLabel: "Install", argGlyph: "\ue142" })   // pen-to-square
    }
    function rows() {
        if (phase === "probing" && pendingName !== "") return [info("installing", "Installing " + pendingName + "...", "After the lookup of " + host, "\ue0f6")]   // spinner
        if (phase === "probing") return [nameRow(), info("probing", "Looking up " + host + "...", "Title, name and icon from the site itself", "\ue0f6")]   // spinner
        if (phase === "installing") return [info("installing", "Installing " + lastName + "...", "Icon and launcher entry", "\ue0f6")]   // spinner
        if (phase === "name") return [nameRow(), urlRow()]
        const out = []
        if (phase === "error" || error !== "") out.push(info("error", "Could not install", error, "\ue101", true))   // triangle-exclamation
        out.push(urlRow())
        return out
    }

    // ---- actions (Launcher.runItem: owns() rows act in place) ------------------------------------------------
    function owns(item) { return !!item && /^webapp-/.test(item.kind || "") }
    // returns a footer note to keep the prompt open, or true
    function activate(item, arg) {
        const t = (arg || "").trim()
        if (item.kind === "webapp-url") {
            if (t === "") return "Type an address, e.g. example.com"
            if (/\s/.test(t) || !/[.:]|^localhost/.test(t)) return "That does not look like a web address"
            token++; installProc.running = false
            error = ""; warn = ""
            host = t.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/[/?#].*$/, "")
            phase = "probing"; pendingName = ""; suggestion = ""
            probeProc.tok = token; probeProc.command = ["python3", "-I", helper, "probe", t]
            probeProc.running = false; probeProc.running = true
            Qt.callLater(() => src.prompt(src.nameRow()))      // ask for the name while the lookup runs
        } else if (item.kind === "webapp-name") {
            // the typed text is the name, exactly (trimmed); the suggestion is used only for an empty field
            const name = t || suggestion
            if (name === "" && phase === "probing") return "Type a name, or wait a moment for the suggestion"
            if (!/[A-Za-z0-9]/.test(name)) return "The name needs a letter or a digit"
            if (phase === "probing") { pendingName = name; updated(); return true }   // installs when the lookup ends
            startInstall(name)
        }
        updated()
        return true
    }

    function startInstall(name) {
        lastName = name; pendingName = ""; phase = "installing"; token++
        installProc.tok = token; installProc.command = ["python3", "-I", helper, "install", url, "--name", name]
        installProc.running = false; installProc.running = true
        updated()
    }

    // Ctrl+K "Uninstall webapp" on an app row (AppsSource sets webappSlug): `webapp-install uninstall <slug>`, toast with
    // the result; DesktopEntries drops the row once the file is gone. Never touches browser profiles.
    function action(id, item) {
        if (id !== "webapp-uninstall" || !/^[a-z0-9][a-z0-9_.-]{0,63}$/.test(item.webappSlug || "")) return false
        if (uninstallProc.running) return "keep"
        uninstallProc.label = item.name
        uninstallProc.command = ["python3", "-I", helper, "uninstall", item.webappSlug]
        uninstallProc.running = true
        return "keep"
    }
    property var uninstallProc: Process {
        property string label: ""
        stdout: StdioCollector { id: unOut }
        stderr: StdioCollector { id: unErr }
        onExited: code => {
            const j = src.parse(unOut.text)
            Quickshell.execDetached(["notify-send", "-a", "Launcher"].concat(code === 0
                ? ["Uninstalled " + label, "Launcher entry and icon removed"]
                : ["Could not uninstall " + label, j && j.error ? j.error : src.firstLine(unErr.text, code)]))
        }
    }

    function parse(text) { try { const j = JSON.parse(text); return j && typeof j === "object" ? j : null } catch (e) { return null } }
    function firstLine(t, code) { const l = (t || "").trim().split("\n")[0]; return l !== "" ? l.slice(0, 160) : "exit code " + code }

    property var probeProc: Process {
        property int tok: 0
        stdout: StdioCollector { id: probeOut }
        stderr: StdioCollector { id: probeErr }
        onExited: code => {
            if (tok !== src.token) return
            const j = src.parse(probeOut.text)
            if (code !== 0 || !j || !j.url) {
                src.phase = "url"; src.pendingName = ""; src.error = j && j.error ? j.error : src.firstLine(probeErr.text, code)
                src.updated(); Qt.callLater(() => src.prompt(src.urlRow())); return
            }
            src.url = j.url; src.host = j.host || src.host; src.suggestion = j.name || j.host
            const ic = (j.icons || [])[0]
            src.iconNote = !j.reachable ? "letter icon" : ic && ic.kind !== "ico" ? "icon from the site" : ic ? "favicon" : "letter icon"
            src.warn = j.reachable ? "" : "page not reachable (" + j.error + ")"
            if (src.pendingName !== "") { src.startInstall(src.pendingName); return }
            src.phase = "name"
            src.updated()
            Qt.callLater(() => src.suggest(src.nameRow(), src.suggestion))
        }
    }
    property var installProc: Process {
        property int tok: 0
        stdout: StdioCollector { id: instOut }
        stderr: StdioCollector { id: instErr }
        onExited: code => {
            if (tok !== src.token) return
            const j = src.parse(instOut.text)
            if (code !== 0 || !j || !j.desktop) {
                src.phase = "error"; src.error = j && j.error ? j.error : src.firstLine(instErr.text, code); src.updated(); return
            }
            const iconFile = (j.iconFiles || []).find(f => /\.png$/.test(f)) || ""
            Quickshell.execDetached(["notify-send", "-a", "Launcher"].concat(iconFile ? ["-i", iconFile] : []).concat(
                ["Installed " + j.name, "Web app for " + src.host + (j.iconSource === "letter tile" ? " (letter icon: the site has none)" : "")]))
            src.phase = "url"; src.url = ""
            src.finished()
        }
    }
}
