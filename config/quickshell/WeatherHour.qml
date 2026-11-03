import QtQuick
import QtQuick.Layouts

// One hour of the strip in WeatherPanel: time, condition glyph, temperature and a rain chance line (blank when low; the whole line is dropped when no hour has one),
// each centred in the column; the strip sets the column width (the same for every hour).
ColumnLayout {
    id: hr
    property string time: ""
    property string kind: ""
    property bool isDay: true
    property string temp: ""
    property string rain: ""        // "40%" or ""
    property bool showRain: true    // the strip has a rain line at all (none: no empty row under the temperatures)

    spacing: Theme.gapTight

    Label { text: hr.time; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    Icon { text: Icons.weatherGlyph(hr.kind, hr.isDay); font.pixelSize: Theme.iconLg; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    Label { text: hr.temp; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    Label { visible: hr.showRain; text: hr.rain; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
}
