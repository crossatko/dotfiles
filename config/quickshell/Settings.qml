pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Settings window: a floating toplevel titled "qs-settings" (Hyprland places it: SUPER+LMB drags; it always opens centred at the default size, nothing is
// remembered, a double-click on the title row re-centres a dragged one; see hypr/scripts/modal-windows.lua), Escape / the X close it. A sidebar
// of pages on the left and the selected page (scrollable) on the right. Resizable and tileable (the size it opens at
// is a default; Hyprland remembers the floating size). Opened from the control center's gear,
// or `qs ipc call settings toggle|open|close` / `qs ipc call settings page <id>`; `qs ipc call picker toggle`
// (SUPER+T) = togglePage("wallpaper").
// Adding a page: one entry in `allPages` (id, title, Vadivam icon, QML file whose root fills the width).
// The linter cannot see these optional page hooks on the dynamically loaded page, hence the
// missing-property suppressions where they are read.
// A page root may declare `readonly property bool wantsFocus: true` (gets the keyboard focus; unhandled keys
// such as Escape bubble up to the card), `property Flickable flick` (set to the page's scroller) and
// `property Component headerItem` (shown in the title row, between the title and the close button; it
// fills that width, is vertically centered on the row's fixed height and doesn't scroll) and
// `property var memory` (set to a per-page object that outlives the page: pages are unloaded when Settings closes,
// so this is where a page keeps session state such as a selected tab; not saved to disk).
FloatingWindow {
    id: win

    // glassOnly pages exist only while the running Hyprland draws the solid_glass blur (Theme.glass)
    // Every page: its 1-3 primary choices first (ChoiceRow / PresetCards with previews, presets in Presets.qml, hardly any
    // words: a label, a value badge, an InfoTip for a technical note), then an AdvancedFold ("Customise…") with the
    // detailed rows, and a PageReset at the end.
    readonly property var allPages: [
        { id: "look", title: "Look & feel", icon: Icons.palette, source: "SettingsLook.qml" },
        { id: "monitors", title: "Monitors", icon: Icons.monitor, source: "SettingsMonitors.qml" },
        { id: "wallpaper", title: "Wallpaper", icon: Icons.image, source: "SettingsWallpaper.qml" },
        { id: "bar", title: "Bar", icon: Icons.tableColumns, source: "SettingsBar.qml" },
        { id: "lock", title: "Lock screen", icon: Icons.lock, source: "SettingsLock.qml" },
        { id: "deskclock", title: "Desktop clock", icon: Icons.clock, source: "SettingsDeskClock.qml" },
        { id: "tv", title: "TV", icon: Icons.tv, source: "SettingsTv.qml" }
    ]
    // page ids of earlier versions (scripts, muscle memory) -> where that setting lives now
    readonly property var oldPages: ({ appearance: "look", animations: "look", glass: "look" })
    readonly property var pages: allPages.filter(p => !p.glassOnly || Theme.glass)
    readonly property var glassCtl: GlassTuneCtl       // instantiates the controller (and its `glasstune` IPC target) with the shell
    property string page: "look"
    property var pageMemory: ({})                   // page id -> object handed to a page's `memory` hook (session only)
    readonly property var current: pages.find(p => p.id === page) || pages[0]

    property bool shown: false
    property var scr: Monitors.primary        // the monitor it was opened for: the card is sized from it
    title: "qs-settings"
    visible: shown
    color: "transparent"
    property bool pinSize: false                   // true just after opening: the window re-sizes to the default (Qt keeps the last size, e.g. a tiled one)
    implicitWidth: Math.min(scr.width - 80, Math.max(920, scr.width * 0.6))   // 920: content area no narrower than before the wider sidebar
    implicitHeight: Math.min(scr.height - 80, Math.max(600, scr.height * 0.62))
    // resizable (SUPER+RMB) and tileable (togglefloating): the card fills the window, 760x480 is the smallest
    property size testSize: Qt.size(0, 0)          // test hook `settingsui size w h`: pins the window to that size (0 = off)
    minimumSize: testSize.width > 0 ? testSize : pinSize ? Qt.size(implicitWidth, implicitHeight) : Qt.size(760, 480)
    maximumSize: testSize.width > 0 ? testSize : pinSize ? Qt.size(implicitWidth, implicitHeight) : Qt.size(16384, 16384)
    Timer { id: unpin; interval: 150; onTriggered: win.pinSize = false }
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: win.contentItem; active: visible }

    // sized for the monitor of the popup it was asked from (control center gear), else the focused one; Hyprland
    // opens it on the focused monitor
    function open(p) {
        if (p && oldPages[p]) p = oldPages[p]
        if (p && pages.some(x => x.id === p)) page = p
        if (shown) return
        const from = Popups.name !== "" ? Quickshell.screens.find(s => s.name === Popups.screen) : null
        scr = from || Popups.focusedScreen()
        Monitors.select("")                       // the pages' shared monitor pick starts at the primary
        Popups.closeAll()
        pinSize = true
        unpin.restart()
        shown = true
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open("") }
    // close if already showing that page, else open on it (or switch to it)
    function togglePage(p) { (shown && current.id === p) ? close() : open(p) }
    function focusPage() {
        const it = pageLoader.item
        if (it && it.wantsFocus === true) it.forceActiveFocus()   // qmllint disable missing-property
        else keys.forceActiveFocus()
    }

    onShownChanged: if (shown) focusPage()

    // test hooks (nested sessions drive the window with a virtual pointer): `qs ipc call settingsui locate <objectName>`
    // -> "x,y wxh" of that item of the open page in window coordinates, `scroll <y>` sets the page's scroll position
    function findNamed(root, name) {
        if (!root) return null
        if (root.objectName === name) return root
        const kids = root.contentItem !== undefined && root.contentItem ? [root.contentItem] : []
        for (const c of root.children) kids.push(c)
        for (const c of kids) { const r = findNamed(c, name); if (r) return r }
        return null
    }
    function locate(name) {
        const it = findNamed(card, name)
        if (!it) return ""
        const p = it.mapToItem(null, 0, 0)
        return Math.round(p.x) + "," + Math.round(p.y) + " " + Math.round(it.width) + "x" + Math.round(it.height)
    }
    IpcHandler {
        target: "settingsui"
        function locate(name: string): string { return win.locate(name) }
        // the card rendered by the shell itself at full size (what the window shows minus the compositor's glass), as a PNG
        function grab(path: string): string {
            if (!path.startsWith("/tmp/")) return "refused"
            card.grabToImage(r => { r.saveToFile(path) })
            return "ok"
        }
        function scroll(y: string): void { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, Number(y))) }
        // pin the window to w x h (a tall window shows a whole page in one grab; 0 0 = back to resizable)
        function size(w: string, h: string): void { win.testSize = Qt.size(Number(w), Number(h)) }
        // open / close a named fold (AdvancedFold / FoldSection objectName) without the pointer
        function fold(name: string, open: string): string {
            const it = win.findNamed(card, name)
            if (!it || it.open === undefined) return ""
            it.open = open === "1" || open === "true"
            return "ok"
        }
        // scroll so that the named item sits `at` px below the page top (a nested output smaller than the window
        // reaches only part of it: put the item where the pointer can go)
        function showAt(name: string, at: string): string {
            const it = win.findNamed(card, name)
            if (!it) return ""
            const y = it.mapToItem(flick.contentItem, 0, 0).y
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - Number(at)))
            return "ok"
        }
        // scroll so that the named item is in view (40 px from the top)
        function reveal(name: string): string {
            const it = win.findNamed(card, name)
            if (!it) return ""
            const y = it.mapToItem(flick.contentItem, 0, 0).y
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - 40))
            return "ok"
        }
    }
    Connections {
        target: Popups
        function onSettingsRequest(action, p) {
            if (action === "open") win.open(p)
            else if (action === "close") win.close()
            else win.toggle()
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.close()
    }

    Rectangle {
        id: card
        readonly property bool isGlassItem: true
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.glass ? Theme.cardFill : 0.85)   // glass behind it (Glass.qml); without solid_glass: blurred by the qs-modal window rule
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)
        GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass
        RimLight { anchors.fill: parent; radius: parent.radius; z: 1 }   // the rim near the pointer catches a light

        Keys.onEscapePressed: win.close()    // keys a focused page leaves unhandled bubble up to here

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---- sidebar ----
            // width follows the widest entry (icon + label at Theme.fontSize + padding), so the selected entry's
            // box always holds its whole label; 200 is the floor. Flush with the card's left side: only the left
            // corners follow the card radius, the right ones are clipped square (clip = bounding box)
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: Math.max(200, Math.ceil(side.implicitWidth) + 24)
                clip: true
                Rectangle {
                    anchors { fill: parent; rightMargin: -radius }
                    color: Theme.alpha(Theme.fg, 0.04)
                    radius: Theme.radius
                }
                // the selected page's marker glides between the entries (GlideHighlight)
                GlideHighlight {
                    target: { void navRep.count; return navRep.itemAt(win.pages.findIndex(p => p.id === win.current.id)) }
                    radius: Theme.radiusItem
                    color: Theme.alpha(Theme.accent, 0.26)
                    border.width: 1
                    border.color: Theme.alpha(Theme.accent, 0.8)
                }

                ColumnLayout {
                    id: side
                    anchors { fill: parent; margins: 12 }
                    spacing: 4
                    Label { text: "Settings"; font.pixelSize: Theme.fontLead; font.bold: true; Layout.bottomMargin: Theme.padSm; Layout.leftMargin: Theme.controlGap }
                    Repeater {
                        id: navRep
                        model: win.pages
                        Rectangle {
                            id: nav
                            required property var modelData
                            readonly property bool sel: win.current.id === modelData.id
                            Layout.fillWidth: true
                            implicitWidth: navRow.implicitWidth + 12 + 18    // left padding + right padding with some air
                            implicitHeight: 36
                            radius: Theme.radiusItem
                            color: Theme.alpha(Theme.fg, !sel && navGlow.hovered ? 0.10 : 0)   // selected: the GlideHighlight under it
                            Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                            HoverGlow { id: navGlow; area: navArea; radius: nav.radius }
                            PressFeedback { area: navArea }
                            RowLayout {
                                id: navRow
                                anchors { fill: parent; leftMargin: 12; rightMargin: 18 }
                                spacing: 10
                                Icon { text: nav.modelData.icon; font.pixelSize: Theme.iconMd; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: Theme.iconLg; color: nav.sel ? Theme.accent : Theme.fgDim }
                                Label { text: nav.modelData.title; Layout.fillWidth: true; color: nav.sel ? Theme.fg : Theme.fgDim }
                            }
                            MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = nav.modelData.id }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Label { text: "Esc to close"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.leftMargin: Theme.controlGap }
                }
            }

            // ---- page ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18
                spacing: 14

                // one line, fixed height (= close button), everything centered on it: title | headerItem | close
                Item {   // double-click on the title row: re-centre at the default size
                    Layout.fillWidth: true
                    Layout.preferredHeight: closeBtn.implicitHeight
                    ModalReset { windowTitle: win.title; anchors.fill: parent }
                    RowLayout {
                        anchors.fill: parent
                        spacing: 16
                        Label { id: titleLabel; text: win.current.title; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.alignment: Qt.AlignVCenter }
                        // the page's optional `headerItem` (stays put while the page scrolls); empty = spacer
                        Loader {
                            id: headerLoader
                            Layout.fillWidth: true
                            Layout.preferredHeight: closeBtn.implicitHeight    // not fillHeight: that would stretch the row
                            Layout.alignment: Qt.AlignVCenter
                            sourceComponent: pageLoader.item && pageLoader.item.headerItem ? pageLoader.item.headerItem : null   // qmllint disable missing-property
                        }
                        Btn { id: closeBtn; icon: true; text: Icons.xmark; inset: 18; Layout.alignment: Qt.AlignVCenter; onClicked: win.close() }
                    }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: pageLoader.item ? (pageLoader.item as Item).implicitHeight : 0
                    boundsBehavior: Flickable.StopAtBounds
                    // don't scroll while a chip is dragged
                    interactive: !(pageLoader.item && pageLoader.item.dragging === true)   // qmllint disable missing-property

                    // a new page arrives (fade + rise, Reveal); the old one is gone at once
                    Reveal { id: pageReveal; target: pageLoader; rise: 10 }
                    Loader {
                        id: pageLoader
                        width: flick.width
                        active: win.shown
                        source: win.current.source
                        onLoaded: {
                            // qmllint disable missing-property
                            if (item.flick !== undefined) item.flick = flick
                            if (item.memory !== undefined) {
                                if (!win.pageMemory[win.current.id]) win.pageMemory[win.current.id] = {}
                                item.memory = win.pageMemory[win.current.id]
                            }
                            // qmllint enable missing-property
                            pageReveal.play()
                            win.focusPage()
                        }
                    }
                }
            }
        }
    }
}
