pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which bar widgets are shown (global: the same on every bar). Saved in
// ~/.local/state/quickshell/bar-widgets.json as { "<widget id>": false, ... }; only an explicit `false`
// hides a widget, so a missing / corrupt file or a widget added later simply shows up. Changed from the
// control center's settings (gear) section. The notifications / control-center chip is not listed: it
// opens that section, so it must always stay on the bar.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"

    // order = order of the switches in the settings section (bar order, left to right)
    readonly property var widgets: [
        { id: "workspaces", title: "Workspaces",   icon: "" },
        { id: "media",      title: "Now playing",  icon: "" },
        { id: "caffeine",   title: "Keep awake",   icon: "" },
        { id: "cpu",        title: "CPU",          icon: "" },
        { id: "memory",     title: "Memory",       icon: "" },
        { id: "volume",     title: "Volume",       icon: "" },
        { id: "network",    title: "Network",      icon: "" },
        { id: "bluetooth",  title: "Bluetooth",    icon: "" },
        { id: "tray",       title: "Tray",         icon: "" },
        { id: "clock",      title: "Clock",        icon: "" }
    ]

    property var data: ({})                    // widget id -> false (hidden)

    function shown(id) { return data[id] !== false }
    readonly property int shownCount: widgets.filter(w => shown(w.id)).length

    function set(id, value) {
        const d = Object.assign({}, data)
        if (value) delete d[id]; else d[id] = false
        data = d
        saver.restart()
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])
    Timer { id: saver; interval: 400; onTriggered: file.setText(JSON.stringify(root.data, null, 2)) }

    FileView {
        id: file
        path: root.dir + "/bar-widgets.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.data = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
            } catch (e) { root.data = ({}) }
        }
        onLoadFailed: root.data = ({})          // missing file: everything visible
    }
}
