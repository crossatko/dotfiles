import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "launcher"
import "launcher/js/Ranker.js" as Ranker
import "launcher/js/Frecency.js" as Frecency

// Raycast-style launcher (beside Menu.qml, which stays on SUPER+D): a ModalMenu card (layer "qs-launcher") with a
// search field, a ranked result list (apps, commands, web-search fallbacks), quick-run badges and an action panel.
//   qs ipc call launcher toggle | show | hide
// Items come from sources (launcher/*Source.qml): each has `items` (static array), optionally dynamic(query) and
// run(item). To add a source: declare it below, add it to `sourceList`. Ranking and frecency: launcher/js/.
// State: ~/.local/state/launcher/usage.json (usage map), history.json (last 20 queries);
// optional ~/.config/launcher/config.json = { "aliases": { "<item id>": ["alias", ...] } }.
ModalMenu {
    id: lc

    kind: "launcher"
    cardWidth: 640
    // always the main display (Hyprland's monitors.primary = monitor1 sits at 0,0 on the workstation / VM hosts), and
    // inside its usable area (bar reserve + monitor reserved_area), so the card centres there
    fixedScreen: Quickshell.screens.find(s => s.x === 0 && s.y === 0) || Quickshell.screens[0]
    respectReserved: true
    focusItem: input
    // header follows the context: action panel (item name), argument prompt (item name), section, prefix mode, else "Launcher"
    readonly property var modeSource: section === "" && !argItem && query.trim() !== ""
        ? (sourceList.find(s => s.exclusive && s.exclusive(query.trim(), query)) || null) : null
    readonly property string rocket: "\uf135"
    title: actionsOpen && current ? current.name
        : argItem ? argItem.name
        : section !== "" ? secSrc.header(section)
        : modeSource ? modeSource.modeTitle : "Launcher"
    titleSub: actionsOpen || argItem ? "" : section !== "" ? secSrc.headerSub(section) : ""
    icon: actionsOpen ? rocket
        : argItem ? (argItem.glyph || rocket)
        : section !== "" ? (secSrc.glyph(section) || rocket)
        : modeSource ? modeSource.modeGlyph : rocket

    property string query: ""
    property var results: []
    property int sel: 0
    property int first: 0                           // first visible result (scroll offset)
    property bool actionsOpen: false
    property int asel: 0                            // selected action
    property var usage: ({})
    property var history: []                        // last 20 queries, newest first
    property int histPos: -1                        // -1 = not recalling
    property var aliases: ({})
    property var argItem: null                      // item waiting for its text argument (item.argument set)
    property string argQuery: ""                    // the search text before the argument prompt

    property string section: ""                     // "" = main list; else the open sub-menu (SectionsSource: sound-output, sound-input, power, twitch, screenshot, record)
    property bool sectionDirect: false              // section opened by IPC / keybind (openSection), not from the main list: Esc closes instead of going back
    property string confirmId: ""                   // section item waiting for a second Enter (destructive power actions)

    readonly property int numResults: 8
    readonly property int rowH: 46
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/launcher"
    readonly property var current: results[sel]

    // sources: add new ones here
    AppsSource { id: appsSrc }
    CommandsSource { id: cmdSrc }
    WebSource { id: webSrc }
    ScriptSource { id: scriptSrc; active: lc.shown }
    CalcSource { id: calcSrc; onUpdated: lc.refreshKeep() }
    WindowSource { id: winSrc; active: lc.shown }
    EmojiSource { id: emojiSrc }
    FileSource { id: fileSrc; onUpdated: lc.refreshKeep() }
    ClipboardSource { id: clipSrc; active: lc.shown; onUpdated: lc.refreshKeep() }
    SectionsSource { id: secSrc; onUpdated: lc.refreshKeep() }
    readonly property var sourceList: [appsSrc, winSrc, cmdSrc, secSrc, scriptSrc, calcSrc, emojiSrc, fileSrc, clipSrc, webSrc]

    readonly property var allItems: {
        const out = []
        for (const s of sourceList)
            for (const it of s.items) {
                const al = aliases[it.id]
                out.push(al && al.length ? Object.assign({}, it, { aliases: al }) : it)
            }
        return out
    }
    onAllItemsChanged: if (shown && section === "") refresh()   // section rows do not depend on the main list

    // Sources may be async: they emit updated() and the launcher calls refreshKeep() (same list, selection kept).
    // A source with exclusive(q) true (prefix modes: ":" emoji, "/" files) owns the whole list for that query.
    // dynamic() items with `top: true` go above the ranked results.
    function refresh(keep) {
        const q = query.trim()
        if (section !== "") {                           // inside a section: only its rows, filtered with the ranker (no usage)
            let rows = secSrc.rows(section)
            if (q !== "") rows = secSrc.extra(section, q).concat(Ranker.rank(rows, q, {}, Date.now(), { limit: 50 }).map(r => r.item))
            const prevId = keep && results[sel] ? results[sel].id : ""
            const hadStop = results.some(r => r.kind === "rec-stop")
            results = rows.map(it => it.id === confirmId
                ? Object.assign({}, it, { name: "Confirm: " + it.name, subtitle: "Press Enter again to confirm", glyph: "\uf071", iconColor: "red" })
                : it)
            let i = 0
            if (keep) {                                 // same row stays selected (rows can shift: Stop recording appears once the status is known)
                i = results.findIndex(r => r.id === prevId)
                if (i < 0) i = Math.min(sel, results.length - 1)
                if (!hadStop && q === "" && results.some(r => r.kind === "rec-stop")) i = 0
            } else if (q === "") i = secSrc.startSel(section)   // sections reopen on the last used capture mode
            sel = Math.max(0, i)
            first = keep ? Math.min(first, sel) : 0
            if (sel >= first + numResults) first = sel - numResults + 1
            return
        }
        let list, top = [], tail = []
        const ex = q === "" ? null : sourceList.find(s => s.exclusive && s.exclusive(q, query))   // 2nd arg: raw (untrimmed) text
        if (ex) list = ex.dynamic(q, query)
        else {
            list = Ranker.rank(allItems, q, usage, Date.now(), { limit: 50 }).map(r => r.item)
            if (q !== "")
                for (const s of sourceList)
                    if (s.dynamic)
                        for (const it of s.dynamic(q, query)) (it.top ? top : tail).push(it)
            list = top.concat(list, tail)
        }
        results = list
        if (keep) { sel = Math.min(sel, Math.max(0, list.length - 1)); first = Math.min(first, sel) }
        else { sel = 0; first = 0 }
    }
    function refreshKeep() { if (shown && !argItem) refresh(true) }

    function clearConfirm() { if (confirmId !== "") { confirmId = ""; if (shown) refresh(true) } }
    onQueryChanged: { confirmId = ""; if (shown && !argItem) refresh() }
    onSelChanged: clearConfirm()
    onOpening: {
        actionsOpen = false; histPos = -1; argItem = null; confirmId = ""
        section = presetSection
        sectionDirect = section !== ""
        if (section !== "") secSrc.enter(section)
        presetSection = ""
        query = preset; input.text = preset; preset = ""
        refresh()
    }

    // ---- sections (sub-menus: sound output / input, power, twitch) ------------------------------------------------
    property string presetSection: ""
    function enterSection(name) {
        if (!secSrc.title(name)) return
        section = name; sectionDirect = false; confirmId = ""; actionsOpen = false; histPos = -1
        secSrc.enter(name)
        input.text = ""
        refresh()
    }
    // qs ipc call launcher section <name>: open straight inside the section; a second call for the same section closes
    function openSection(name) {
        if (!secSrc.title(name)) return
        if (shown) {
            if (argItem || actionsOpen) return
            if (section === name) close(); else { enterSection(name); sectionDirect = true }
            return
        }
        presetSection = name
        open()
    }
    // Esc / Ctrl+C: one level back (section -> main list), at the root close
    function back() {
        if (section === "") { close(); return }
        section = ""; sectionDirect = false; confirmId = ""; histPos = -1
        input.text = ""
        refresh()
    }
    // Key handlers shared by the search field's Keys.onPressed.
    // Esc / Ctrl+C: a section entered from the main list goes one level back, a section opened directly (keybind / IPC) closes
    function keyEscape() {
        if (section !== "" && !sectionDirect) back(); else close()
    }
    // Left = back out of a section, but only when it would not move the text caret (empty filter, or caret at 0 without selection)
    function keyLeft() {
        if (section === "" || actionsOpen || argItem) return false
        if (input.text !== "" && (input.cursorPosition !== 0 || input.selectionStart !== input.selectionEnd)) return false
        back()
        return true
    }

    // open with the search field prefilled (qs ipc call launcher query "v "); on an open launcher just sets the text
    property string preset: ""
    function openWith(q) {
        if (shown && !argItem && !actionsOpen) { input.text = q; input.cursorPosition = q.length; return }
        preset = q
        open()
        input.cursorPosition = input.text.length
    }

    function move(d) {
        if (results.length === 0) return
        sel = Math.max(0, Math.min(results.length - 1, sel + d))
        if (sel < first) first = sel
        else if (sel >= first + numResults) first = sel - numResults + 1
    }

    // ---- running -----------------------------------------------------------------------------------------
    function runItem(item, arg) {
        if (!item) { close(); return }
        if (item.kind === "info") return                 // loading / error rows in a section
        if (item.kind === "section") {                   // root row: push the section (the entry itself is recorded)
            usage = Frecency.record(usage, item.id, query.trim().toLowerCase(), Date.now())
            saveUsage.restart()
            enterSection(item.section)
            return
        }
        if (item.kind === "rec-opt") {                   // recording options: toggle, save, stay open
            secSrc.run(item)
            refresh(true)
            return
        }
        if (item.confirm && confirmId !== item.id) {     // destructive: ask for a second Enter first
            confirmId = item.id
            refresh(true)
            return
        }
        if (item.argument && arg === undefined) {       // ask for the argument first
            argQuery = query.trim(); argItem = item
            input.text = ""
            return
        }
        const q = argItem ? argQuery : query.trim()
        argItem = null
        shown = false
        for (const s of sourceList)
            if (s.run && s.run(item, arg)) break
        if (item.kind !== "web" && !item.transient) {
            usage = Frecency.record(usage, item.id, q.toLowerCase(), Date.now())
            saveUsage.restart()
        }
        if (q !== "" && !item.private) {                 // private items (clipboard): the query text is never kept
            history = [q].concat(history.filter(h => h !== q)).slice(0, 20)
            saveHistory.restart()
        }
    }

    function runIndex(i) { if (i >= 0 && i < results.length) runItem(results[i]) }

    // ---- actions (Ctrl+K) ----------------------------------------------------------------------------------
    readonly property var actions: {
        const it = current
        if (!it) return []
        const u = usage[it.id] || {}
        const a = [{ id: "run", label: "Run", glyph: "" }]
        if (it.kind !== "web" && !it.transient) {
            a.push({ id: "pin", label: u.pinned ? "Unpin" : "Pin", glyph: "" })       // thumbtack
            a.push({ id: "hide", label: "Hide", glyph: "" })                        // eye-slash
        }
        if (it.kind === "app") a.push({ id: "reveal", label: "Open .desktop location", glyph: "" })   // folder-open
        return a.concat(it.actions || [])
    }

    function doAction(id) {
        const it = current
        if (!it) { actionsOpen = false; return }
        if (id === "run") { runItem(it); return }
        if (id === "pin") {
            usage = Frecency.setPinned(usage, it.id, !(usage[it.id] && usage[it.id].pinned))
            saveUsage.restart()
        } else if (id === "hide") {
            usage = Frecency.setHidden(usage, it.id, true)
            saveUsage.restart()
        } else if (id === "reveal") {
            shown = false
            appsSrc.reveal(it)
            return
        } else {                                        // item-specific actions (it.actions), handled by the source
            for (const s of sourceList)
                if (s.action) {
                    const r = s.action(id, it)
                    if (r === "keep") { actionsOpen = false; refresh(true); return }   // stays open (e.g. clipboard delete)
                    if (r) { shown = false; return }
                }
        }
        actionsOpen = false
        refresh()
    }

    function openActions() {
        if (!current) return
        asel = 0
        actionsOpen = true
    }

    // ---- state files -------------------------------------------------------------------------------------
    Component.onCompleted: mkdir.running = true
    Process {
        id: mkdir
        command: ["mkdir", "-p", lc.stateDir, Quickshell.env("HOME") + "/.config/launcher"]
        onExited: { usageFile.reload(); historyFile.reload(); configFile.reload() }
    }
    Timer { id: saveUsage; interval: 300; onTriggered: usageFile.setText(JSON.stringify(lc.usage) + "\n") }
    Timer { id: saveHistory; interval: 300; onTriggered: historyFile.setText(JSON.stringify(lc.history) + "\n") }

    FileView {
        id: usageFile
        path: lc.stateDir + "/usage.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const u = JSON.parse(text())
                if (u && typeof u === "object" && !Array.isArray(u)) lc.usage = Frecency.prune(u, Date.now())
            } catch (e) {}
            if (lc.shown) lc.refresh()
        }
    }
    FileView {
        id: historyFile
        path: lc.stateDir + "/history.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const h = JSON.parse(text())
                if (Array.isArray(h)) lc.history = h.filter(s => typeof s === "string").slice(0, 20)
            } catch (e) {}
        }
    }
    FileView {
        id: configFile
        path: Quickshell.env("HOME") + "/.config/launcher/config.json"
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text())
                if (c && c.aliases && typeof c.aliases === "object") lc.aliases = c.aliases
            } catch (e) {}
        }
    }

    // ---- search field ------------------------------------------------------------------------------------
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
                onTextChanged: lc.query = text
                onTextEdited: lc.histPos = -1

                Label {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: lc.argItem ? lc.argItem.name + ": " + lc.argItem.argument : lc.section !== "" ? "Filter..." : "Search apps, windows, commands · : emoji · / files"
                    color: Theme.muted
                    font.pixelSize: 14
                }

                function recall(pos) {
                    lc.histPos = pos
                    text = pos < 0 ? "" : lc.history[pos]
                    cursorPosition = text.length
                }

                Keys.onPressed: ev => {
                    const ctrl = ev.modifiers & Qt.ControlModifier
                    const k = ev.key
                    ev.accepted = true
                    if (lc.argItem) {
                        if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_C)) { lc.argItem = null; text = lc.argQuery }
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) lc.runItem(lc.argItem, text)
                        else ev.accepted = false
                        return
                    }
                    if (lc.actionsOpen) {
                        const n = lc.actions.length
                        if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_K) || k === Qt.Key_Left) lc.actionsOpen = false
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) lc.doAction(lc.actions[lc.asel].id)
                        else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) lc.asel = Math.min(n - 1, lc.asel + 1)
                        else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_P)) lc.asel = Math.max(0, lc.asel - 1)
                        else ev.accepted = false
                        return
                    }
                    if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_C)) lc.keyEscape()
                    else if (k === Qt.Key_Left && !ctrl && !(ev.modifiers & Qt.ShiftModifier) && lc.keyLeft()) {}
                    else if (k === Qt.Key_Backspace && !ctrl && lc.section !== "" && text === "") lc.back()
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) lc.runIndex(lc.sel)
                    else if (ctrl && k === Qt.Key_K) lc.openActions()
                    else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_9) lc.runIndex(lc.first + (k - Qt.Key_1))
                    else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) {
                        if (lc.histPos >= 0) recall(lc.histPos - 1)
                        else lc.move(1)
                    }
                    else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_P)) {
                        if ((text === "" || lc.histPos >= 0) && lc.sel === 0 && lc.history.length > 0)
                            recall(Math.min(lc.history.length - 1, lc.histPos + 1))
                        else lc.move(-1)
                    }
                    else if (k === Qt.Key_PageDown) lc.move(lc.numResults)
                    else if (k === Qt.Key_PageUp) lc.move(-lc.numResults)
                    else if (ctrl && k === Qt.Key_U) text = ""
                    else if (ctrl && k === Qt.Key_W) text = text.replace(/\s*\S*\s*$/, "")
                    else ev.accepted = false
                }
            }
            Label { text: lc.results.length; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
    }

    // ---- results (a window of numResults rows over `results`) ----------------------------------------------
    Item {
        id: list
        Layout.fillWidth: true
        readonly property int gap: 4
        readonly property bool scrolls: lc.results.length > lc.numResults
        implicitHeight: lc.numResults * lc.rowH + (lc.numResults - 1) * gap

        WheelHandler {
            enabled: !lc.actionsOpen
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: ev => lc.move(ev.angleDelta.y < 0 ? 1 : -1)
        }

        Column {
            visible: !lc.actionsOpen
            width: parent.width - (list.scrolls ? 10 : 0)
            spacing: list.gap
            Repeater {
                model: lc.results.slice(lc.first, lc.first + lc.numResults)
                ListRow {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: lc.first + index === lc.sel
                    readonly property string iconPath: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""

                    width: parent.width
                    rowH: lc.rowH
                    radius: Theme.radiusModal
                    icon: iconPath === "" ? (modelData.glyph || "") : ""
                    iconSize: 16
                    iconColor: modelData.iconColor === "red" ? Theme.red : sel ? Theme.accent : modelData.iconColor === "muted" ? Theme.muted : Theme.fgDim
                    outlined: sel
                    border.color: Theme.alpha(Theme.accent, 0.8)
                    color: sel ? Theme.alpha(Theme.accent, 0.26) : hovered ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                    onClicked: { lc.sel = lc.first + index; lc.runIndex(lc.sel) }

                    IconImage {
                        visible: row.iconPath !== ""
                        source: row.iconPath
                        implicitSize: 24
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }
                    RowText { title: row.modelData.name; sub: row.modelData.subtitle || "" }
                    Label {
                        text: (lc.usage[row.modelData.id] && lc.usage[row.modelData.id].pinned ? "• " : "") + row.modelData.source
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                    }
                    KeyBadge { visible: row.index < 9; text: String(row.index + 1); sel: row.sel }
                }
            }
        }

        // action panel for the selected item
        Column {
            visible: lc.actionsOpen
            width: parent.width
            spacing: list.gap
            Repeater {
                model: lc.actions
                ListRow {
                    id: arow
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === lc.asel
                    width: parent.width
                    rowH: 40
                    radius: Theme.radiusModal
                    icon: modelData.glyph
                    iconSize: 14
                    iconColor: sel ? Theme.accent : Theme.fgDim
                    outlined: sel
                    border.color: Theme.alpha(Theme.accent, 0.8)
                    color: sel ? Theme.alpha(Theme.accent, 0.26) : hovered ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                    onClicked: lc.doAction(modelData.id)
                    RowText { title: arow.modelData.label }
                }
            }
        }

        // scroll position
        Rectangle {
            visible: list.scrolls && !lc.actionsOpen
            anchors.right: parent.right
            width: 3
            radius: Math.min(1.5, Theme.radius)
            color: Theme.alpha(Theme.fg, 0.25)
            height: Math.max(16, list.height * lc.numResults / Math.max(1, lc.results.length))
            y: lc.results.length <= lc.numResults ? 0
                : (list.height - height) * lc.first / (lc.results.length - lc.numResults)
        }

        Label {
            visible: lc.results.length === 0 && !lc.actionsOpen
            anchors.centerIn: parent
            text: "No matches"
            color: Theme.muted
        }
    }

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: lc.actionsOpen ? "↑↓ select · Enter do · Esc back"
            : lc.section !== "" ? "↑↓ select · Enter run · ← / Backspace back · Esc " + (lc.sectionDirect ? "close" : "back")
            : "↑↓ select · Enter run · Ctrl+1-9 quick run · Ctrl+K actions · Esc close"
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }

}
