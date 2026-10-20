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
                desktopId: a.id
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
    Component.onCompleted: DesktopEntries.applications.values.length

    function run(item) {
        if (item.kind !== "app") return false
        const e = byId[item.desktopId]
        if (!e) return true
        if (e.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(e.command))
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
