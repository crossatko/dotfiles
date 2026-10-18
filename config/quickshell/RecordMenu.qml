import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Screen recording mode picker (SHIFT+Print when nothing records; see hyprland/binds.lua and
// hypr/scripts/screenrec-key.sh). Fullscreen dim overlay on the focused monitor with a small card:
// Region / Window / Screen tiles, Frame rate 30/60 and Format MP4/WebM segments, a "Record desktop
// audio" switch. Keys: 1/2/3 start a mode, arrows / Tab move, Enter/Space activates (cycles a segment row),
// F toggles the frame rate, M the format, A toggles audio, Escape or a click outside closes.
//   qs ipc call record menu | close
// Frame rate, format and audio are saved to $XDG_STATE_HOME/quickshell/screenrec.conf (key=value lines);
// screenrec.sh reads the same file for options it isn't given (the key's fallback when the shell is down).
// Choosing a mode hides the window first and starts screenrec.sh only after `launchDelay`, so the popup is
// unmapped before slurp grabs the pointer and is never in the video. QS_RECORD_SCRIPT overrides the script
// (isolated tests only).
ModalMenu {
    id: win

    kind: "record"
    title: "Screen recording"
    icon: "\uf03d"                    // video
    iconColor: Theme.red

    readonly property string script: Quickshell.env("QS_RECORD_SCRIPT")
        || (Quickshell.env("HOME") + "/.config/hypr/scripts/screenrec.sh")
    readonly property string prefsDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property int launchDelay: 200

    readonly property var modes: [
        { id: "region", title: "Region", sub: "Drag a rectangle", icon: "\uf5cb" },   // vector-square
        { id: "window", title: "Window", sub: "Click a window",   icon: "\uf2d0" },   // window-maximize
        { id: "output", title: "Screen", sub: "Whole monitor",    icon: "\uf390" }    // display
    ]
    // segment rows (entries 3 and 4: frame rate, format); values are what screenrec.sh accepts
    readonly property var options: [
        { key: "fps",    title: "Frame rate", badge: "F", values: [30, 60],         labels: ["30", "60"], segW: 36 },
        { key: "format", title: "Format",     badge: "M", values: ["mp4", "webm"], labels: ["MP4", "WebM"], segW: 52 }
    ]

    property int fps: 60              // saved choices (see prefs below)
    property string format: "mp4"
    property bool audio: false
    property int cur: 0               // highlighted entry: 0-2 = mode tiles, 3 = frame rate, 4 = format, 5 = audio row
    property int lastMode: 0          // the menu reopens on the last used mode
    property string pendingMode: ""
    readonly property bool optStacked: card.width < 440   // frame rate / format rows stacked on a narrow card
    // concentric radii: card = R; tiles / segment rows / audio row sit 20 px inside it; key badges sit 8 px inside them

    onOpening: cur = lastMode
    onKeyPressed: ev => { if (win.handleKey(ev.key)) ev.accepted = true }

    // close first, start the recorder once the window is gone
    function choose(i) {
        if (!shown || i < 0 || i >= modes.length) return
        lastMode = i
        pendingMode = modes[i].id
        shown = false
        launch.restart()
    }

    // ---- options: frame rate / format / audio, saved on every change ----
    function value(key) { return key === "fps" ? fps : format }
    function setOption(key, v) {
        if (key === "fps") fps = v
        else if (key === "format") format = v
        saver.restart()
    }
    function cycle(key, step) {
        const o = options.find(x => x.key === key)
        const i = o.values.indexOf(value(key))
        setOption(key, o.values[(i + (step || 1) + o.values.length) % o.values.length])
    }
    function setAudio(on) { audio = on; saver.restart() }
    function activate() {
        if (cur < 3) choose(cur)
        else if (cur < 5) cycle(options[cur - 3].key, 1)
        else setAudio(!audio)
    }

    // keyboard (also what an isolated test drives); returns false for keys it doesn't use
    function handleKey(k) {
        const c = cur
        if (k === Qt.Key_Escape) close()
        else if (k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3) choose(k - Qt.Key_1)
        else if (k === Qt.Key_A) setAudio(!audio)
        else if (k === Qt.Key_F) cycle("fps", 1)
        else if (k === Qt.Key_M) cycle("format", 1)
        else if (k === Qt.Key_Left) cur = c < 3 ? Math.max(0, c - 1) : c === 4 ? 3 : c
        else if (k === Qt.Key_Right) cur = c < 3 ? Math.min(2, c + 1) : c === 3 ? 4 : c
        else if (k === Qt.Key_Down) cur = c < 3 ? 3 : c === 3 && optStacked ? 4 : 5
        else if (k === Qt.Key_Up) cur = c === 5 ? (optStacked ? 4 : 3) : c === 4 && optStacked ? 3 : c >= 3 ? lastMode : c
        else if (k === Qt.Key_Tab) cur = (c + 1) % 6
        else if (k === Qt.Key_Backtab) cur = (c + 5) % 6
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activate()
        else return false
        return true
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", win.prefsDir])
    Timer {
        id: saver
        interval: 400
        onTriggered: prefs.setText("fps=" + win.fps + "\nformat=" + win.format + "\naudio=" + (win.audio ? 1 : 0) + "\n")
    }
    FileView {
        id: prefs
        path: win.prefsDir + "/screenrec.conf"
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const i = line.indexOf("=")
                if (i < 0) continue
                const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim()
                if (k === "fps" && ["30", "60"].includes(v)) win.fps = parseInt(v)
                else if (k === "format" && ["mp4", "webm"].includes(v)) win.format = v
                else if (k === "audio" && (v === "0" || v === "1")) win.audio = v === "1"
            }
        }
    }

    Timer {
        id: launch
        interval: win.launchDelay
        onTriggered: {
            if (win.pendingMode === "") return
            Quickshell.execDetached([win.script, win.pendingMode, "--fps", String(win.fps), "--format", win.format,
                win.audio ? "--audio" : "--no-audio"])
            win.pendingMode = ""
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: win.modes
            ModeTile {
                required property var modelData
                required property int index
                icon: modelData.icon
                title: modelData.title
                sub: modelData.sub
                badge: index + 1
                sel: win.cur === index
                onHovered: win.cur = index
                onClicked: win.choose(index)
            }
        }
    }

    // frame rate | format: segment rows side by side (stacked on a narrow card)
    GridLayout {
        Layout.fillWidth: true
        columns: win.optStacked ? 1 : 2
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: win.options
            Rectangle {
                id: opt
                required property var modelData
                required property int index
                readonly property bool sel: win.cur === 3 + index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 44
                radius: Theme.radiusModal
                color: sel ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.fg, 0.05)
                border.width: 1
                border.color: sel ? Theme.alpha(Theme.accent, 0.7) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: win.cur = 3 + opt.index
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 8
                    Label { text: opt.modelData.title; color: opt.sel ? Theme.fg : Theme.fgDim; Layout.fillWidth: true; elide: Text.ElideRight }
                    KeyBadge { text: opt.modelData.badge; sel: opt.sel }
                    Row {
                        spacing: 2
                        Repeater {
                            model: opt.modelData.values
                            Btn {
                                required property var modelData
                                required property int index
                                outerRadius: Theme.radiusModal   // concentric with the row box, like the badges
                                inset: 8
                                implicitHeight: 26
                                implicitWidth: opt.modelData.segW
                                text: opt.modelData.labels[index]
                                active: win.value(opt.modelData.key) === modelData
                                onClicked: { win.cur = 3 + opt.index; win.setOption(opt.modelData.key, modelData) }
                            }
                        }
                    }
                }
            }
        }
    }

    // desktop audio switch (whole row is clickable)
    Rectangle {
        id: audioRow
        readonly property bool sel: win.cur === 5
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Theme.radiusModal
        color: sel ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.fg, 0.05)
        border.width: 1
        border.color: sel ? Theme.alpha(Theme.accent, 0.7) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: win.cur = 5
            onClicked: win.setAudio(!win.audio)
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            Icon {
                text: win.audio ? "\uf028" : "\uf6a9"     // volume-high / volume-xmark
                font.pixelSize: 15
                color: win.audio ? Theme.accent : Theme.fgDim
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 20
            }
            Label { text: "Record desktop audio"; color: win.audio ? Theme.fg : Theme.fgDim; Layout.fillWidth: true; elide: Text.ElideRight }
            KeyBadge { text: "A"; sel: audioRow.sel }
            Toggle { checked: win.audio; onToggled: v => win.setAudio(v) }
        }
    }

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "1 2 3 start · ←→↑↓ Enter · F fps · M format · A audio · Esc close"
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }
}
