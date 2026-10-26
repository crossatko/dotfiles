import QtQuick
import Quickshell

// Source: installed applications (DesktopEntries). Contract shared by every launcher source:
//   property var items            static item array (rebuilt when it changes)
//   function dynamic(query)       optional, extra items for the current query (appended after the ranked results)
//   function run(item)            optional, runs an item of this source; return true when handled
QtObject {
    id: src

    property var byId: ({})
    property var items: build()

    function webappSlug(a) {
        const m = /^webapp_([a-z0-9][a-z0-9_.-]{0,63})$/.exec(a.id || "")
        const cmd = a.command || []
        return m && cmd.some(c => String(c).startsWith("--app=")) && /(brave|chrom)/.test(String(cmd[0] || "")) ? m[1] : ""
    }

    function build() {
        const out = [], map = {}
        for (const a of DesktopEntries.applications.values) {
            if (a.noDisplay) continue
            map[a.id] = a
            const kw = [a.genericName, a.comment].concat(a.keywords || []).filter(s => s && s.length > 0)
            out.push({
                id: "app:" + a.id,
                name: a.name,
                subtitle: a.genericName || a.comment || "",
                keywords: kw,
                kind: "app",
                source: "Application",
                icon: a.icon || "",
                glyph: "",                 // cube
                desktopId: a.id,
                argv: (a.runInTerminal ? [] : (a.command || [])).map(String),   // launch command, matched to Hyprland binds (Binds.keysForApp)
                // web apps from bin/webapp-install (or the old create_brave_webapp function): webapp_<slug>.desktop running
                // a browser with --app=; Ctrl+K offers "Uninstall webapp" (WebappSource.action)
                actions: webappSlug(a) ? [{ id: "webapp-uninstall", label: "Uninstall webapp", glyph: "\uf1f8", confirm: true,
                                           confirmText: "Uninstall " + a.name + "?", sub: "Removes its launcher entry and icon; site data stays in Brave" }] : [],
                webappSlug: webappSlug(a)
            })
        }
        byId = map
        return out
    }

    // the scan can still be running right after login: rebuild when entries arrive
    property var conn: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { src.items = src.build() }
    }
    // a rescan that only changes existing entries in place (a web app reinstalled with a new Icon= / Name=) leaves the
    // list itself unchanged, so valuesChanged does not fire: rebuild on every finished scan too
    property var rescan: Connections {
        target: DesktopEntries
        function onApplicationsChanged() { src.items = src.build() }
    }
    Component.onCompleted: DesktopEntries.applications.values.length

    function run(item) {
        if (item.kind !== "app") return false
        const e = byId[item.desktopId]
        if (!e) return true
        if (e.runInTerminal) Quickshell.execDetached(["ghostty", "-e"].concat(e.command))
        else e.execute()
        // same launch log Menu.qml writes, so the old launcher's ordering keeps learning too
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.cache/qmenu\" && printf '%s\\n' \"$1\" >> \"$HOME/.cache/qmenu/drun-history\"", "sh", item.desktopId])
        return true
    }

    // opens the file manager on the .desktop file (searched in the XDG data dirs)
    function reveal(item) {
        Quickshell.execDetached(["sh", "-c",
            "IFS=:; for d in \"${XDG_DATA_HOME:-$HOME/.local/share}\" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do " +
            "f=\"$d/applications/$1.desktop\"; [ -f \"$f\" ] && exec nautilus --select \"$f\"; done", "sh", item.desktopId])
    }
}
