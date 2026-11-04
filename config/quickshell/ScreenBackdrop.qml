pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// What a monitor shows under a pill, at real pixels (PillPreview: the screen mock and the actual-size crop): a fill, its
// wallpaper still (cover crop, LockWallpapers.stillFor) and a sketch of its bar (PillBarSketch). Size it to the screen.
// `frost` (a rect in these coordinates, empty = none): the wallpaper blurred inside a rounded rect there, a sketch of the
// compositor's glass under a card drawn on top (the Settings window cannot show the real glass there).
Item {
    id: bd
    property var screen: null
    property int decodeWidth: width          // the still's decode width (a scaled-down mock needs fewer pixels)
    property rect frost: Qt.rect(0, 0, 0, 0)
    property real frostRadius: Theme.radius
    readonly property int frostBlur: 48       // the sketch's blur radius (px): about the compositor glass's frost
    readonly property string still: LockWallpapers.stillFor(bd.screen)
    readonly property Item frostMask: mask

    Rectangle { anchors.fill: parent; color: Theme.itemActive }
    Image {
        anchors.fill: parent
        source: bd.still
        sourceSize.width: Math.max(64, bd.decodeWidth)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    PillBarSketch { anchors.fill: parent; screen: bd.screen }

    // the frosted copy: wallpaper + bar, blurred, cut to the rounded rect; card-sized (its layer and blur are too)
    Item {
        id: frostBox
        x: bd.frost.x
        y: bd.frost.y
        width: bd.frost.width
        height: bd.frost.height
        visible: width > 0 && height > 0
        clip: true
        layer.enabled: visible
        layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: bd.frostBlur; maskEnabled: true; maskSource: bd.frostMask }
        Item {
            x: -frostBox.x
            y: -frostBox.y
            width: bd.width
            height: bd.height
            Rectangle { anchors.fill: parent; color: Theme.itemActive }
            Image {
                anchors.fill: parent
                source: bd.still
                sourceSize.width: Math.max(64, Math.round(bd.decodeWidth / 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            PillBarSketch { anchors.fill: parent; screen: bd.screen }
        }
    }
    Rectangle { id: mask; width: frostBox.width; height: frostBox.height; radius: bd.frostRadius; visible: false; layer.enabled: true }
}
