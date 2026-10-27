import QtQuick
import QtQuick.Layouts

// One Settings > Glass value row: title | slider | value | reset. `o` = a GlassTuneCtl.opts entry (min, max, dec,
// unit, curve: slider response exponent > 1 gives the low end more travel). `inherited` = the value is not set here
// (a surface profile showing the global value): the value is muted. The slider's default notch is the option's default,
// or `mark` (0..1) when set (a surface profile: the global value); a double-click = reset().
SettingRow {
    id: row
    property var o: ({ min: 0, max: 1, dec: 2 })
    property real cur: 0
    property bool changed: false        // the reset button looks active
    property bool inherited: false
    property real mark: -1
    property real valueW: 62
    property string resetName: "reset-" + (o.key || "")
    signal moved(real v)
    signal reset()

    function toNorm(v) { return Math.pow(Math.max(0, Math.min(1, (v - o.min) / (o.max - o.min))), 1 / (o.curve || 1)) }
    function fromNorm(n) { return o.min + (o.max - o.min) * Math.pow(n, o.curve || 1) }

    Slider {
        wheel: false
        objectName: "slider-" + (row.o.key || "")
        Layout.fillWidth: true
        value: row.toNorm(row.cur)
        notches: [row.mark >= 0 ? row.mark : row.toNorm(row.o.def ?? row.o.min)]
        resetToNotch: false
        onResetRequested: row.reset()
        onMoved: v => row.moved(row.fromNorm(v))
    }
    Label {
        text: row.cur.toFixed(row.o.dec) + (row.o.unit || "")
        Layout.preferredWidth: row.valueW
        horizontalAlignment: Text.AlignRight
        color: row.inherited ? Theme.muted : Theme.fg
        font.pixelSize: Theme.fontSmall
    }
    ResetBtn {
        objectName: row.resetName
        set: row.changed
        onClicked: row.reset()
    }
}
