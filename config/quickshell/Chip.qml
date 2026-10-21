import QtQuick
import QtQuick.Layouts

// One recessed module on the bar. Children go in the row; set `active` for the
// accent-filled look and connect `clicked`/`wheel` for interaction.
// Geometry (Theme.chip*): chipHeight tall; icon-only content (<= one icon box wide) gives a chipHeight square so the
// pill is evenly padded around the icon; otherwise chipPadX (`padX`) on both sides. Widths are whole pixels.
Rectangle {
    id: chip

    default property alias content: row.data
    property bool active: false
    property bool dim: false
    property int padX: Theme.chipPadX
    readonly property real contentW: row.implicitWidth
    readonly property bool iconOnly: contentW <= Theme.chipIcon
    signal clicked(var mouse)
    signal wheel(int dy)

    // no glass of its own: the chip sits flat on the glass of its panel (the bar container, see Bar.qml)

    implicitHeight: Theme.chipHeight
    implicitWidth: Math.max(Theme.chipHeight, iconOnly ? Theme.chipHeight : Math.ceil(row.implicitWidth) + 2 * padX)   // never narrower than tall (min 1:1)
    radius: Theme.radiusChip   // inset barPad inside the bar
    color: active ? Theme.alpha(Theme.accent, 0.28)
         : hover.containsMouse ? Theme.alpha(Theme.fg, 0.10)
         : Theme.alpha(Theme.bg, Theme.glass ? 0.10 : 0.35)
    border.width: active ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.8)
    opacity: dim ? 0.55 : 1

    Behavior on color { ColorAnimation { duration: 120 } }

    // Blank px between the row edges and the visible ink of its first / last visible item. BarIcon and BarLabel
    // report their own ink insets (InkMeter); other items (tray images, the record dot) count as solid.
    function inkItems() { const r = []; for (const c of row.children) if (c.visible && c.implicitWidth > 0) r.push(c); return r }
    // (items are packed from x 0 to row.implicitWidth; reading their x/width or the row size here re-polishes the
    // layout inside the binding = binding loop, so the row's ceil() slack is added in row.x instead)
    readonly property real inkL: { const a = inkItems(); return a.length && a[0].inkLeft !== undefined ? a[0].inkLeft : 0 }
    readonly property real inkR: { const a = inkItems(); const c = a[a.length - 1]; return c && c.inkRight !== undefined ? c.inkRight : 0 }
    readonly property bool inkAware: { const a = inkItems(); return a.length > 0 && (a[0].inkLeft !== undefined || a[a.length - 1].inkRight !== undefined) }

    RowLayout {
        id: row
        // Centred on the visible ink: equal padding from the chip edges to the icon ink on the left and the text ink
        // on the right. This x may be fractional: glyphs are rendered with horizontal sub-pixel positioning, so a
        // half-pixel shift is real and stays sharp (an odd leftover pixel cannot be split otherwise). Rows without
        // ink-reporting items (tray bitmaps) and icon-only chips (box centred, BarIcon centres the ink) stay on
        // whole pixels.
        y: 0
        width: Math.ceil(implicitWidth)
        height: parent.height
        spacing: Theme.chipGap
    }
    // Bound outside the RowLayout and delayed: the ink insets and the row width are laid-out values, so a layout
    // pass (a chip item appearing / changing size) re-enters the row's own x binding = binding loop. Delayed
    // evaluates it once after the pass settles.
    Binding {
        target: row; property: "x"; delayed: true
        value: chip.iconOnly || !chip.inkAware ? Math.round((chip.width - row.width) / 2)
                                               : (chip.width - chip.contentW + chip.inkR - chip.inkL) / 2
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        z: -1                  // under the content so children (tray icons) get their own clicks
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => chip.clicked(mouse)
        onWheel: w => chip.wheel(w.angleDelta.y)
    }
}
