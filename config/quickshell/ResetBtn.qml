import QtQuick

// The per-key reset at the end of a Settings row (DESIGN.md "Settings"): a small undo glyph, dim while the key is at its
// default (`set` false), lit while a saved value exists. Used by PrefSlider, GlassOptRow, GlassAdvanced (tint),
// GlassSurfaceProfile, MotionAdvanced and ShapeAdvanced; the row wires `set` and `onClicked`.
Btn {
    property bool set: true
    readonly property int resetW: 24      // glyph-only button, narrower and shorter than controlH so a row stays rowH
    readonly property int resetH: 20
    icon: true
    text: Icons.undo
    implicitWidth: resetW
    implicitHeight: resetH
    outerRadius: Theme.radius
    inset: Theme.pad
    enabledLook: set
}
