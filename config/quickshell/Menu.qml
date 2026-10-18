import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Replacement for tofi. Same look (full-screen dim, text block at 35% / 30%, 24pt
// Paper Mono, accent-colored prompt and selection, 8 results, 10px spacing); fzf does
// the fuzzy matching and Theme.qml supplies the colors.
//   qs ipc call menu drun                  application launcher
//   <choices> | qmenu --prompt-text 'X: '  dmenu mode, prints the chosen line (see bin/qmenu)
PanelWindow {
    id: menu

    property bool shown: false
    property string mode: "drun"          // "drun" | "dmenu"
    property string prompt: "run: "
    property string dir: ""               // dmenu: temp dir holding `items` and the `out` fifo
    property string query: ""
    property var results: []
    property int sel: 0
    property int first: 0                 // first visible result (scroll offset)
    property string drunItems: ""
    property var drunById: ({})
    property bool replied: false

    readonly property int numResults: 8
    readonly property string historyFile: "$HOME/.cache/qmenu/drun-history"

    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    color: Theme.alpha(Theme.bg, 0.67)     // tofi: background-color = <bg>aa
    exclusiveZone: -1
    // "launcher" is the namespace tofi used, so the existing blur layer rule applies unchanged
    WlrLayershell.namespace: "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function begin() {
        if (shown) close()
        screen = Popups.focusedScreen()
        query = ""; input.text = ""
        results = []; sel = 0; first = 0
        replied = false
        shown = true
        input.forceActiveFocus()
    }

    function openDrun() {
        if (shown && mode === "drun") { close(); return }
        mode = "drun"; prompt = "run: "   // tofi-drun's default prompt
        begin()
        history.running = true            // frecency from the launch log, then build + filter
    }

    function openDmenu(p, d) {
        mode = "dmenu"; prompt = p; dir = d
        begin()
        runFzf()
    }

    // application list, most-launched first, then alphabetical. Ranking = our own launch log
    // (by desktop id) + tofi's old history (by name, read-only) so your usual order carries over.
    property string lastRaw: ""
    function buildDrun(raw) {
        lastRaw = raw
        const [mine, tofi] = raw.split("---tofi\n")
        const byIdCount = {}, byName = {}
        for (const l of (mine || "").split("\n")) if (l) byIdCount[l] = (byIdCount[l] || 0) + 1
        for (const l of (tofi || "").split("\n")) {
            const m = l.match(/^(\d+) (.*)$/)
            if (m) byName[m[2]] = parseInt(m[1])
        }
        const score = a => (byIdCount[a.id] || 0) + (byName[a.name] || 0)
        const apps = DesktopEntries.applications.values.filter(a => !a.noDisplay)
        apps.sort((a, b) => score(b) - score(a) || a.name.localeCompare(b.name))
        const byId = {}, lines = []
        for (const a of apps) {
            byId[a.id] = a
            lines.push(a.name.replace(/[\t\n]/g, " ") + "\t" + a.id)
        }
        drunById = byId
        drunItems = lines.join("\n")
        runFzf()
    }

    // Right after login Quickshell is still scanning the .desktop files, so the first open could find
    // an empty list. Touch the model at startup so the scan begins early, and rebuild the open
    // launcher as soon as entries arrive.
    Component.onCompleted: DesktopEntries.applications.values.length
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { if (menu.shown && menu.mode === "drun" && menu.lastRaw !== "") menu.buildDrun(menu.lastRaw) }
    }

    Process {
        id: history
        command: ["sh", "-c", "{ tail -n 3000 \"" + menu.historyFile + "\" 2>/dev/null; echo '---tofi'; cat \"$HOME/.local/state/tofi-drun-history\" 2>/dev/null; }"]
        stdout: StdioCollector { onStreamFinished: menu.buildDrun(text) }
    }

    // one fzf run at a time; a keystroke during a run just flags a re-run
    property bool dirty: false
    function runFzf() {
        if (fz.running) { dirty = true; return }
        if (mode === "drun") {
            fz.environment = ({ "QM_ITEMS": drunItems })
            fz.command = ["sh", "-c",
                "T=$(printf '\\t'); printf '%s\\n' \"$QM_ITEMS\" | fzf --filter \"$1\" --delimiter \"$T\" --nth 1 --tiebreak=index | head -n 300",
                "sh", query]
        } else {
            fz.command = ["sh", "-c",
                "fzf --filter \"$1\" --tiebreak=index < \"$2/items\" | head -n 300",
                "sh", query, dir]
        }
        fz.running = true
    }
    Process {
        id: fz
        stdout: StdioCollector {
            onStreamFinished: {
                menu.results = text.split("\n").filter(l => l.length > 0)
                menu.sel = 0; menu.first = 0
                if (menu.dirty) { menu.dirty = false; menu.runFzf() }
            }
        }
    }

    function reply(text) {
        replied = true
        // the fifo is already being read by qmenu; an empty write signals "cancelled"
        Quickshell.execDetached(["sh", "-c",
            "if [ -n \"$1\" ]; then printf '%s\\n' \"$1\" > \"$2/out\"; else : > \"$2/out\"; fi", "sh", text, dir])
    }

    function accept() {
        const line = results[sel]
        if (line === undefined) { close(); return }
        if (mode === "dmenu") { shown = false; reply(line); return }
        const id = line.split("\t")[1]
        const e = drunById[id]
        shown = false
        if (!e) return
        if (e.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(e.command))
        else e.execute()
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.cache/qmenu\" && printf '%s\\n' \"$1\" >> \"" + historyFile + "\"", "sh", id])
    }

    // one click-away thing at a time; a click on another monitor (ClickCatcher) closes it too
    onShownChanged: shown ? Popups.opened("menu", screen ? screen.name : "") : Popups.closed("menu")
    Connections {
        target: Popups
        function onDismiss(except) { if (except !== "menu" && menu.shown) menu.close() }
    }

    function close() {
        const wasOpen = shown
        shown = false
        if (wasOpen && mode === "dmenu" && !replied) reply("")
    }

    function move(d) {
        if (results.length === 0) return
        sel = Math.max(0, Math.min(results.length - 1, sel + d))
        if (sel < first) first = sel
        else if (sel >= first + numResults) first = sel - numResults + 1
    }

    MouseArea { anchors.fill: parent; onClicked: menu.close() }

    Item {
        anchors.fill: parent

        Column {
            x: parent.width * 0.35        // tofi: padding-left = 35%
            y: parent.height * 0.30       // tofi: padding-top = 30%
            spacing: 10                   // tofi: result-spacing = 10

            Row {
                Text {
                    id: promptText
                    text: menu.prompt
                    color: Theme.accent
                    font.family: Theme.font
                    font.pointSize: 24
                }
                TextInput {
                    id: input
                    color: Theme.fg
                    font.family: Theme.font
                    font.pointSize: 24
                    cursorDelegate: Item {}
                    onTextChanged: { menu.query = text; if (menu.shown) menu.runFzf() }

                    Keys.onPressed: ev => {
                        const ctrl = ev.modifiers & Qt.ControlModifier
                        if (ev.key === Qt.Key_Escape) { menu.close(); ev.accepted = true }
                        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { menu.accept(); ev.accepted = true }
                        else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab || (ctrl && (ev.key === Qt.Key_N || ev.key === Qt.Key_J))) { menu.move(1); ev.accepted = true }
                        else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab || (ctrl && (ev.key === Qt.Key_P || ev.key === Qt.Key_K))) { menu.move(-1); ev.accepted = true }
                        else if (ev.key === Qt.Key_PageDown) { menu.move(menu.numResults); ev.accepted = true }
                        else if (ev.key === Qt.Key_PageUp) { menu.move(-menu.numResults); ev.accepted = true }
                        else if (ctrl && ev.key === Qt.Key_U) { text = ""; ev.accepted = true }
                        else if (ctrl && ev.key === Qt.Key_W) { text = text.replace(/\s*\S*\s*$/, ""); ev.accepted = true }
                        else if (ctrl && ev.key === Qt.Key_C) { menu.close(); ev.accepted = true }
                    }
                }
            }

            // results line up with the input text, as in tofi
            Column {
                x: promptText.width
                spacing: 10
                Repeater {
                    model: menu.results.slice(menu.first, menu.first + menu.numResults)
                    Text {
                        required property string modelData
                        required property int index
                        text: modelData.split("\t")[0]
                        color: (menu.first + index === menu.sel) ? Theme.accent : Theme.fg
                        font.family: Theme.font
                        font.pointSize: 24
                        elide: Text.ElideRight
                        width: menu.width * 0.6
                    }
                }
            }
        }
    }
}
