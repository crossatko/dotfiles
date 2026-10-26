pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Lock screen: a live preview (LockPreview: the real LockView in preview mode, scaled) and the LockPrefs
// keys (lock.json). Everything applies live: the preview at once, the real lock at once if it is up, else at the next
// lock. "Lock now" asks THIS shell for the same lock as SUPER+SHIFT+L (`qs -p <its config> ipc call lock lock`).
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: dim.dragging || blur.dragging || size.dragging || dots.dragging
    readonly property var monitors: Quickshell.screens.filter(s => s && s.width > 0)
    property int monitorIdx: 0
    function pct(v) { return Math.round(v * 100) + " %" }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        SectionHead {
            title: "Preview"
            detail: pg.monitors.length > 1 ? "" : "as on " + (pg.monitors[0] ? pg.monitors[0].name : "this monitor")
            Btn { objectName: "btn-lock-replay"; text: "Replay"; inset: 18; implicitHeight: 26; onClicked: preview.replay() }
            Btn {
                objectName: "btn-lock-now"
                text: "Lock now"
                inset: 18; implicitHeight: 26
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "lock", "lock"])
            }
        }
        Segmented {
            visible: pg.monitors.length > 1
            values: pg.monitors.map((s, i) => i)
            labels: pg.monitors.map(s => s.name)
            current: pg.monitorIdx
            inset: 18; segHeight: 24
            onPicked: v => pg.monitorIdx = v
        }
        LockPreview {
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight      // 16:9
            screen: pg.monitors[Math.min(pg.monitorIdx, pg.monitors.length - 1)] || null
        }

        SectionHead { title: "Look"; Layout.topMargin: 6 }
        PrefSlider { id: dim; title: "Wallpaper dim"; titleWidth: pg.titleW; store: LockPrefs; key: "dim"; format: v => pg.pct(v) }
        PrefSlider { id: blur; title: "Blur"; titleWidth: pg.titleW; store: LockPrefs; key: "blur"; format: v => v + " px" }
        PrefSlider { id: size; title: "Clock size"; titleWidth: pg.titleW; store: LockPrefs; key: "clockSize"; format: v => pg.pct(v) }
        PrefSlider { id: dots; title: "Dot size"; titleWidth: pg.titleW; store: LockPrefs; key: "dotSize"; format: v => (v * 100).toFixed(1) + " %" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "showDate"; label: "Show the date" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "clock24h"; label: "24-hour clock"; hint: "off: 12-hour without AM / PM" }

        SectionHead { title: "Motion"; detail: "at the Animations speed; none = instant"; Layout.topMargin: 6 }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "clockReveal"; label: "Clock reveal"; hint: "the digits form after the lock is up" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "snapshot"; label: "Desktop snapshot"; hint: "needed for the ring transitions; off: the desktop is never captured" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "unlockRing"; label: "Unlock ring"; hint: "the lock opens onto the desktop" }

        SectionHead { title: "Video wallpaper"; detail: "play-once videos play a burst"; Layout.topMargin: 6 }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnLock"; label: "When the lock comes up" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnType"; label: "While typing" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnSubmit"; label: "On Enter" }

        RowLayout {
            Layout.topMargin: 6
            Btn { objectName: "btn-lock-reset"; text: "Reset all"; inset: 18; implicitHeight: 26; enabledLook: Object.keys(LockPrefs.data).length > 0; onClicked: LockPrefs.reset() }
            Item { Layout.fillWidth: true }
        }
    }
}
