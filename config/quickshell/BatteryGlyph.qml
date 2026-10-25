import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell

// A filled battery for bar chips (Font Awesome 7 Sharp has only the outline batteries): a sharp-cornered body with
// the terminal nub, the body filled with `color` up to `level` (0..100), the rest a dim track of the same colour inside a one
// device px outline, a
// bolt cut into it while `charging`. Same box as BarIcon (Theme.chipIcon square, the drawing centred in it) and
// the same chip contract: inkLeft / inkRight are the blank px between the box edges and the drawing. Every edge
// sits on a whole DEVICE pixel (sizes are rounded in device px, `dpr` = the window's ratio), so the body stays
// crisp at fractional scales.
Item {
    id: bg
    property int level: 0
    property bool charging: false
    property color color: Theme.fg

    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1   // qmllint disable missing-property
    function px(v) { return Math.max(1, Math.round(v * dpr)) / dpr }   // logical size of a whole device-px length
    // proportions of FA Sharp's battery at the chip icon size: 14 x 9 body, 2 x 4 nub
    readonly property real bodyW: px(Theme.chipIcon - 2)
    readonly property real bodyH: { const h = Math.round(9 * dpr), n = Math.round(4 * dpr); return ((h - n) % 2 ? h + 1 : h) / dpr }   // nub centres exactly
    readonly property real nubW: px(2)
    readonly property real nubH: px(4)
    readonly property real inkW: bodyW + nubW
    readonly property real x0: Math.round((width - inkW) / 2 * dpr) / dpr
    readonly property real y0: Math.round((height - bodyH) / 2 * dpr) / dpr

    readonly property real inkLeft: x0
    readonly property real inkRight: width - x0 - inkW

    Layout.preferredWidth: Theme.chipIcon
    Layout.preferredHeight: Theme.chipIcon
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Theme.chipIcon
    implicitHeight: Theme.chipIcon

    readonly property real line: px(1)     // outline: one device pixel at every scale
    Rectangle {      // body: outline in the colour, dim track inside
        x: bg.x0; y: bg.y0; width: bg.bodyW; height: bg.bodyH
        color: Theme.alpha(bg.color, 0.22)
        border.width: bg.line
        border.color: bg.color
    }
    Rectangle {      // charge: fills the body up to the level, outline included
        x: bg.x0; y: bg.y0; height: bg.bodyH
        width: Math.round(bg.bodyW * Math.max(0, Math.min(100, bg.level)) / 100 * bg.dpr) / bg.dpr
        color: bg.color
    }
    Rectangle {      // terminal nub
        x: bg.x0 + bg.bodyW; y: bg.y0 + (bg.bodyH - bg.nubH) / 2; width: bg.nubW; height: bg.nubH
        color: bg.color
    }
    Shape {          // bolt, cut out of the body in the bar's background colour
        visible: bg.charging
        x: bg.x0; y: bg.y0; width: bg.bodyW; height: bg.bodyH
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: bolt
            strokeWidth: -1
            fillColor: bg.level < 50 ? bg.color : Theme.bg     // on the track: the colour; on the charge: cut out
            readonly property real w: bg.bodyW
            readonly property real h: bg.bodyH
            startX: bolt.w * 0.56; startY: 0
            PathLine { x: bolt.w * 0.30; y: bolt.h * 0.56 }
            PathLine { x: bolt.w * 0.48; y: bolt.h * 0.56 }
            PathLine { x: bolt.w * 0.42; y: bolt.h }
            PathLine { x: bolt.w * 0.70; y: bolt.h * 0.42 }
            PathLine { x: bolt.w * 0.52; y: bolt.h * 0.42 }
            PathLine { x: bolt.w * 0.56; y: 0 }
        }
    }
}
