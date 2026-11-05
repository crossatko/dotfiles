import QtQuick
import QtQuick.Shapes

// A ring meter: a full track circle and an arc from the top, clockwise, for `value` (0..1, clamped). `size` is the
// square it fills, `stroke` the line width, `inset` the gap from the square's edge to the line's centre. Used by
// BudRing (AirPods battery) and the reminder chip.
Shape {
    id: ring
    property real size: Theme.rowH
    property real stroke: Theme.gapTight      // line width (BudRing's 4; the bar chip sets its own)
    property real inset: stroke / 2
    property real value: 0
    property color color: Theme.accent
    property color trackColor: Theme.itemActive
    readonly property real r: size / 2 - inset

    implicitWidth: size
    implicitHeight: size
    preferredRendererType: Shape.CurveRenderer     // analytic anti-aliasing: crisp at fractional scales

    ShapePath {
        strokeColor: ring.trackColor; strokeWidth: ring.stroke; fillColor: Theme.alpha(Theme.bg, 0)
        PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: ring.r; radiusY: ring.r; startAngle: 0; sweepAngle: 360 }
    }
    ShapePath {
        strokeColor: ring.color; strokeWidth: ring.stroke; fillColor: Theme.alpha(Theme.bg, 0); capStyle: ShapePath.RoundCap
        PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, ring.value)) }
    }
}
