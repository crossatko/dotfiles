import QtQuick

// A big numeral (the reminder's time left / minutes): bold, tight letter spacing; Paper Mono digits keep their width,
// so a countdown does not wobble. `compact` = the notification card's size, else the popup's.
Label {
    id: digits
    property bool compact: false
    readonly property int heroPx: Theme.fontLead * 5      // 75: the popup's numeral
    readonly property int cardPx: Theme.fontLead * 4      // 60: the notification card's numeral
    readonly property real tracking: -0.05                // letter spacing, in ems

    readonly property int px: compact ? cardPx : heroPx

    font.pixelSize: px
    font.bold: true
    font.letterSpacing: tracking * px
}
