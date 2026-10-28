import QtQuick

// A page action at the end of the monitor strip (MonitorSection children): an icon button as tall as a chip, its name in
// a tooltip (`tip`, also the accessible name; Tab + Space / Enter). Optional short `text` after the glyph only where the
// glyph alone cannot tell two actions apart (copy from one of several monitors).
Btn {
    implicitHeight: Theme.rowH              // MonitorSection.chipH
    minWidth: implicitHeight
    outerRadius: Theme.radiusPage
    inset: 0
}
