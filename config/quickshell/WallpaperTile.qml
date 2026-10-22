import QtQuick
import QtQuick.Effects

// One thumbnail of the Settings > Wallpaper & theme grid (SettingsWallpaper.qml): image (or a video's cached still)
// with a caption strip. `current` = what the edited monitor shows (accent ring + check), `cursor` = keyboard
// selection, `busy` = being applied, `unreadable` = a video ffmpeg could not read (dimmed, the page ignores clicks),
// `badge` = top-right tag ("▶ LOOP" on the playing video), "" = none.
Rectangle {
    id: cell
    property string name: ""
    property string source: ""          // image path, "" = no thumbnail yet
    property bool current: false
    property bool cursor: false
    property bool busy: false
    property bool unreadable: false
    property string badge: ""
    signal clicked()

    radius: Theme.radiusPage
    color: Theme.surface
    opacity: unreadable ? 0.4 : 1
    border.width: current || cursor || ma.containsMouse ? 3 : 1
    border.color: current ? Theme.accent : (cursor || ma.containsMouse) ? Theme.fg : Theme.alpha(Theme.overlay, 0.6)
    clip: true

    // thumbnail + caption, 3 px inside the cell (room for the 3 px border). clip only cuts the bounding box, so with
    // rounded cells the content is masked to a concentric rounded rect.
    Item {
        id: thumb
        readonly property int innerRadius: Theme.inner(cell.radius, 3)
        anchors.fill: parent
        anchors.margins: 3
        layer.enabled: innerRadius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: thumbMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Image {
            anchors.fill: parent
            source: cell.source !== "" ? "file://" + cell.source : ""
            sourceSize: Qt.size(640, 360)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle {
            visible: cell.badge !== ""
            anchors { right: parent.right; top: parent.top; margins: 6 }
            width: badgeLabel.implicitWidth + 12; height: 20
            radius: Math.min(4, Theme.radiusPage)
            color: Theme.alpha(Theme.bg, 0.78)
            Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: cell.badge
                font.pixelSize: Theme.fontCaption - 1; font.bold: true; font.letterSpacing: 1
                color: Theme.accent
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 24
            color: Theme.alpha(Theme.bg, 0.75)
            Label {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                font.pixelSize: Theme.fontCaption
                elide: Text.ElideMiddle
                verticalAlignment: Text.AlignVCenter
                text: cell.unreadable ? "unreadable: " + cell.name : cell.busy ? "Applying…" : cell.current ? "✓ " + cell.name : cell.name
                color: cell.current || cell.busy ? Theme.accent : Theme.fg
            }
        }
    }
    Rectangle {
        id: thumbMask
        anchors.fill: thumb
        radius: thumb.innerRadius
        visible: false
        layer.enabled: thumb.innerRadius > 0
    }
    // pointer-following highlight over the thumbnail (z above the content; the glow takes no clicks)
    HoverGlow { area: ma; radius: cell.radius; color: Theme.fg; z: 2 }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: cell.unreadable ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: cell.clicked()
    }
}
