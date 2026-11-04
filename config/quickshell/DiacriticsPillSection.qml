import QtQuick
import QtQuick.Layouts

// Settings > Diacritics > Pill: whether the pill shows the real words being fixed or a generic animation (privacy).
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead { title: "Pill" }
    PrefSwitch {
        title: "Text"; titleWidth: sec.titleWidth
        store: DiacriticsPrefs; key: "show_text"
        hint: "Show the text in the pill"
        info: "On = the pill shows the real words while they are fixed. Off = a generic animation, so nobody looking at the screen can read your text."
    }
}
