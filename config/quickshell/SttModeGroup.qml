import QtQuick
import QtQuick.Layouts

// The two model choices of one mode in SttModelsSection: a small heading (the mode, `info` in its tip), then the Fast
// (live) and the Full (final) model (SttRoleRow). `mode` = "en" | "cs" | "translate" (an entry of SttModels.modes).
ColumnLayout {
    id: grp
    property string mode: "en"
    property string title: ""
    property string info: ""
    property int titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    RowLayout {
        spacing: Theme.gapTight
        Label { objectName: "mode-head-" + grp.mode; text: grp.title; color: Theme.fg; font.pixelSize: Theme.fontSmall; font.bold: true }
        InfoTip { visible: grp.info !== ""; text: grp.info }
    }
    SttRoleRow {
        title: "Fast (live)"; titleWidth: grp.titleWidth; mode: grp.mode; role: "live"
        info: "Feeds the pill preview while you hold the key (nothing is typed yet). A faster model keeps up better."
    }
    SttRoleRow {
        title: "Full (final)"; titleWidth: grp.titleWidth; mode: grp.mode; role: "final"
        info: grp.mode === "translate" ? "The English text after you release the key. Only models that can translate."
                                       : "The corrected text after you release the key."
    }
}
