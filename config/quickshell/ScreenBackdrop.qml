pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// What a monitor shows under a pill (PillPreview): a fill, its wallpaper still (cover
// crop, LockWallpapers.stillFor), a sketch of its bar (PillBarSketch) and its reserved left / right strips (`reserved`, e.g. the
// pinned-video strip: a dim veil). It draws the part `view` of the screen (screen px; default the whole screen) into its own
// size and decodes only that part of the still (WallpaperCut), at `decodeWidth` px across (default its width).
// `frost` (a rect in screen px, empty = none): the wallpaper blurred inside a rounded rect there, a sketch of the
// compositor's glass under a card drawn on top (the Settings window cannot show the real glass there).
Item {
    id: bd
    property var screen: null
    // qmllint disable missing-property
    readonly property real sw: screen && screen.width > 0 ? screen.width : 1920
    readonly property real sh: screen && screen.height > 0 ? screen.height : 1080
    // qmllint enable missing-property
    property rect view: Qt.rect(0, 0, sw, sh)
    property int decodeWidth: width
    property var reserved: ({ left: 0, top: 0, right: 0, bottom: 0 })
    property rect frost: Qt.rect(0, 0, 0, 0)
    property real frostRadius: Theme.radius
    readonly property int frostBlur: 48       // the sketch's blur radius (px): about the compositor glass's frost
    readonly property string still: LockWallpapers.stillFor(bd.screen)
    readonly property real scaleX: view.width > 0 ? width / view.width : 1        // item px per screen px
    readonly property real decodeScale: view.width > 0 ? decodeWidth / view.width : 1
    readonly property Item frostMask: mask
    clip: true

    // the still's aspect, from a tiny decode (the parts below need it for the cover crop)
    Image { id: probe; visible: false; source: bd.still; sourceSize.width: 32; asynchronous: true }
    readonly property real aspect: probe.status === Image.Ready && probe.implicitHeight > 0 ? probe.implicitWidth / probe.implicitHeight : 0

    Rectangle { anchors.fill: parent; color: Theme.itemActive }
    WallpaperCut {
        anchors.fill: parent
        source: bd.still; aspect: bd.aspect; screenW: bd.sw; screenH: bd.sh
        view: bd.view
        decodeScale: bd.decodeScale
    }
    // things at screen positions: the bar, the reserved strips
    Item {
        x: -bd.view.x * bd.scaleX
        y: -bd.view.y * bd.scaleX
        width: bd.sw
        height: bd.sh
        scale: bd.scaleX
        transformOrigin: Item.TopLeft
        PillBarSketch { anchors.fill: parent; screen: bd.screen }
        Rectangle { width: bd.reserved.left; height: parent.height; color: Theme.alpha(Theme.bg, 0.55); visible: width > 0 }
        Rectangle { x: parent.width - width; width: bd.reserved.right; height: parent.height; color: Theme.alpha(Theme.bg, 0.55); visible: width > 0 }
    }

    // the frosted copy: wallpaper + bar, blurred, cut to the rounded rect; card-sized (its layer and blur are too)
    Item {
        id: frostBox
        x: (bd.frost.x - bd.view.x) * bd.scaleX
        y: (bd.frost.y - bd.view.y) * bd.scaleX
        width: bd.frost.width * bd.scaleX
        height: bd.frost.height * bd.scaleX
        visible: width > 0 && height > 0
        clip: true
        layer.enabled: visible
        layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: bd.frostBlur; maskEnabled: true; maskSource: bd.frostMask }
        Rectangle { anchors.fill: parent; color: Theme.itemActive }
        WallpaperCut {
            anchors.fill: parent
            source: bd.still; aspect: bd.aspect; screenW: bd.sw; screenH: bd.sh
            view: bd.frost
            decodeScale: bd.decodeScale / 2
        }
        Item {
            x: -bd.frost.x * bd.scaleX
            y: -bd.frost.y * bd.scaleX
            width: bd.sw
            height: bd.sh
            scale: bd.scaleX
            transformOrigin: Item.TopLeft
            PillBarSketch { anchors.fill: parent; screen: bd.screen }
        }
    }
    Rectangle { id: mask; width: frostBox.width; height: frostBox.height; radius: bd.frostRadius * bd.scaleX; visible: false; layer.enabled: true }
}
