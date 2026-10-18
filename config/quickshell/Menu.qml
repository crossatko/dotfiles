import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// List picker (replaced tofi): a ModalMenu card (layer "qs-menu", dim scrim, Esc / click outside / X close)
// with a header per mode, a search field, up to `numResults` result rows and a key-hint footer. fzf does the
// fuzzy matching.
//   qs ipc call menu drun                  application launcher ("Applications", app icons, launch history)
//   <choices> | qmenu --prompt-text 'X: '  dmenu mode, prints the chosen line (see bin/qmenu). The prompt picks
//                                          the header: "Power: ", "Output: " (audio), "Twitch: " (streams);
//                                          anything else shows the prompt without its colon and a list icon.
// dmenu lines show the text before the first TAB; a leading "✓ " is drawn as a check mark at the row's end.
// The reply is always the full original line.
ModalMenu {
    id: menu

    kind: "menu"
    cardWidth: 600
    focusItem: input
    title: meta.title
    icon: meta.icon
    iconFamily: meta.brand ? Theme.brandFont : Theme.iconFont

    property string mode: "drun"          // "drun" | "dmenu"
    property string prompt: "run: "
    property string dir: ""               // dmenu: temp dir holding `items` and the `out` fifo
    property string query: ""
    property var results: []
    property int sel: 0
    property int first: 0                 // first visible result (scroll offset)
    property int totalCount: 0            // dmenu: number of items (sizes the list so it doesn't jump while typing)
    property bool waitingFirst: false     // dmenu: show once the first fzf result is in (list height known)
    property string drunItems: ""
    property var drunById: ({})
    property bool replied: false

    readonly property int numResults: 8
    readonly property int rowH: 38
    readonly property int rows: mode === "drun" ? numResults : Math.max(1, Math.min(numResults, totalCount))
    readonly property string historyFile: "$HOME/.cache/qmenu/drun-history"

    // header per mode; dmenu callers are told apart by their prompt
    readonly property string promptKey: prompt.replace(/[:\s]+$/, "")
    readonly property var meta: mode === "drun" ? { title: "Applications", icon: "", brand: false }          // grid-2
        : promptKey === "Power"  ? { title: "Power",        icon: "", brand: false }                        // power-off
        : promptKey === "Output" ? { title: "Audio output", icon: "", brand: false }                        // volume-high
        : promptKey === "Twitch" ? { title: "Streams",      icon: "", brand: true }                         // twitch (Brands)
        : { title: promptKey || "Menu", icon: "", brand: false }                                            // list
    readonly property var powerIcons: ({
        "sleep": "", "shutdown": "", "reboot": "", "exit hyprland": "",
        "switch to gamescope": "", "switch to kde": ""
    })

    // one display record per result line
    function rowInfo(line) {
        const text = line.split("\t")[0]
        if (mode === "drun") {
            const e = drunById[line.split("\t")[1]]
            return { title: text, extra: "", checked: false, dim: false, glyph: "", glyphColor: Theme.fgDim,   // cube
                     iconPath: e && e.icon ? Quickshell.iconPath(e.icon, true) : "" }
        }
        const checked = text.startsWith("✓ ")
        const shown = checked ? text.slice(2) : text.replace(/^\s+/, "")
        if (promptKey === "Power")
            return { title: shown, extra: "", checked: checked, dim: false, glyph: powerIcons[shown] || "", glyphColor: Theme.fgDim, iconPath: "" }
        if (promptKey === "Output")
            return { title: shown, extra: "", checked: checked, dim: false, iconPath: "", glyphColor: Theme.fgDim,
                     glyph: /navi|\btv\b|hdmi/i.test(shown) ? "" : /head|arctis|buds|airpods|hyperx|wh-1000/i.test(shown) ? "" : "" }   // tv / headphones / speaker
        if (promptKey === "Twitch") {
            // "<Name>: <game> [<viewers>]" or "<Name>: [offline]"
            const m = shown.match(/^([^:]+):\s*(.*)$/)
            const offline = shown.indexOf("[offline]") >= 0
            return { title: m ? m[1] : shown, extra: m ? m[2] : "", checked: checked, dim: offline, iconPath: "",
                     glyph: "", dot: offline ? Theme.alpha(Theme.muted, 0.5) : Theme.red, glyphColor: Theme.fgDim }   // live / offline dot
        }
        return { title: shown, extra: "", checked: checked, dim: false, glyph: "", glyphColor: Theme.fgDim, iconPath: "" }
    }

    // a dmenu that is still open when it closes (any way but accept) gets the "cancelled" reply
    onShownChanged: if (!shown && mode === "dmenu" && !replied) reply("")

    function begin(m, p, d) {
        if (shown) shown = false          // replies "" to a dmenu that is still open, before its dir is replaced
        mode = m; prompt = p; dir = d
        query = ""; input.text = ""
        results = []; sel = 0; first = 0; totalCount = 0
        replied = false
    }

    function openDrun() {
        if (shown && mode === "drun") { close(); return }
        begin("drun", "run: ", "")
        open()
        history.running = true            // frecency from the launch log, then build + filter
    }

    function openDmenu(p, d) {
        begin("dmenu", p, d)
        waitingFirst = true
        showFallback.restart()
        runFzf()
    }

    Timer { id: showFallback; interval: 300; onTriggered: if (menu.waitingFirst) { menu.waitingFirst = false; menu.open() } }

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
                if (menu.mode === "dmenu" && menu.query === "") menu.totalCount = menu.results.length
                if (menu.dirty) { menu.dirty = false; menu.runFzf() }
                else if (menu.waitingFirst) { menu.waitingFirst = false; showFallback.stop(); menu.open() }
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
        if (mode === "dmenu") { replied = true; shown = false; reply(line); return }
        const id = line.split("\t")[1]
        const e = drunById[id]
        shown = false
        if (!e) return
        if (e.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(e.command))
        else e.execute()
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.cache/qmenu\" && printf '%s\\n' \"$1\" >> \"" + historyFile + "\"", "sh", id])
    }

    function move(d) {
        if (results.length === 0) return
        sel = Math.max(0, Math.min(results.length - 1, sel + d))
        if (sel < first) first = sel
        else if (sel >= first + numResults) first = sel - numResults + 1
    }

    // search field
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.radiusModal
        color: Theme.alpha(Theme.fg, 0.07)
        border.width: 1
        border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.4) : Theme.alpha(Theme.overlay, 0.45)

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            Icon { text: ""; font.pixelSize: 14; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 22 }   // magnifying-glass
            TextInput {
                id: input
                Layout.fillWidth: true
                clip: true
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                selectedTextColor: Theme.fg
                font.family: Theme.font
                font.pixelSize: 14
                onTextChanged: { menu.query = text; if (menu.shown) menu.runFzf() }

                Label {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.mode === "drun" ? "Search applications" : "Filter"
                    color: Theme.muted
                    font.pixelSize: 14
                }

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
            Label { text: menu.results.length >= 300 ? "300+" : menu.results.length; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
    }

    // results: a window of `rows` rows over `results`, moved by the keys (and the wheel) like before
    Item {
        id: list
        Layout.fillWidth: true
        readonly property int gap: 4
        readonly property bool scrolls: menu.results.length > menu.rows
        implicitHeight: menu.rows * menu.rowH + (menu.rows - 1) * gap

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: ev => menu.move(ev.angleDelta.y < 0 ? 1 : -1)
        }

        Column {
            width: parent.width - (list.scrolls ? 10 : 0)
            spacing: list.gap
            Repeater {
                model: menu.results.slice(menu.first, menu.first + menu.rows)
                ListRow {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property bool sel: menu.first + index === menu.sel
                    readonly property var info: menu.rowInfo(modelData)

                    width: parent.width
                    rowH: menu.rowH
                    radius: Theme.radiusModal
                    icon: info.iconPath === "" ? info.glyph : ""
                    iconSize: 16
                    iconColor: sel && info.glyphColor === Theme.fgDim ? Theme.accent : info.glyphColor
                    outlined: sel
                    border.color: Theme.alpha(Theme.accent, 0.8)
                    color: sel ? Theme.alpha(Theme.accent, 0.26) : hovered ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                    onClicked: { menu.sel = menu.first + index; menu.accept() }

                    IconImage {
                        visible: row.info.iconPath !== ""
                        source: row.info.iconPath
                        implicitSize: 22
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }
                    Item {   // stream live / offline dot
                        visible: row.info.dot !== undefined
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: row.info.dot || "transparent" }
                    }
                    RowText {
                        title: row.info.title
                        titleColor: row.info.dim ? Theme.fgDim : Theme.fg
                        Layout.fillWidth: row.info.extra === ""
                        Layout.preferredWidth: row.info.extra === "" ? -1 : implicitWidth
                        Layout.maximumWidth: row.info.extra === "" ? Number.POSITIVE_INFINITY : row.width * 0.45
                    }
                    Label {
                        visible: row.info.extra !== ""
                        Layout.fillWidth: true
                        text: row.info.extra
                        color: Theme.muted
                        font.pixelSize: Theme.fontSmall
                        elide: Text.ElideRight
                    }
                    RowState { visible: row.info.checked; connected: true }
                }
            }
        }

        // scroll position
        Rectangle {
            visible: list.scrolls
            anchors.right: parent.right
            width: 3
            radius: Math.min(1.5, Theme.radius)
            color: Theme.alpha(Theme.fg, 0.25)
            height: Math.max(16, list.height * menu.rows / Math.max(1, menu.results.length))
            y: menu.results.length <= menu.rows ? 0
                : (list.height - height) * menu.first / (menu.results.length - menu.rows)
        }

        Label {
            visible: menu.results.length === 0 && menu.query !== ""
            anchors.centerIn: parent
            text: "No matches"
            color: Theme.muted
        }
    }

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "↑↓ select · Enter " + (menu.mode === "drun" ? "launch" : "choose") + " · Esc close"
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }
}
