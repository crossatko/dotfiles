pragma ComponentBehavior: Bound
import QtQuick

// A tiny 16:9 sketch of the lock screen for the Layout cards (Settings > Lock screen): a dark wallpaper box with the
// clock bar, the date line and the playback card the preset (Presets.lockLayout id in `preset`) shows, plus the
// password dots. Plain Rectangles, cheap enough for one per card.
Rectangle {
    id: sk
    property string preset: "date"
    readonly property var p: Presets.lockLayout.find(x => x.id === sk.preset) ?? null
    readonly property bool date: p ? p.v.showDate : LockPrefs.showDate
    readonly property bool card: p ? p.v.mediaCard : LockPrefs.mediaCard

    color: Theme.alpha(Theme.bg, 0.9)
    radius: Theme.inner(Theme.radiusPage, 8)
    clip: true

    Column {
        anchors.centerIn: parent
        spacing: Math.round(sk.height * 0.07)
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: sk.width * 0.46; height: sk.height * 0.2; radius: height / 3; color: Theme.alpha(Theme.fg, 0.85) }
        Rectangle { visible: sk.date; anchors.horizontalCenter: parent.horizontalCenter; width: sk.width * 0.28; height: Math.max(2, sk.height * 0.05); radius: height / 2; color: Theme.alpha(Theme.fg, 0.45) }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(sk.height * 0.05)
            Repeater { model: 4; Rectangle { id: dot; required property int index; width: Math.max(3, sk.height * 0.06); height: dot.width; radius: dot.width / 2; color: Theme.alpha(Theme.fg, dot.index < 2 ? 0.8 : 0.3) } }
        }
        Rectangle {
            visible: sk.card
            anchors.horizontalCenter: parent.horizontalCenter
            width: sk.width * 0.4; height: sk.height * 0.17; radius: height / 3
            color: Theme.alpha(Theme.fg, 0.16); border.width: 1; border.color: Theme.alpha(Theme.fg, 0.25)
            Rectangle { x: parent.height * 0.2; anchors.verticalCenter: parent.verticalCenter; width: parent.height * 0.6; height: width; radius: width / 4; color: Theme.alpha(Theme.accent, 0.8) }
            Rectangle { x: parent.height; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; height: Math.max(2, parent.height * 0.18); radius: height / 2; color: Theme.alpha(Theme.fg, 0.6) }
        }
    }
}
