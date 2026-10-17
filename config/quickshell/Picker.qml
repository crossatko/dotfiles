import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Fullscreen wallpaper picker. Click a thumbnail -> theme.py apply <image>,
// which re-extracts the palette and restyles every app (this shell included).
PanelWindow {
    id: picker

    property bool shown: false
    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    color: Theme.alpha(Theme.bg, Theme.pickerOpacity)
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-picker"

    // Folders come from wallpaper_dirs in ~/.config/theme/theme.toml
    readonly property var dirs: Theme.wallpaperDirs
    property var files: []

    // open on whichever monitor has focus right now
    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0]
    }
    function toggle() {
        if (!shown) screen = focusedScreen()
        shown = !shown
    }

    onShownChanged: {
        if (shown) { files = []; scan.running = true; grid.forceActiveFocus() }
        shown ? Popups.opened("picker", screen ? screen.name : "") : Popups.closed("picker")
    }
    // one click-away thing at a time; a click on another monitor (ClickCatcher) closes it too
    Connections {
        target: Popups
        function onDismiss(except) { if (except !== "picker" && picker.shown) picker.shown = false }
    }

    Process {
        id: scan
        command: ["sh", "-c", "find -L " + picker.dirs.map(d => "'" + d + "'").join(" ")
            + " -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: picker.files = text.split("\n").filter(l => l.length > 0)
        }
    }
    Process { id: apply }

    MouseArea { anchors.fill: parent; onClicked: picker.shown = false }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 160, 1500)
        height: parent.height - 160
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Label { text: "Wallpaper"; font.pixelSize: 24; color: Theme.fg }
            Item { Layout.fillWidth: true }
            // live swatches of the current palette
            Repeater {
                model: [Theme.bg, Theme.surface2, Theme.muted, Theme.fg, Theme.accent, Theme.red, Theme.green, Theme.yellow, Theme.blue, Theme.magenta, Theme.cyan]
                Rectangle {
                    required property var modelData
                    width: 22; height: 22; radius: 0
                    color: modelData
                    border.width: 1; border.color: Theme.alpha(Theme.fg, 0.25)
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 320
            cellHeight: 190
            model: picker.files
            focus: true
            Keys.onEscapePressed: picker.shown = false

            delegate: Item {
                id: cell
                required property string modelData
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property bool current: modelData === Theme.wallpaper.replace(/^~/, Theme.home)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: cell.current || ma.containsMouse ? 3 : 1
                    border.color: cell.current ? Theme.accent : ma.containsMouse ? Theme.fg : Theme.alpha(Theme.overlay, 0.6)
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + cell.modelData
                        sourceSize: Qt.size(480, 270)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 22
                        color: Theme.alpha(Theme.bg, 0.75)
                        Label {
                            anchors { fill: parent; leftMargin: 8 }
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            text: cell.modelData.split("/").pop()
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            apply.command = ["python3", "-I", Theme.themeDir + "/theme.py", "apply", cell.modelData]
                            apply.running = true
                            picker.shown = false
                        }
                    }
                }
            }
        }
    }
}
