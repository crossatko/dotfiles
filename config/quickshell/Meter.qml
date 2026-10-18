import QtQuick

// Thin horizontal bar: a track with an accent fill for `value` (0..1, clamped). Pill ends that follow the theme
// (square at radius 0). Used by Slider (its track), the OSD, the media seek bar and AI usage limits.
// `animMs` > 0 animates the fill (OutCubic unless `easingType` says otherwise); `animate: false` pauses that
// (e.g. while dragging).
Rectangle {
    id: m
    property real value: 0
    property color fillColor: Theme.accent
    property int animMs: 0
    property int easingType: Easing.OutCubic
    property bool animate: true

    implicitHeight: 6
    radius: Math.min(height / 2, Theme.radius)
    color: Theme.alpha(Theme.fg, 0.14)

    Rectangle {
        width: Math.max(0, Math.min(1, m.value)) * parent.width
        height: parent.height
        radius: parent.radius
        color: m.fillColor
        Behavior on width { enabled: m.animMs > 0 && m.animate; NumberAnimation { duration: m.animMs; easing.type: m.easingType } }
    }
}
