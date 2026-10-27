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
    readonly property bool dragging: dim.dragging || blur.dragging || size.dragging || dots.dragging || morph.dragging
    readonly property var monitors: Quickshell.screens.filter(s => s && s.width > 0)
    property int monitorIdx: 0
    function pct(v) { return Math.round(v * 100) + " %" }
    function times(v) { return v <= 0 ? "instant" : Number(v.toFixed(2)) + "x" }
    // a changed morph time shows itself in the preview once the slider rests
    Connections { target: LockPrefs; function onMorphChanged() { morphShow.restart() } }
    Timer { id: morphShow; interval: 400; onTriggered: preview.demo() }

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

        SectionHead {
            title: "Clock"; detail: "morph at the Animations speed, with seconds 0.45 s at most"; Layout.topMargin: 6
            Btn { objectName: "btn-lock-morph"; text: "Show morph"; inset: 18; implicitHeight: 26; onClicked: preview.demo() }
        }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "showDate"; label: "Show the date" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "clock24h"; label: "24-hour clock"; hint: "off: 12-hour without AM / PM" }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "seconds"; label: "Seconds"; hint: "only the changing digits redraw each second" }
        PrefSlider { id: morph; title: "Morph time"; titleWidth: pg.titleW; store: LockPrefs; key: "morph"; format: v => pg.times(v) }
        SettingRow {
            title: "Screens"
            titleWidth: pg.titleW
            Label {
                text: "clock and date on these screens; the password dots stay in place on every screen"
                color: Theme.muted; font.pixelSize: Theme.fontCaption
                Layout.fillWidth: true; wrapMode: Text.Wrap
            }
        }
        MonitorToggles {
            Layout.fillWidth: true
            titleWidth: pg.titleW
            idPrefix: "toggle-lockclock"
            isOn: key => LockPrefs.hidden[key] !== true
            onToggled: (key, on) => LockPrefs.setClockOn(key, on)
        }

        SectionHead { title: "Playback"; Layout.topMargin: 6 }
        PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "mediaCard"; label: "Playback card"; hint: "under the dots while a player is open; on the screens with the clock" }

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
