import QtQuick
import QtQuick.Layouts

// One forecast day (WeatherPanel): condition glyph, day name with the condition under it, rain chance, low / high.
ListRow {
    id: day
    property string name: ""
    property string condition: ""
    property string kind: ""
    property string rain: ""        // "40%" or ""
    property string low: ""
    property string high: ""

    interactive: false
    icon: Icons.weatherGlyph(kind, true)
    iconColor: Theme.fg

    RowText { title: day.name; sub: day.condition }
    Label { visible: day.rain !== ""; text: day.rain; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
    Label { text: day.low; color: Theme.fgDim; Layout.preferredWidth: lowM.advanceWidth; horizontalAlignment: Text.AlignRight }
    Label { text: day.high; font.bold: true; Layout.preferredWidth: lowM.advanceWidth; horizontalAlignment: Text.AlignRight }
    TextMetrics { id: lowM; font.family: Theme.font; font.pixelSize: Theme.fontSize; text: "-00°" }
}
