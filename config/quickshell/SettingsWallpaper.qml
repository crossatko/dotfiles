import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings -> Wallpaper & theme: every image in wallpaper_dirs (~/.config/theme/theme.toml) as a thumbnail
// grid. Click one (or arrows + Enter) -> `theme.py apply <image>`, which re-extracts the palette and restyles
// every app, this shell included (Theme.qml watches out/palette.json). Replaces the old standalone picker
// overlay; `qs ipc call picker toggle` (SUPER+T) opens Settings on this page. The current palette sits in the
// Settings title row (`headerItem`), so it stays visible while the grid scrolls.
ColumnLayout {
    id: page
    spacing: 12

    readonly property bool wantsFocus: true    // Settings.qml gives this page the keyboard focus
    property Flickable flick: null             // set by Settings.qml; keeps the keyboard selection in view

    readonly property var dirs: Theme.wallpaperDirs
    property var files: []
    property bool scanned: false
    property int sel: -1                       // keyboard selection (index into files), -1 = none yet
    property string applying: ""               // path handed to theme.py, cleared once Theme.wallpaper follows
    readonly property string currentPath: Theme.wallpaper.replace(/^~/, Theme.home)
    onCurrentPathChanged: if (currentPath === applying) applying = ""

    readonly property int gap: 12
    readonly property int cols: Math.max(2, Math.floor((width + gap) / 300))
    readonly property real cellW: Math.floor((width - (cols - 1) * gap) / cols)
    readonly property real cellH: Math.round(cellW * 9 / 16)

    // detached: closing Settings mid-apply must not kill theme.py
    function apply(path) {
        if (!path || applying !== "") return
        applying = path
        applyTimeout.restart()
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "apply", path])
    }
    Timer { id: applyTimeout; interval: 30000; onTriggered: page.applying = "" }   // apply failed / same image

    function reveal(i) {
        if (!flick || i < 0) return
        const top = grid.y + Math.floor(i / cols) * (cellH + gap)
        const bottom = top + cellH
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (top < flick.contentY) flick.contentY = Math.max(0, top - 8)
        else if (bottom > flick.contentY + flick.height) flick.contentY = Math.min(maxY, bottom - flick.height + 8)
    }

    Keys.onPressed: e => {
        const n = files.length
        if (n === 0) { e.accepted = false; return }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
            if (sel >= 0) apply(files[sel])
            e.accepted = true
            return
        }
        let i = sel >= 0 ? sel : Math.max(0, files.indexOf(currentPath))
        if (sel < 0 && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(e.key)) {
            // first arrow press just shows the cursor on the current wallpaper
        } else if (e.key === Qt.Key_Left) i -= 1
        else if (e.key === Qt.Key_Right) i += 1
        else if (e.key === Qt.Key_Up) i -= cols
        else if (e.key === Qt.Key_Down) i += cols
        else if (e.key === Qt.Key_Home) i = 0
        else if (e.key === Qt.Key_End) i = n - 1
        else { e.accepted = false; return }   // Escape etc. go up to Settings
        sel = Math.max(0, Math.min(n - 1, i))
        reveal(sel)
        e.accepted = true
    }

    Process {
        id: scan
        command: ["sh", "-c", "find -L " + page.dirs.map(d => "'" + d + "'").join(" ")
            + " -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: { page.files = text.split("\n").filter(l => l.length > 0); page.scanned = true }
        }
    }
    Component.onCompleted: scan.running = true   // rescanned every time Settings opens on this page

    // ---- current palette: lives in the Settings title row (headerItem), so it stays visible while the grid scrolls ----
    // one line, centered on the row: [wallpaper file name, or "name  #hex" of the hovered swatch] [swatches]
    readonly property Component headerItem: paletteHeader
    Component {
        id: paletteHeader
        Item {
            id: pal
            property string hovered: ""        // "name  #rrggbb" of the swatch under the mouse
            readonly property var swatches: [
                { n: "bg", c: Theme.bg }, { n: "surface2", c: Theme.surface2 }, { n: "muted", c: Theme.muted },
                { n: "fg", c: Theme.fg }, { n: "accent", c: Theme.accent }, { n: "red", c: Theme.red },
                { n: "green", c: Theme.green }, { n: "yellow", c: Theme.yellow }, { n: "blue", c: Theme.blue },
                { n: "magenta", c: Theme.magenta }, { n: "cyan", c: Theme.cyan }
            ]
            readonly property int gap: 3
            readonly property int captionMin: 110    // room kept for the caption before swatches shrink
            readonly property int sw: Math.max(14, Math.min(28, Math.floor((width - captionMin - 12 - (swatches.length - 1) * gap) / swatches.length)))
            implicitHeight: 30

            Label {
                id: caption
                anchors { left: parent.left; right: swatchRow.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                font.pixelSize: 11
                color: pal.hovered !== "" ? Theme.fg : Theme.muted
                text: pal.hovered !== "" ? pal.hovered : page.currentPath.split("/").pop()
            }
            Row {
                id: swatchRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: pal.gap
                Repeater {
                    model: pal.swatches
                    Rectangle {
                        id: swatch
                        required property var modelData
                        width: pal.sw; height: 20; radius: 0
                        color: modelData.c
                        border.width: 1; border.color: Theme.alpha(Theme.fg, swatchArea.containsMouse ? 0.8 : 0.25)
                        MouseArea {
                            id: swatchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: pal.hovered = containsMouse ? swatch.modelData.n + "  " + String(swatch.modelData.c)
                                : pal.hovered.startsWith(swatch.modelData.n + "  ") ? "" : pal.hovered
                        }
                    }
                }
            }
        }
    }

    // ---- wallpapers ----
    SectionHead {
        title: "Wallpapers"
        detail: !page.scanned ? "scanning…" : page.files.length + " images · " + page.dirs.join(", ")
    }
    Label {
        visible: page.scanned && page.files.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.fgDim
        text: "No images found. Folders come from wallpaper_dirs in ~/.config/theme/theme.toml."
    }

    Grid {
        id: grid
        Layout.fillWidth: true
        columns: page.cols
        spacing: page.gap

        Repeater {
            model: page.files
            Rectangle {
                id: cell
                required property string modelData
                required property int index
                readonly property bool current: modelData === page.currentPath
                readonly property bool cursor: index === page.sel
                readonly property bool busy: modelData === page.applying
                width: page.cellW
                height: page.cellH
                radius: Theme.radius
                color: Theme.surface
                border.width: current || cursor || ma.containsMouse ? 3 : 1
                border.color: current ? Theme.accent : (cursor || ma.containsMouse) ? Theme.fg : Theme.alpha(Theme.overlay, 0.6)
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    source: "file://" + cell.modelData
                    sourceSize: Qt.size(640, 360)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 3 }
                    height: 24
                    color: Theme.alpha(Theme.bg, 0.75)
                    Label {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                        text: cell.busy ? "Applying…" : cell.current ? "✓ " + cell.modelData.split("/").pop() : cell.modelData.split("/").pop()
                        color: cell.current || cell.busy ? Theme.accent : Theme.fg
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.sel = cell.index; page.apply(cell.modelData) }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.topMargin: 4
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.pixelSize: 11
        text: "Click a wallpaper (or arrows + Enter) to apply it: theme.py re-extracts the palette and restyles every app. Folders: wallpaper_dirs in ~/.config/theme/theme.toml."
    }
}
