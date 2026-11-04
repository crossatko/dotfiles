pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// The frame of a Settings screen preview (LockPreview, DeskClockPreview, PillPreview): the children are laid out on a virtual
// screen of `virtualW` x `virtualH` (fill it: `anchors.fill: parent`) scaled down uniformly to this item's width, with rounded
// corners (radiusItem) and a hairline. The corners are the layer's effect: the frame stays visible (layered parts inside an
// invisible item, such as the lock date's halo, were not drawn). `ratio` = preview px per virtual px. Height = the virtual aspect.
Item {
    id: sf
    property real virtualW: 1920
    property real virtualH: 1080
    readonly property real ratio: virtualW > 0 ? width / virtualW : 1
    readonly property Item cornerMask: corners
    default property alias content: stage.data
    implicitHeight: Math.round(width * virtualH / Math.max(1, virtualW))

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: sf.cornerMask }
        Item {
            id: stage
            width: sf.virtualW
            height: sf.virtualH
            scale: sf.ratio
            transformOrigin: Item.TopLeft
        }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: Theme.radiusItem; visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; radius: Theme.radiusItem; color: "transparent"; border.width: 1; border.color: Theme.alpha(Theme.overlay, 0.5) }
}
