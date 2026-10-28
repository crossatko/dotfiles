pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// The preview inside one Layout card (Settings > Lock screen): a 16:9 mini lock of `screen` (the MonitorSection's pick):
// its wallpaper still with the saved backdrop (blur, dim veil as LockView), the clock as text in the saved size / 24 h /
// seconds, then what the preset (Presets.lockLayout id in `preset`) shows: the date line, the password dots and the
// playback card. Light ink as the glass lettering on the dimmed wallpaper. One Image per card, cheap.
Item {
    id: sk
    property string preset: "date"
    property var screen: Monitors.selected
    readonly property var p: Presets.lockLayout.find(x => x.id === sk.preset) ?? null
    readonly property bool date: p ? p.v.showDate : LockPrefs.showDate
    readonly property bool card: p ? p.v.mediaCard : LockPrefs.mediaCard
    readonly property var inkSet: Theme.barInkLight      // light ink, as the glass lettering on the dimmed wallpaper
    readonly property color ink: inkSet.fg
    readonly property string time: (LockPrefs.clock24h ? "14:25" : "2:25") + (LockPrefs.seconds ? ":36" : "")
    readonly property real u: height / 100           // 1 % of the sketch height

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: corners }
        Rectangle { anchors.fill: parent; color: Theme.bgAlt }
        Image {
            anchors.fill: parent
            source: { const w = LockWallpapers.stillFor(sk.screen); return w ? "file://" + w : "" }
            sourceSize.width: 320
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            layer.enabled: LockPrefs.blur > 0
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.min(1, LockPrefs.blur / LockPrefs.blurMax) }
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.lockDim }      // the lock's veil (LockView)

        Column {
            anchors.centerIn: parent
            spacing: Math.round(sk.u * 5)
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sk.time
                color: Theme.alpha(sk.ink, 0.92)
                font.pixelSize: Math.max(8, Math.round(sk.height * LockPrefs.clockSize))
                font.weight: Font.DemiBold
            }
            Rectangle {
                visible: sk.date
                anchors.horizontalCenter: parent.horizontalCenter
                width: sk.width * 0.24; height: Math.max(2, sk.u * 3); radius: height / 2
                color: Theme.alpha(sk.ink, 0.55)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(sk.u * 3)
                Repeater {
                    model: 4
                    Rectangle {
                        id: dot
                        required property int index
                        width: Math.max(3, Math.round(sk.height * LockPrefs.clockSize * LockPrefs.dotSize * 2.4)); height: width; radius: width / 2
                        color: Theme.alpha(sk.ink, dot.index < 2 ? 0.85 : 0.35)
                    }
                }
            }
            Rectangle {
                visible: sk.card
                anchors.horizontalCenter: parent.horizontalCenter
                width: sk.width * 0.36; height: sk.u * 15; radius: height / 3
                color: Theme.alpha(sk.ink, 0.14); border.width: 1; border.color: Theme.alpha(sk.ink, 0.22)
                Rectangle { x: parent.height * 0.18; anchors.verticalCenter: parent.verticalCenter; width: parent.height * 0.64; height: width; radius: width / 4; color: Theme.alpha(Theme.accent, 0.85) }
                Rectangle { x: parent.height; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -parent.height * 0.12; width: parent.width * 0.42; height: Math.max(2, parent.height * 0.14); radius: height / 2; color: Theme.alpha(sk.ink, 0.7) }
                Rectangle { x: parent.height; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: parent.height * 0.16; width: parent.width * 0.26; height: Math.max(2, parent.height * 0.1); radius: height / 2; color: Theme.alpha(sk.ink, 0.4) }
            }
        }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: Theme.inner(Theme.radiusPage, 8); visible: false; layer.enabled: true }
}
