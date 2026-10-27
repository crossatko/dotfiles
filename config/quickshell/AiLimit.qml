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
    spacing: Theme.controlGap
    opacity: stale ? Theme.disabledOpacity : 1

    TextMetrics { id: pctW; font.family: Theme.font; font.pixelSize: Theme.fontSmall; font.bold: true; text: "100%" }   // widest percent value

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.controlGap
        Label { text: lim.win.title || ""; font.pixelSize: Theme.fontSmall }
        Label { text: lim.win.detail || ""; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight; Layout.fillWidth: true }
        Label { text: lim.resetText; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        Label {
            text: Math.round(lim.pct) + "%"
            color: Theme.fg
            font.pixelSize: Theme.fontSmall; font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Math.ceil(pctW.advanceWidth)
        }
    }
    Meter {
        Layout.fillWidth: true
        value: lim.pct / 100
        fillColor: lim.pct >= 100 ? Theme.red : Theme.accent     // red = the limit is hit
        animMs: Motion.moveMs
    }
}
