import QtQuick
import QtQuick.Layouts

// One usage-limit window in the AI popup: "Session  5-hour window      resets in 2h 14m   62%" over a
// meter. `win` = {title, detail, percent (0..100+), resetsAt (epoch s | null)} from bin/ai-usage.
// `stale` dims it (values kept from an earlier check).
ColumnLayout {
    id: lim
    property var win: ({})
    property bool stale: false
    property string resetText: win.resetsAt ? "resets in " + AiUsage.until(win.resetsAt) : ""

    readonly property real pct: typeof win.percent === "number" ? win.percent : 0

    Layout.fillWidth: true
    spacing: 5
    opacity: stale ? 0.5 : 1

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Label { text: lim.win.title || ""; font.pixelSize: 12 }
        Label { text: lim.win.detail || ""; color: Theme.fgDim; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
        Label { text: lim.resetText; color: Theme.muted; font.pixelSize: 11 }
        Label {
            text: Math.round(lim.pct) + "%"
            color: Theme.fg
            font.pixelSize: 12; font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 38
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 6
        radius: Math.min(3, Theme.rounding)
        color: Theme.alpha(Theme.fg, 0.14)
        Rectangle {
            width: Math.max(0, Math.min(1, lim.pct / 100)) * parent.width
            height: parent.height
            radius: parent.radius
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }
}
