import QtQuick
import QtQuick.Effects

// Notification icon, Adwaita style: generic freedesktop names (dialog-information, mail-unread,
// network-transmit, ...) have a *symbolic* Adwaita icon, which is drawn in a palette color.
// App-specific names (steam, discord) have no symbolic variant and keep their own colored icon.
// Real image data sent with the notification (avatars, album art) is shown untouched.
Item {
    id: ico

    property string name: ""
    property string image: ""
    property color tint: Theme.accent
    property int size: 40

    implicitWidth: size
    implicitHeight: size

    readonly property bool direct: image !== "" || name.startsWith("/") || name.startsWith("file://") || name.startsWith("image://")
    readonly property string base: name.replace(/-symbolic$/, "")
    readonly property string symPath: Icons.symbolic[base] || ""

    // 1. real image / explicit path: as is
    Image {
        anchors.fill: parent
        visible: ico.direct
        source: !ico.direct ? ""
              : ico.image !== "" ? (ico.image.startsWith("/") ? "file://" + ico.image : ico.image)
              : ico.name.startsWith("/") ? "file://" + ico.name : ico.name
        sourceSize: Qt.size(ico.size * 2, ico.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    // 2. symbolic variant, tinted
    Image {
        id: sym
        anchors.fill: parent
        visible: false
        source: !ico.direct && ico.symPath !== "" ? "file://" + ico.symPath : ""
        sourceSize: Qt.size(ico.size * 2, ico.size * 2)
        fillMode: Image.PreserveAspectFit
    }
    MultiEffect {
        anchors.fill: parent
        source: sym
        visible: sym.status === Image.Ready
        brightness: 1.0
        colorization: 1.0
        colorizationColor: ico.tint
    }

    // 3. no symbolic icon: the app's own icon
    Image {
        anchors.fill: parent
        visible: !ico.direct && ico.symPath === ""
        source: !ico.direct && ico.base !== "" ? "image://icon/" + ico.base : ""
        sourceSize: Qt.size(ico.size * 2, ico.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
}
