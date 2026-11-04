import QtQuick
import QtQuick.Layouts

// Settings > Diacritics > Key: the one press-to-run key that fixes the text (DiacriticsPrefs, applied to Hyprland at
// once; PttKeyRow with the DiacriticsPrefs store: type or press a key, conflicts checked before it is applied).
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Key"
        detail: DiacriticsPrefs.overridden("key") ? "changed" : ""
        InfoTip { text: "Press it once: the selected text is fixed, or the whole field when nothing is selected. Type a key such as SUPER + SHIFT + D or mouse:276, or press it in the field. Keys Hyprland already uses never reach the field: type those. Saved in diacritics.json next to the other shell settings." }
    }
    PttKeyRow { entry: DiacriticsPrefs.entry; store: DiacriticsPrefs; held: false; titleWidth: sec.titleWidth }
}
