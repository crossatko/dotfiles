import QtQuick
import Quickshell
import Quickshell.Io

// Source: open windows (`hyprctl clients -j`), refreshed whenever the launcher opens (`active` follows Launcher.shown).
// Enter focuses the window by address. Items are transient (not recorded in usage.json, no pin/hide).
// $LAUNCHER_CLIENTS_JSON = path of a JSON file used instead of hyprctl (tests).
QtObject {
    id: src

    property bool active: false
    property var items: []

    onActiveChanged: if (active && !proc.running) proc.running = true

    readonly property string fake: Quickshell.env("LAUNCHER_CLIENTS_JSON")

    property var proc: Process {
        command: src.fake !== "" ? ["cat", src.fake] : ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                try { arr = JSON.parse(text) } catch (e) { return }
                const out = []
                for (const c of arr) {
                    if (c.mapped === false || !/^0x[0-9a-f]+$/.test(c.address || "")) continue
                    const cls = c.class || c.initialClass || ""
                    if (cls === "" && !c.title) continue
                    const ws = c.workspace && c.workspace.name ? c.workspace.name : ""
                    out.push({
                        id: "win:" + c.address,
                        name: c.title || cls,
                        subtitle: cls + (ws ? " · workspace " + ws : ""),
                        keywords: [cls, c.initialClass || ""].filter(s => s),
                        kind: "window",
                        source: "Window",
                        icon: cls.toLowerCase(),
                        glyph: "\uf2d0",                // window-maximize
                        transient: true,
                        address: c.address
                    })
                }
                src.items = out
            }
        }
    }

    function run(item) {
        if (item.kind !== "window") return false
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({window=\"address:" + item.address + "\"})"])
        return true
    }
}
