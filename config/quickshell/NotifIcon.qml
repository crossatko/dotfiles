import QtQuick
import QtQuick.Effects
import Quickshell
import "launcher/js/NotifGlyph.js" as Glyphs

// Notification icon, Adwaita style: generic freedesktop names (dialog-information, mail-unread,
// network-transmit, ...) have a *symbolic* Adwaita icon, which is drawn in a palette color (`tint`: accent, red /
// yellow with meaning). App-specific names (steam, discord) have no symbolic variant and keep their own colored
// icon. Real image data sent with the notification (avatars, album art) is shown untouched.
Item {
    id: ico

    property string name: ""
    property string image: ""
    property color tint: Theme.accent
    property int size: Theme.iconCol + Theme.iconLg   // 40: the box of a card's app icon (NotifCard sets its own)

    implicitWidth: size
    implicitHeight: size

    // a drawing of the shell's own assets/ (black on transparent, e.g. the AirPods icon of BtNotifier) is tinted like a symbolic icon
    // matched on "/quickshell/assets/" so both the launch path (~/.config/quickshell) and the resolved repo path count
    readonly property string assetPath: name.replace(/^file:\/\//, "")
    readonly property bool asset: image === "" && (assetPath.startsWith(Quickshell.shellDir + "/assets/") || assetPath.indexOf("/quickshell/assets/") >= 0)
    readonly property bool direct: !asset && (image !== "" || name.startsWith("/") || name.startsWith("file://") || name.startsWith("image://"))
    readonly property string base: name.replace(/-symbolic$/, "")
    // a standard freedesktop name draws as a Vadivam glyph (NotifGlyph.js); "" = app-specific / unknown
    readonly property string glyph: direct || asset ? "" : Glyphs.glyph(name)
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

    // 2a. Vadivam glyph, same tint and box as the symbolic icon
    Icon {
        anchors.fill: parent
        visible: ico.glyph !== ""
        text: ico.glyph
        color: ico.tint
        font.pixelSize: Math.round(ico.size * 0.7)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // 2b. symbolic variant, tinted
    Image {
        id: sym
        anchors.fill: parent
        visible: false
        source: ico.asset ? "file://" + ico.assetPath : !ico.direct && ico.glyph === "" && ico.symPath !== "" ? "file://" + ico.symPath : ""
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
        visible: !ico.direct && !ico.asset && ico.glyph === "" && ico.symPath === ""
        source: !ico.direct && ico.base !== "" ? "image://icon/" + ico.base : ""
        sourceSize: Qt.size(ico.size * 2, ico.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
}
