pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Weather popup (weather chip): current conditions, a few facts, the next hours and the next days. Data: Weather.qml -> bin/weather.
ColumnLayout {
    id: wp
    spacing: Theme.pad      // between blocks; a section's head -> body is gapRow, its list items gapTight

    readonly property var cur: Weather.current
    readonly property bool failed: Weather.loaded && !Weather.ok
    readonly property int heroIcon: Theme.iconXl * 2   // the card's one big condition glyph, twice the OSD glyph size
    readonly property var later: Weather.daily.filter(d => d.rel !== 0)   // today is in the hero card
    readonly property int rainShowPct: 20      // a precipitation chance below this is not shown
    // every hour column is as wide as its widest possible line, so "Now" and "23:00" share one centre line; the strip
    // spreads the columns from the card's left padding to its right one (space-between)
    readonly property real hourW: Math.max(hourTimeM.advanceWidth, hourTempM.advanceWidth, Theme.iconLg)

    TextMetrics { id: hourTimeM; font.family: Theme.font; font.pixelSize: Theme.fontCaption; text: "00:00" }
    TextMetrics { id: hourTempM; font.family: Theme.font; font.pixelSize: Theme.fontSmall; font.bold: true; text: "-00°" }

    function dayName(rel, date) {
        if (rel === 0) return "Today"
        if (rel === 1) return "Tomorrow"
        const d = new Date(date + "T12:00:00")
        return isNaN(d.getTime()) ? date : Qt.locale().dayName(d.getDay(), Locale.LongFormat)
    }
    function rainText(pop) {
        return typeof pop === "number" && pop >= rainShowPct ? Math.round(pop) + "%" : ""
    }
    function windText(c) {
        return typeof c.wind === "number" ? Math.round(c.wind) + " " + Weather.windUnit : "–"
    }

    PanelHeader {
        title: Weather.place || "Weather"
        showStatus: Weather.stale || (Weather.loading && !Weather.loaded)
        status: Weather.stale ? "Offline, " + Weather.ageText() : "Loading…"
        statusColor: Weather.stale ? Theme.orange : Theme.fgDim
        Btn {
            icon: true
            text: Icons.retry
            tip: "Refresh"
            active: Weather.loading
            onClicked: Weather.refresh(true)
        }
    }

    EmptyState {
        visible: wp.failed
        icon: Icons.weatherOff
        text: "No weather data"
        hint: Weather.problem
    }

    Notice {
        visible: wp.cur !== null
        spacing: Theme.padSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.pad
            Icon { text: wp.cur ? Icons.weatherGlyph(wp.cur.kind, wp.cur.isDay) : ""; font.pixelSize: wp.heroIcon; color: Theme.fg }   // information, not a state: plain ink
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: wp.cur ? Weather.tempFull(wp.cur.temp) : ""; font.pixelSize: Theme.fontTitle; font.bold: true }
                Label { text: wp.cur ? wp.cur.text : ""; color: Theme.fgDim; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            ColumnLayout {
                visible: Weather.today !== null
                spacing: 0
                Label { text: "High " + Weather.temp(Weather.today?.max); font.pixelSize: Theme.fontSmall; Layout.alignment: Qt.AlignRight }
                Label { text: "Low " + Weather.temp(Weather.today?.min); color: Theme.fgDim; font.pixelSize: Theme.fontSmall; Layout.alignment: Qt.AlignRight }
            }
        }
        // space-between: the first fact starts at the card's left padding, the last ends at its right one (under High / Low)
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            WeatherStat { icon: Icons.thermometer; text: wp.cur ? Weather.temp(wp.cur.feels) : ""; tip: "Feels like" }
            Item { Layout.fillWidth: true }
            WeatherStat { icon: Icons.humidity; text: wp.cur && typeof wp.cur.humidity === "number" ? Math.round(wp.cur.humidity) + "%" : "–"; tip: "Humidity" }
            Item { Layout.fillWidth: true }
            WeatherStat { icon: Icons.wind; text: wp.cur ? wp.windText(wp.cur) : ""; tip: "Wind" }
        }
    }

    ColumnLayout {
        visible: Weather.hourly.length > 0
        Layout.fillWidth: true
        spacing: Theme.gapRow

        SectionHead { title: "Hourly" }
        Notice {
            RowLayout {
                id: hours
                readonly property int n: Weather.hourly.length
                readonly property bool anyRain: Weather.hourly.some(h => wp.rainText(h.pop) !== "")
                Layout.fillWidth: true
                spacing: hours.n > 1 ? Math.max(0, (hours.width - hours.n * wp.hourW) / (hours.n - 1)) : 0
                Repeater {
                    model: Weather.hourly
                    WeatherHour {
                        required property var modelData
                        required property int index
                        Layout.preferredWidth: wp.hourW
                        time: index === 0 && !Weather.stale ? "Now" : modelData.time
                        kind: modelData.kind
                        isDay: modelData.isDay
                        temp: Weather.temp(modelData.temp)
                        rain: wp.rainText(modelData.pop)
                        showRain: hours.anyRain
                    }
                }
            }
        }
    }

    ColumnLayout {
        visible: wp.later.length > 0
        Layout.fillWidth: true
        spacing: Theme.gapRow

        SectionHead { title: "Forecast" }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Repeater {
                model: wp.later
                WeatherDay {
                    required property var modelData
                    Layout.fillWidth: true
                    name: wp.dayName(modelData.rel, modelData.date)
                    condition: modelData.text
                    kind: modelData.kind
                    rain: wp.rainText(modelData.pop)
                    low: Weather.temp(modelData.min)
                    high: Weather.temp(modelData.max)
                }
            }
        }
    }
}
