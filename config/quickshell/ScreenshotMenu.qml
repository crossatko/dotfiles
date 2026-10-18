import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Screenshot mode picker (CTRL+Print; see hyprland/binds.lua and hypr/scripts/screenshot-key.sh).
// Fullscreen dim overlay on the focused monitor with a small card: Region / Window / Screen tiles.
// Keys: 1/2/3 take a shot, arrows / Tab move, Enter/Space activates, Escape or a click outside closes.
//   qs ipc call screenshot menu | close
// Choosing a mode hides the window first and starts screenshot.sh only after `launchDelay`, so the popup is
// unmapped before slurp grabs the pointer and is never in the picture. QS_SHOT_SCRIPT overrides the script
// (isolated tests only).
PanelWindow {
    id: win

    readonly property string script: Quickshell.env("QS_SHOT_SCRIPT")
        || (Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh")
    readonly property int launchDelay: 200

    readonly property var modes: [
        { id: "region", title: "Region", sub: "Drag a rectangle", icon: "\uf5cb" },   // vector-square
        { id: "window", title: "Window", sub: "Click a window",   icon: "\uf2d0" },   // window-maximize
        { id: "output", title: "Screen", sub: "Whole monitor",    icon: "\uf390" }    // display
    ]

    property bool shown: false
    property int cur: 0               // highlighted mode tile
    property int lastMode: 0          // the menu reopens on the last used mode
    property string pendingMode: ""
    // concentric radii: card = R; tiles / segment rows / audio row sit 20 px inside it; key badges sit 8 px inside a tile
    readonly property int badgeRadius: Theme.inner(Theme.radiusModal, 8)

    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    color: Theme.alpha(Theme.bg, 0.5)
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-screenshot"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0]
    }
    function open() {
        if (shown) return
        screen = focusedScreen()
        cur = lastMode
        shown = true
        keys.forceActiveFocus()
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open() }

    // close first, start the recorder once the window is gone
    function choose(i) {
        if (!shown || i < 0 || i >= modes.length) return
        lastMode = i
        pendingMode = modes[i].id
        shown = false
        launch.restart()
    }

    function activate() { choose(cur) }

    // keyboard (also what an isolated test drives); returns false for keys it doesn't use
    function handleKey(k) {
        if (k === Qt.Key_Escape) close()
        else if (k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3) choose(k - Qt.Key_1)
        else if (k === Qt.Key_Left) cur = Math.max(0, cur - 1)
        else if (k === Qt.Key_Right) cur = Math.min(2, cur + 1)
        else if (k === Qt.Key_Tab) cur = (cur + 1) % 3
        else if (k === Qt.Key_Backtab) cur = (cur + 2) % 3
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activate()
        else return false
        return true
    }

    Timer {
        id: launch
        interval: win.launchDelay
        onTriggered: {
            if (win.pendingMode === "") return
            Quickshell.execDetached([win.script, win.pendingMode])
            win.pendingMode = ""
        }
    }

    onShownChanged: shown ? Popups.opened("screenshot", screen ? screen.name : "") : Popups.closed("screenshot")
    Connections {
        target: Popups
        function onDismiss(except) { if (except !== "screenshot" && win.shown) win.close() }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => { if (win.handleKey(ev.key)) ev.accepted = true }
    }
    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: body.implicitHeight + 40
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, 0.98)     // small card over arbitrary content: nearly opaque
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        MouseArea { anchors.fill: parent }   // clicks on the card don't reach the close-scrim

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label { text: "\uf030"; font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 16; color: Theme.accent }   // camera
                Label { text: "Screenshot"; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                Btn { icon: true; text: "\uf00d"; inset: 20; onClicked: win.close() }   // 20 px inside the card
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: win.modes
                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool sel: win.cur === index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1                 // equal thirds
                        implicitHeight: 128
                        radius: Theme.radiusModal
                        color: sel ? Theme.alpha(Theme.accent, tileArea.pressed ? 0.36 : 0.26) : Theme.alpha(Theme.fg, 0.07)
                        border.width: 1
                        border.color: sel ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.45)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        // key hint, top-left
                        Rectangle {
                            x: 8; y: 8
                            width: 20; height: 20
                            radius: win.badgeRadius
                            color: tile.sel ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.08)
                            Label { anchors.centerIn: parent; text: tile.index + 1; font.pixelSize: 11; color: tile.sel ? Theme.accent : Theme.muted }
                        }

                        ColumnLayout {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                            anchors.verticalCenterOffset: 6
                            spacing: 4
                            Label {
                                text: tile.modelData.icon
                                font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 32
                                color: tile.sel ? Theme.accent : Theme.fgDim
                                Layout.alignment: Qt.AlignHCenter
                                Layout.bottomMargin: 6
                            }
                            Label { text: tile.modelData.title; font.pixelSize: 14; color: tile.sel ? Theme.fg : Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
                            Label {
                                text: tile.modelData.sub; font.pixelSize: 11; color: Theme.muted
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: win.cur = tile.index
                            onClicked: win.choose(tile.index)
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "1 2 3 capture · ←→ Enter · Esc close"
                color: Theme.muted
                font.pixelSize: 11
            }
        }
    }
}
