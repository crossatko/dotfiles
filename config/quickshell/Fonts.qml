pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The two chosen fonts (Settings > Look > Type): `ui` for the shell, GTK / Qt / KDE, hyprlock, Vesktop and the Twitch app,
// `mono` for the terminals (ghostty, kitty, alacritty) and hyprtoolkit's monospace. Saved in
// ${XDG_STATE_HOME:-~/.local/state}/quickshell/fonts.json (QS_FONTS_FILE overrides), this singleton is the only writer
// (atomic); the file is watched, so a hand edit shows here too.
//   { "version": 1, "ui": "Paper Mono", "mono": "Paper Mono" }
// A save runs `theme.py fonts` (detached, a moment later): it reads the same file, re-renders the font files in
// ~/.config/theme/out and reloads the apps that can. A family that is no longer installed (or a missing / malformed
// field) counts as Paper Mono, here and in theme.py.
//   qs ipc call fonts get | set <ui|mono> <family> | reset | list
Singleton {
    id: fonts

    readonly property string defaultFamily: "Paper Mono"
    readonly property string filePath: {
        const env = Quickshell.env("QS_FONTS_FILE")
        return env ? String(env) : Appearance.dir + "/fonts.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    // test hook: the program that lists the installed families (bin/font-families)
    readonly property string lister: Quickshell.env("QS_FONT_FAMILIES") || Quickshell.shellDir + "/bin/font-families"
    // test hook: the program that re-renders the themed apps
    readonly property string themeCmd: Quickshell.env("QS_FONTS_THEME_CMD") || Theme.themeDir + "/theme.py"

    // what was saved
    property string uiChoice: defaultFamily
    property string monoChoice: defaultFamily
    // installed families, [] until the first listing finishes
    property var uiList: []
    property var monoList: []
    readonly property bool listed: uiList.length > 0

    // what is used: the choice, or Paper Mono when the listing says it is gone
    readonly property string ui: !listed || uiList.indexOf(uiChoice) >= 0 ? uiChoice : defaultFamily
    readonly property string mono: !listed || monoList.indexOf(monoChoice) >= 0 ? monoChoice : defaultFamily
    readonly property bool changed: uiChoice !== defaultFamily || monoChoice !== defaultFamily

    function valid(v) { return typeof v === "string" && v.length > 0 && v.length <= 100 && !/[\x00-\x1f"'\\{}$`;]/.test(v) }
    function set(key, v) {
        if (!valid(v)) return false
        if (key === "ui") uiChoice = v
        else if (key === "mono") monoChoice = v
        else return false
        saver.restart()
        return true
    }
    function reset() { uiChoice = defaultFamily; monoChoice = defaultFamily; saver.restart() }

    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const d = o !== null && typeof o === "object" && !Array.isArray(o) ? o : {}
        uiChoice = valid(d.ui) ? d.ui : defaultFamily
        monoChoice = valid(d.mono) ? d.mono : defaultFamily
    }
    function serialize() { return JSON.stringify({ version: 1, ui: uiChoice, mono: monoChoice }) + "\n" }

    function refreshList() { if (!listProc.running) listProc.running = true }
    Process {
        id: listProc
        command: [fonts.lister]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text)
                    if (Array.isArray(o.ui) && Array.isArray(o.mono)) { fonts.uiList = o.ui; fonts.monoList = o.mono }
                } catch (e) {}
            }
        }
    }

    property string lastText: ""
    Timer {
        id: saver
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", fonts.dir])
            writer.restart()
        }
    }
    // mkdir runs detached: a moment before the write; the re-render after it reads the file
    Timer {
        id: writer
        interval: 150
        onTriggered: { fonts.lastText = fonts.serialize(); fileView.setText(fonts.lastText); render.restart() }
    }
    Timer {
        id: render
        interval: 400
        // detached, not a Process: closing Settings must not kill a half-done render
        onTriggered: Quickshell.execDetached(["python3", "-I", fonts.themeCmd, "fonts"])
    }

    Component.onCompleted: { fileView.text(); refreshList() }
    FileView {
        id: fileView
        path: fonts.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: if (!saver.running && !writer.running && text() !== fonts.lastText) { fonts.lastText = text(); fonts.parse(text()) }
        onLoadFailed: if (!saver.running && !writer.running) fonts.parse("")
    }

    IpcHandler {
        target: "fonts"
        function get(): string { return JSON.stringify({ ui: fonts.ui, mono: fonts.mono, uiChoice: fonts.uiChoice, monoChoice: fonts.monoChoice }) }
        function set(key: string, family: string): string { return fonts.set(key, family) ? "ok" : "bad" }
        function reset(): string { fonts.reset(); return "ok" }
        function list(): string { fonts.refreshList(); return JSON.stringify({ ui: fonts.uiList, mono: fonts.monoList }) }
    }
}
