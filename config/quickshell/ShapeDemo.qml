pragma ComponentBehavior: Bound
import QtQuick

// A scaled desktop (Settings > Look & feel > Shape): the wallpaper, the bar on its edge and two tiled windows laid out
// with Hyprland's gap math for `radius`, `gap` (window gap, edge gap = the same) and `border`. Default = the live
// values (Theme); a preset card binds its own. Any size: the screen is scaled to fit `width`.
Rectangle {
    id: mini
    property string wallpaper: LockWallpapers.primary     // the page passes the wallpaper of the monitor Settings is on
    property real cornerR: Theme.radius
    property real gap: Theme.gap
    property real borderPx: Theme.borderSize
    property bool floating: BarConfig.floating(Monitors.ordered.find(s => BarConfig.enabled(s)) ?? Monitors.primary ?? null)
    readonly property real gapIn: Math.round(gap / 2)
    // a 16:9 desktop (the same picture on every monitor; the real layout follows the real screen)
    readonly property real sw: 2560
    readonly property real sh: 1440
    readonly property real k: width / sw
    readonly property real barGap: floating ? gap : 0
    function s(v) { return v * k }
    function sb(v) { return v <= 0 ? 0 : Math.max(1, v * k) }   // a nonzero border stays visible at this scale

    implicitHeight: Math.round(width * sh / sw)
    radius: Theme.inner(Theme.radiusPage, 8)
    color: Theme.bgAlt
    border.width: 1
    border.color: Theme.alpha(Theme.overlay, 0.6)
    clip: true

    Image {
        anchors.fill: parent
        source: mini.wallpaper ? "file://" + mini.wallpaper : ""
        sourceSize.width: 640
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // bar
    Rectangle {
        x: mini.s(mini.barGap); y: mini.s(mini.barGap)
        width: mini.width - 2 * x; height: mini.s(Theme.barHeight)
        radius: mini.s(mini.floating ? mini.cornerR : 0)
        color: Theme.surface2
        Row {
            anchors { left: parent.left; leftMargin: mini.s(Theme.barPad); verticalCenter: parent.verticalCenter }
            spacing: mini.s(6)
            Repeater {
                model: [60, 40, 40]
                Rectangle {
                    required property int modelData
                    width: mini.s(modelData); height: mini.s(Theme.barHeight - 2 * Theme.barPad)
                    radius: mini.s(Theme.inner(mini.cornerR, Theme.barPad))
                    color: Theme.alpha(Theme.fg, 0.16)
                }
            }
        }
    }
    // two tiled windows: gaps_out at the screen edges, 2 * gaps_in between, border inside the box
    Repeater {
        model: 2
        Rectangle {
            required property int index
            readonly property real wy: Theme.barHeight + mini.barGap + mini.gap
            readonly property real areaW: mini.sw - 2 * mini.gap
            readonly property real w: (areaW - 2 * mini.gapIn) / 2
            x: mini.s(mini.gap + index * (w + 2 * mini.gapIn))
            y: mini.s(wy)
            width: mini.s(w)
            height: mini.s(mini.sh - wy - mini.gap)
            radius: mini.s(mini.cornerR)
            color: Theme.bg
            border.width: mini.sb(mini.borderPx)
            border.color: index === 0 ? Theme.accent : Theme.overlay
            Column {
                x: mini.s(40); y: mini.s(36)
                spacing: mini.s(22)
                Repeater {
                    model: [0.55, 0.8, 0.4, 0.7]
                    Rectangle {
                        required property real modelData
                        width: mini.s(1100) * modelData; height: mini.s(10)
                        radius: height / 2
                        color: Theme.alpha(Theme.fg, 0.18)
                    }
                }
            }
        }
    }
}
