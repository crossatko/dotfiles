import QtQuick
import QtQuick.Layouts

// One monitor card of Settings > Wallpaper & theme (SettingsWallpaper.qml): what the monitor shows (thumbnail, a
// play glyph on a video's still), model, connector + what it shows. `picked` = the monitor being edited (accent
// border, same look as the Bar page's monitor cards), `primary` = the theme source (palette glyph + PRIMARY).
Rectangle {
    id: card
    property string title: ""
    property string connector: ""
    property string detail: ""          // "name", "video.mp4 · loop", "same as primary"
    property string thumb: ""           // image path (a video's still)
    property bool video: false
    property bool picked: false
    property bool grouped: false        // linked to the picked monitor (shares its wallpaper): softer accent border
    property bool primary: false
    property var notches: []            // MonitorCardRow.notchesOf(index): round cut-outs for the link buttons
    signal clicked()
    readonly property bool roomy: width >= 250      // narrow (3 across at the minimum size): smaller thumbnail, icon-only badge

    implicitHeight: 62
    height: implicitHeight
    radius: Theme.radiusPage
    color: picked ? Theme.alpha(Theme.accent, 0.12) : grouped ? Theme.alpha(Theme.accent, 0.06) : glow.hovered ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)
    border.width: 1
    border.color: picked ? Theme.alpha(Theme.accent, 0.85) : grouped ? Theme.alpha(Theme.accent, 0.5) : Theme.alpha(Theme.overlay, 0.45)
    layer.enabled: notches.length > 0
    layer.effect: NotchMask { notches: card.notches; radius: card.radius; borderWidth: card.border.width; borderColor: card.border.color }

    HoverGlow { id: glow; area: area; radius: card.radius }   // pointer-following highlight (HoverHandler: never takes clicks)
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.clicked() }

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 12; topMargin: 9; bottomMargin: 9 }
        spacing: 10
        Rectangle {
            Layout.preferredWidth: card.roomy ? 64 : 48
            Layout.preferredHeight: card.roomy ? 36 : 27
            radius: Math.min(4, Theme.radiusPage)
            color: Theme.surface
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.5)
            clip: true
            Image {
                anchors { fill: parent; margins: 1 }
                source: card.thumb !== "" ? "file://" + card.thumb : ""
                sourceSize: Qt.size(128, 72)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {      // play glyph: this monitor plays a video (the thumbnail is its still)
                visible: card.video
                anchors.centerIn: parent
                width: 18; height: 18; radius: 9
                color: Theme.alpha(Theme.bg, 0.7)
                Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; text: ""; font.pixelSize: 8; color: Theme.fg }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: card.title; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: card.picked; color: card.picked ? Theme.fg : Theme.fgDim }
                Icon { visible: card.primary; text: ""; font.pixelSize: 11; color: Theme.accent }
                Label { visible: card.primary && card.roomy; text: "PRIMARY"; font.pixelSize: Theme.fontCaption - 1; font.bold: true; font.letterSpacing: 1; color: Theme.accent }
            }
            Label {
                text: (card.connector !== card.title ? card.connector + "  ·  " : "") + card.detail   // no model: the title is the connector
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fontCaption
                color: Theme.muted
            }
        }
    }
}
