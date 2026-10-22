import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick.Effects
import "launcher"
import "launcher/js/Ranker.js" as Ranker
import "launcher/js/Frecency.js" as Frecency

// Raycast-style launcher (beside Menu.qml, which stays on SUPER+D): a ModalMenu card (layer "qs-launcher") with a
// search field, a ranked result list (apps, commands, web-search fallbacks), quick-run badges and an action panel.
//   qs ipc call launcher toggle | show | hide
// Items come from sources (launcher/*Source.qml): each has `items` (static array), optionally dynamic(query) and
// run(item). To add a source: declare it below, add it to `sourceList`. Ranking and frecency: launcher/js/.
// State: ~/.local/state/launcher/usage.json (usage map), history.json (last 20 queries);
// optional ~/.config/launcher/config.json = { "aliases": { "<item id>": ["alias", ...] }, "screen": "<model substring>" }.
ModalMenu {
    id: lc

    kind: "launcher"
    animated: Motion.launcherMotion          // Settings -> Animations "Launcher": popup speed / curve / style
    cardWidth: 640
    // always the main display (Hyprland's monitors.primary = monitor1 sits at 0,0 on the workstation / VM hosts), and
    // inside its usable area (bar reserve + monitor reserved_area), so the card centres there
    // host override: config.json { "screen": "<text>" } = case-insensitive substring of a screen's model or name (e.g. its
    // model "MPG271QX", not the connector, which can change); no match / unset = the screen at 0,0
    property string screenMatch: ""
    fixedScreen: {
        const m = screenMatch.toLowerCase()
        const byMatch = m === "" ? null : Quickshell.screens.find(s => (s.model || "").toLowerCase().includes(m) || (s.name || "").toLowerCase() === m)
        return byMatch || Quickshell.screens.find(s => s.x === 0 && s.y === 0) || Quickshell.screens[0]
    }
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
        : argItem ? (argItem.argGlyph || argItem.glyph || rocket)
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
    property string argNote: ""                     // footer note under an argument prompt (e.g. a Wi-Fi password that is too short)
    readonly property bool argSecret: !!(argItem && argItem.secret)   // masked prompt (Wi-Fi password): never kept in history

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
    JellyfinSource { id: jfSrc; onUpdated: lc.refreshKeep() }
    NetSource { id: netSrc; active: lc.shown; section: lc.section; onUpdated: lc.refreshKeep(); onFinished: lc.close() }   // Network / Bluetooth sections (closes after a connect)
    WebappSource {                                  // Install webapp section: opens its own text prompts, closes after installing
        id: waSrc
        onUpdated: lc.refreshKeep()
        onFinished: lc.close()
        // a new prompt replaces an open webapp prompt (address -> name), but never a non-empty filter the user is typing in
        onPrompt: item => {
            if (!lc.shown || lc.section !== "webapp" || lc.actionsOpen) return
            if (lc.argItem ? !waSrc.owns(lc.argItem) : lc.query !== "") return
            lc.argItem = null
            lc.runItem(item)
        }
        // lookup done: the open name prompt gets the new row; the suggestion goes into the field only while it is empty,
        // so a name typed meanwhile stays exactly as typed
        onSuggest: (item, text) => {
            if (!lc.shown || lc.section !== "webapp" || lc.actionsOpen) return
            if (lc.argItem && lc.argItem.kind === item.kind) {
                lc.argItem = item
                if (lc.focusItem.text === "" && text !== "") { lc.focusItem.text = text; lc.focusItem.cursorPosition = text.length }
            } else if (!lc.argItem && lc.query === "") lc.runItem(item)
        }
    }
    VpnSource { id: vpnSrc; sw: VpnSwitch; active: lc.shown; section: lc.section; onUpdated: lc.refreshKeep() }   // Tailscale / Mullvad sections
    SectionsSource { id: secSrc; jf: jfSrc; vpn: vpnSrc; net: netSrc; web: waSrc; onUpdated: lc.refreshKeep() }
    readonly property var sourceList: [appsSrc, winSrc, cmdSrc, secSrc, jfSrc, netSrc, vpnSrc, waSrc, scriptSrc, calcSrc, emojiSrc, fileSrc, clipSrc, webSrc]

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
        const q = argItem ? argQuery : query.trim()     // under a text prompt the field holds the argument, not a filter
        if (section !== "") {                           // inside a section: only its rows, filtered with the ranker (no usage)
            let rows = section === "jellyfin" ? jfSrc.listFor(q) : secSrc.rows(section)   // jellyfin: nested level / server search, no usage ranking
            if (q !== "" && section !== "jellyfin") rows = secSrc.extra(section, q).concat(Ranker.rank(rows, q, {}, Date.now(), { limit: 50 }).map(r => r.item))
            const prevId = keep && results[sel] ? results[sel].id : ""
            const hadStop = results.some(r => r.kind === "rec-stop")
            // a status block (Loading / error / Try again rows) that gets replaced hands the selection to the row now at its first position,
            // e.g. Try again -> Loading... -> the first loaded row, instead of whatever row slid under the old index
            const isStatus = r => r && (r.kind === "info" || r.kind === "jf-retry")
            let statusAt = sel
            while (isStatus(results[sel]) && statusAt > 0 && isStatus(results[statusAt - 1])) statusAt--
            const fromStatus = isStatus(results[sel])
            results = rows.map(it => it.id === confirmId
                ? Object.assign({}, it, { name: it.confirmText || ("Confirm: " + it.name), subtitle: it.confirmSub || "Press Enter again to confirm", glyph: "\uf071", iconColor: "red" })
                : it)
            let i = 0
            if (keep) {                                 // same row stays selected (rows can shift: Stop recording appears once the status is known)
                i = results.findIndex(r => r.id === prevId)
                if (i < 0) i = Math.min(fromStatus ? statusAt : sel, results.length - 1)
                if (!hadStop && q === "" && results.some(r => r.kind === "rec-stop")) i = 0
            } else if (q === "") i = secSrc.startSel(section)   // sections reopen on the last used capture mode
            sel = Math.max(0, i)
            first = keep ? Math.min(first, sel) : 0
            if (sel >= first + numResults) first = sel - numResults + 1
            if (section === "jellyfin") jfSrc.nearEnd(sel, results.length)   // a page that just loaded may leave the selection near the end
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
    function refreshKeep() { if (shown) refresh(true) }   // also under a prompt: rows behind it stay current (lookup / connect progress)

    function clearConfirm() { if (confirmId !== "") { confirmId = ""; if (shown) refresh(true) } }
    onQueryChanged: { confirmId = ""; jfSrc.track(query, section); if (shown && !argItem) refresh() }
    onSelChanged: { clearConfirm(); if (section === "jellyfin") jfSrc.nearEnd(sel, results.length) }   // Jellyfin: next page of a long library
    onOpening: {
        actionsOpen = false; histPos = -1; argItem = null; confirmId = ""
        jfSrc.reset()
        section = presetSection
        sectionDirect = section !== ""
        if (section !== "") secSrc.enter(section)
        presetSection = ""
        query = preset; input.text = preset; preset = ""
        refresh()
        replayWallpaper()
    }

    // opening on an EMPTY workspace advances that monitor's play-once video wallpaper by one burst (like a workspace switch,
    // hypr/scripts/video-replay.lua); theme/mpv/replay.py (= `theme.py video replay`, ~5 ms instead of ~50) debounces itself
    // and does nothing for loop / image wallpapers
    property string replayConn: ""
    function replayWallpaper() {
        const m = Hyprland.focusedMonitor, ws = m ? m.activeWorkspace : null
        if (!ws || ws.toplevels.values.length > 0 || replay.running) return
        const c = m.name
        if (typeof c !== "string" || !/^[A-Za-z0-9_.-]+$/.test(c) || c.length > 40) return
        replayConn = c
        replay.running = true
    }
    Process {
        id: replay
        command: ["python3", "-I", "-S", Quickshell.env("HOME") + "/.config/theme/mpv/replay.py", lc.replayConn]
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
        if (section === "jellyfin" && jfSrc.depth > 0) { backJellyfin(); return }
        if (section === "mullvad" && vpnSrc.country !== "") {   // nested city level -> the country list, country stays selected
            const id = "vpn:mv:cc:" + vpnSrc.country
            vpnSrc.leaveCountry()
            confirmId = ""; histPos = -1
            input.text = ""
            refresh()
            const i = results.findIndex(r => r.id === id)
            if (i > 0) { sel = i; first = Math.max(0, i - numResults + 1) }
            return
        }
        if (section === "twitch" && secSrc.vodActive) {  // nested "Past broadcasts" level -> the channel list, channel stays selected
            const id = "sec:twitch:" + secSrc.vodLogin
            secSrc.leaveVods()
            confirmId = ""; histPos = -1
            input.text = ""
            refresh()
            const i = results.findIndex(r => r.id === id)
            if (i > 0) { sel = i; first = Math.max(0, i - numResults + 1) }
            return
        }
        section = ""; sectionDirect = false; confirmId = ""; histPos = -1
        input.text = ""
        refresh()
    }
    // Jellyfin nested level -> its parent (filter text and selected row restored); leaving the last level of a "jf " prefix search returns to it
    function backJellyfin() {
        const r = jfSrc.pop()
        confirmId = ""; histPos = -1
        if (jfSrc.depth === 0 && jfSrc.fromPrefix) { section = ""; sectionDirect = false }
        input.text = r.text
        input.cursorPosition = input.text.length
        refresh()
        const i = results.findIndex(x => x.id === r.selId)
        if (i > 0) { sel = i; first = Math.max(0, i - numResults + 1) }
    }
    // after an action pushed a nested level (Twitch past broadcasts, Jellyfin browse): fresh list, empty filter
    function afterEnter() {
        if (section === "" && jfSrc.depth > 0) { section = "jellyfin"; sectionDirect = false }   // browsing from the "jf " prefix mode
        actionsOpen = false; confirmId = ""; histPos = -1
        input.text = ""
        refresh()
    }
    // Key handlers shared by the search field's Keys.onPressed.
    // Esc / Ctrl+C: a section entered from the main list goes one level back, a section opened directly (keybind / IPC) closes
    function keyEscape() {
        if (section !== "" && !sectionDirect) back(); else close()
    }
    // Left = one level back: action panel -> list, nested level -> its parent list, section -> main list. Outside the panel only when
    // it would not move the text caret (empty filter, or caret at 0 without selection)
    function keyLeft() {
        if (argItem) return false
        if (actionsOpen) { actionsOpen = false; return true }
        if (section === "") return false
        if (input.text !== "" && (input.cursorPosition !== 0 || input.selectionStart !== input.selectionEnd)) return false
        back()
        return true
    }
    // Right = into the selected item's options, only when it would not move the text caret (empty filter, or caret at the end without
    // selection): a Twitch channel goes straight to its past broadcasts, any other item with actions opens the action panel (Ctrl+K)
    function keyRight() {
        if (actionsOpen || argItem || !current) return false
        const jfBrowse = jfSrc.rightHintFor(current)
        const cities = current.kind === "vpn-country"     // Mullvad country -> its cities
        if (!jfBrowse && !cities && actions.length < 2) return false
        if (input.text !== "" && (input.cursorPosition !== input.text.length || input.selectionStart !== input.selectionEnd)) return false
        if (cities) runItem(current)
        else if (current.actions && current.actions.some(a => a.id === "twitch-vods")) doAction("twitch-vods")
        else if (jfBrowse) doAction("jf-browse")
        else openActions()
        return true
    }
    // Backspace on an empty filter inside a section goes back like Left
    function keyBackspace() {
        if (section === "" || actionsOpen || argItem || input.text !== "") return false
        back()
        return true
    }
    // footer hint for Right ("" = the selected row has no options)
    readonly property string rightHint: actionsOpen || argItem || !current || (actions.length < 2 && !jfSrc.rightHintFor(current) && current.kind !== "vpn-country") ? ""
        : current.kind === "vpn-country" ? "→ cities" : current.actions && current.actions.some(a => a.id === "twitch-vods") ? "→ broadcasts" : jfSrc.rightHintFor(current) ? "→ browse" : "→ options"

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
        if (item.descend !== undefined) {                // file browser: a folder row descends (query = its path + "/"), nothing recorded
            input.text = item.descend; input.cursorPosition = input.text.length
            return
        }
        if (item.kind === "section") {                   // root row: push the section (the entry itself is recorded)
            usage = Frecency.record(usage, item.id, query.trim().toLowerCase(), Date.now())
            saveUsage.restart()
            enterSection(item.section)
            return
        }
        if (item.kind === "jf-nav" || item.kind === "jf-retry") {   // Jellyfin: open a nested level / reload (not recorded, launcher stays open)
            const r = jfSrc.action(item.kind === "jf-nav" ? "jf-browse" : "jf-retry", item)
            if (r === "enter") afterEnter(); else refresh(true)
            return
        }
        if (item.kind === "vpn-country") {               // Mullvad: descend to the cities of a country (not recorded, launcher stays open)
            vpnSrc.enterCountry(item.cc)
            afterEnter()
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
            argQuery = query.trim(); argNote = ""; argItem = item
            input.text = item.argInit || ""             // e.g. the suggested web app name, editable
            input.cursorPosition = input.text.length
            return
        }
        const inPlace = [netSrc, vpnSrc, waSrc].find(s => s.owns(item))
        if (inPlace) {                                  // Network / Bluetooth / Install webapp rows act in place: progress and errors show on the row
            const r = inPlace.activate(item, arg)
            if (typeof r === "string") { argNote = r; return }   // the prompt stays, with this note in the footer
            const prompt = argItem !== null
            argItem = null; argNote = ""; confirmId = ""
            if (prompt) { input.text = argQuery; input.cursorPosition = input.text.length }   // also wipes the password from the field
            refresh(true)
            const i = results.findIndex(r => r.id === item.id)   // the text change above re-ran refresh(): stay on the row that is connecting
            if (i >= 0) { sel = i; if (sel < first) first = sel; else if (sel >= first + numResults) first = sel - numResults + 1 }
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
        const a = [{ id: "run", label: it.runLabel || "Run", glyph: "" }]
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
        const def = actions.find(a => a.id === id)
        if (def && def.confirm && actionConfirm !== id) { actionConfirm = id; return }
        actionConfirm = ""
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
                    if (r === "enter") { afterEnter(); return }   // pushed a nested level (Twitch past broadcasts, Jellyfin browse)
                    if (r) { shown = false; return }
                }
        }
        actionsOpen = false
        refresh()
    }

    function openActions() {
        if (!current) return
        asel = 0; actionConfirm = ""
        actionsOpen = true
    }
    // action-panel entries with `confirm: true` (Uninstall webapp) need a second Enter; moving or closing the panel disarms
    property string actionConfirm: ""
    onAselChanged: actionConfirm = ""
    onActionsOpenChanged: actionConfirm = ""

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
                if (c && typeof c.screen === "string") lc.screenMatch = c.screen
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
            Icon { text: lc.argSecret ? "\uf084" : ""; font.pixelSize: 14; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 22 }   // magnifying-glass (key while a Wi-Fi password is typed)
            TextInput {
                id: input
                Layout.fillWidth: true
                clip: true
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                selectedTextColor: Theme.fg
                font.family: Theme.font
                font.pixelSize: 14
                // Wi-Fi password prompt: masked, no input-method prediction / learning
                echoMode: lc.argSecret ? TextInput.Password : TextInput.Normal
                passwordCharacter: "\u2022"
                inputMethodHints: lc.argSecret ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase : Qt.ImhNone
                onTextChanged: { lc.query = text; if (lc.argNote !== "") lc.argNote = "" }
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
                        if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_C)) { lc.argItem = null; lc.argNote = ""; text = lc.argQuery }
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) lc.runItem(lc.argItem, text)
                        else ev.accepted = false
                        return
                    }
                    if (lc.actionsOpen) {
                        const n = lc.actions.length
                        if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_K)) lc.actionsOpen = false
                        else if (k === Qt.Key_Left) lc.keyLeft()
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) lc.doAction(lc.actions[lc.asel].id)
                        else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) lc.asel = Math.min(n - 1, lc.asel + 1)
                        else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_P)) lc.asel = Math.max(0, lc.asel - 1)
                        else ev.accepted = false
                        return
                    }
                    if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_C)) lc.keyEscape()
                    else if (k === Qt.Key_Left && !ctrl && !(ev.modifiers & Qt.ShiftModifier) && lc.keyLeft()) {}
                    else if (k === Qt.Key_Right && !ctrl && !(ev.modifiers & Qt.ShiftModifier) && lc.keyRight()) {}
                    else if (k === Qt.Key_Backspace && !ctrl && lc.keyBackspace()) {}
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
            Label { visible: !lc.argSecret; text: lc.results.length; color: Theme.muted; font.pixelSize: Theme.fontCaption }
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
                    readonly property string avatar: modelData.avatar || ""      // local image (twitch profile picture), drawn in the icon slot
                    icon: iconPath === "" && avatar === "" ? (modelData.glyph || "") : ""
                    iconSize: 16
                    iconColor: modelData.iconColor === "red" ? Theme.red : modelData.iconColor === "green" ? Theme.green : sel ? Theme.accent : modelData.iconColor === "muted" ? Theme.muted : Theme.fgDim
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
                    Item {
                        visible: row.avatar !== ""
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            source: row.avatar !== "" ? "file://" + row.avatar : ""
                            sourceSize: Qt.size(44, 44)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: avatarImg
                            visible: avatarImg.status === Image.Ready
                            saturation: row.modelData.avatarLive ? 0 : -1
                            opacity: row.modelData.avatarLive ? 1 : 0.6
                            maskEnabled: true
                            maskSource: avatarMask
                        }
                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: Math.min(width / 2, Theme.radiusItem)
                            layer.enabled: true
                            visible: false
                        }
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
                    readonly property bool arming: lc.actionConfirm === modelData.id
                    width: parent.width
                    rowH: 40
                    radius: Theme.radiusModal
                    icon: arming ? "\uf071" : modelData.glyph
                    iconSize: 14
                    iconColor: sel ? Theme.accent : Theme.fgDim
                    outlined: sel
                    border.color: Theme.alpha(Theme.accent, 0.8)
                    color: sel ? Theme.alpha(Theme.accent, 0.26) : hovered ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                    onClicked: lc.doAction(modelData.id)
                    RowText {
                        title: arow.arming ? (arow.modelData.confirmText || "Confirm: " + arow.modelData.label) : arow.modelData.label
                        sub: arow.arming ? "Press Enter again to confirm" : (arow.modelData.sub || "")
                    }
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
        text: lc.argItem ? (lc.argNote !== "" ? lc.argNote + " · " : "") + "Enter " + (lc.argItem.argVerb || "run") + " · Esc cancel"
            : lc.actionsOpen ? "↑↓ select · Enter do · ← / Esc back"
            : lc.section !== "" ? "↑↓ select · Enter run · " + (lc.rightHint ? lc.rightHint + " · " : "") + "← / Backspace back · Esc " + (lc.sectionDirect ? "close" : "back")
            : "↑↓ select · Enter run · " + (lc.rightHint ? lc.rightHint + " · " : "") + "Ctrl+1-9 quick run · Esc close"
        color: lc.argNote !== "" ? Theme.red : Theme.muted
        font.pixelSize: Theme.fontCaption
    }

}
