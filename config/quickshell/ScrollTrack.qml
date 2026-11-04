import QtQuick

// Thin draggable scrollbar for a Flickable, plus a mouse-wheel that moves a fixed distance per notch
// (Qt's own Flickable wheel is slow and varies with the platform). Put it as a child of the Flickable's parent,
// anchored along the right edge: `ScrollTrack { target: flick; anchors { right: parent.right; top: ...; bottom: ... } }`.
Item {
    id: root
    required property Flickable target
    property real wheelStep: 110          // px per wheel notch (angleDelta 120)

    implicitWidth: 10
    visible: target.contentHeight > target.height + 1

    readonly property real maxY: Math.max(1, target.contentHeight - target.height)
    readonly property real handleH: Math.max(32, height * target.height / Math.max(1, target.contentHeight))

    Rectangle {
        id: handle
        x: 3
        width: 4
        radius: 2
        height: root.handleH
        y: (root.height - height) * Math.max(0, Math.min(1, root.target.contentY / root.maxY))
        color: Theme.alpha(Theme.fg, drag.active || hover.hovered ? 0.5 : 0.25)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    HoverHandler { id: hover }

    // dragging the handle, or clicking the track to jump there
    DragHandler {
        id: drag
        target: null
        yAxis.enabled: true
        xAxis.enabled: false
        onActiveChanged: if (active) grab = centroid.position.y - handle.y
        onCentroidChanged: if (active) root.seek(centroid.position.y - grab + root.handleH / 2)
        property real grab: 0
    }
    TapHandler { onTapped: p => root.seek(p.position.y) }

    function seek(y: real): void {
        const frac = Math.max(0, Math.min(1, (y - handleH / 2) / Math.max(1, height - handleH)))
        target.contentY = frac * maxY
    }

    // mounted on the Flickable itself so the wheel works over the whole page
    WheelHandler {
        parent: root.target
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            const t = root.target
            const notch = ev.angleDelta.y !== 0 && ev.angleDelta.y % 120 === 0   // a mouse also reports a small pixelDelta; ignore it
            const dy = notch ? ev.angleDelta.y / 120 * root.wheelStep : ev.pixelDelta.y
            t.contentY = Math.max(0, Math.min(t.contentHeight - t.height, t.contentY - dy))
        }
    }
}
