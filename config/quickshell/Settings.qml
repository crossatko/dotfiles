import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Settings window: a centered card on a fullscreen overlay (click outside / Escape closes), a sidebar of
// pages on the left and the selected page (scrollable) on the right. Opened from the control center's gear,
// or `qs ipc call settings toggle|open|close` / `qs ipc call settings page <id>`; `qs ipc call picker toggle`
// (SUPER+T) = togglePage("wallpaper").
// Adding a page: one entry in `pages` (id, title, Font Awesome icon, QML file whose root fills the width).
// A page root may declare `readonly property bool wantsFocus: true` (gets the keyboard focus; unhandled keys
// such as Escape bubble up to the card), `property Flickable flick` (set to the page's scroller) and
// `property Component headerItem` (shown in the title row, between the title and the close button; it
// fills that width, is vertically centered on the row's fixed height and doesn't scroll).
PanelWindow {
    id: win

    readonly property var pages: [
        { id: "bar",      title: "Bar",      icon: "\uf0db", source: "SettingsBar.qml" },
        { id: "wallpaper", title: "Wallpaper & theme", icon: "\uf03e", source: "SettingsWallpaper.qml" },
        { id: "appearance", title: "Appearance", icon: "\uf53f", source: "SettingsAppearance.qml" }
    ]
    property string page: "bar"
    readonly property var current: pages.find(p => p.id === page) || pages[0]

    property bool shown: false
    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    color: Theme.alpha(Theme.bg, 0.5)
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-settings"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0]
    }
    // opens on the monitor of the popup it was asked from (control center gear), else the focused one
    function open(p) {
        if (p === "monitors") p = "bar"           // old page id: bar on/off + edge now live on the Bar page
        if (p && pages.some(x => x.id === p)) page = p
        if (shown) return
        const from = Popups.name !== "" ? Quickshell.screens.find(s => s.name === Popups.screen) : null
        screen = from || focusedScreen()
        shown = true
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open("") }
    // close if already showing that page, else open on it (or switch to it)
    function togglePage(p) { (shown && current.id === p) ? close() : open(p) }
    function focusPage() {
        const it = pageLoader.item
        if (it && it.wantsFocus === true) it.forceActiveFocus()
        else keys.forceActiveFocus()
    }

    onShownChanged: {
        if (shown) { focusPage(); Popups.opened("settings", screen ? screen.name : "") }
        else Popups.closed("settings")
    }
    Connections {
        target: Popups
        function onDismiss(except) { if (except !== "settings" && win.shown) win.shown = false }
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
    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Math.max(920, parent.width * 0.6))   // 920: content area no narrower than before the wider sidebar
        height: Math.min(parent.height - 80, Math.max(600, parent.height * 0.62))
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, 0.96)     // a big card of small text: near-opaque, unlike the small popups
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        Keys.onEscapePressed: win.close()    // keys a focused page leaves unhandled bubble up to here

        MouseArea { anchors.fill: parent }   // clicks on the card don't reach the close-scrim

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

                ColumnLayout {
                    id: side
                    anchors { fill: parent; margins: 12 }
                    spacing: 4
                    Label { text: "Settings"; font.pixelSize: 17; font.bold: true; Layout.bottomMargin: 10; Layout.leftMargin: 6 }
                    Repeater {
                        model: win.pages
                        Rectangle {
                            id: nav
                            required property var modelData
                            readonly property bool sel: win.current.id === modelData.id
                            Layout.fillWidth: true
                            implicitWidth: navRow.implicitWidth + 12 + 18    // left padding + right padding with some air
                            implicitHeight: 36
                            radius: Theme.radiusItem
                            color: sel ? Theme.alpha(Theme.accent, 0.26) : navArea.containsMouse ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                            border.width: sel ? 1 : 0
                            border.color: Theme.alpha(Theme.accent, 0.8)
                            RowLayout {
                                id: navRow
                                anchors { fill: parent; leftMargin: 12; rightMargin: 18 }
                                spacing: 10
                                Icon { text: nav.modelData.icon; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 18; color: nav.sel ? Theme.accent : Theme.fgDim }
                                Label { text: nav.modelData.title; Layout.fillWidth: true; color: nav.sel ? Theme.fg : Theme.fgDim }
                            }
                            MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = nav.modelData.id }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Label { text: "Esc to close"; color: Theme.muted; font.pixelSize: 11; Layout.leftMargin: 6 }
                }
            }

            // ---- page ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18
                spacing: 14

                // one line, fixed height (= close button), everything centered on it: title | headerItem | close
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: closeBtn.implicitHeight
                    Layout.fillHeight: false
                    spacing: 16
                    Label { id: titleLabel; text: win.current.title; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter }
                    // the page's optional `headerItem` (stays put while the page scrolls); empty = spacer
                    Loader {
                        id: headerLoader
                        Layout.fillWidth: true
                        Layout.preferredHeight: closeBtn.implicitHeight    // not fillHeight: that would stretch the row
                        Layout.alignment: Qt.AlignVCenter
                        sourceComponent: pageLoader.item && pageLoader.item.headerItem ? pageLoader.item.headerItem : null
                    }
                    Btn { id: closeBtn; icon: true; text: "\uf00d"; inset: 18; Layout.alignment: Qt.AlignVCenter; onClicked: win.close() }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !(pageLoader.item && pageLoader.item.dragging === true)   // don't scroll while a chip is dragged

                    Loader {
                        id: pageLoader
                        width: flick.width
                        active: win.shown
                        source: win.current.source
                        onLoaded: {
                            if (item.flick !== undefined) item.flick = flick
                            win.focusPage()
                        }
                    }
                }
            }
        }
    }
}
