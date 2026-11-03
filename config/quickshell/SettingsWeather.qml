pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Weather (the chip / popup itself is shown or hidden under Settings -> Bar). Units (Weather.setUnits, a
// ChoiceRow) and the location: a city name or `lat,lon` typed into the field and applied with Enter or Apply
// (Weather.setLocation), Auto-detect clears the override (IP geolocation again). The Place row shows what the helper
// resolved (Weather.place), "Loading…" while it runs and the helper's error in red (e.g. a city it does not find; the
// field turns red too). A `lat,lon` override leaves the field empty: its numbers are never shown.
// Customise… holds Weather blur (PrefSwitch, off by default: the weather picks the compositor's blur variant,
// WeatherBlur.qml) and the cold / hot thresholds of the frost and heat-shimmer rules (stored in Celsius in weather.json,
// shown and stepped by one degree in the units above; cold stays below hot). PageReset = Weather.resetAll().
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property int fieldW: 160          // the location field: a city name fits
    readonly property int ctrlH: 26            // inline field / button height of a Settings row (as the Lock / Desktop clock pages)
    readonly property int ctrlInset: 9         // their inset from the page card's corner radius
    readonly property bool failed: !Weather.loading && Weather.location !== "" && Weather.problem !== ""
    readonly property int foldChanged: ["blur", "coldC", "hotC"].filter(k => Weather.overridden(k)).length
    function degrees(v) { return Math.round(Weather.toUnits(v)) + (Weather.units === "imperial" ? "°F" : "°C") }
    function apply() { Weather.setLocation(field.text) }
    function sync() { field.text = Weather.coordsOverride ? "" : Weather.location }

    Component.onCompleted: { sync(); Weather.refresh(false) }
    Connections { target: Weather; function onLocationChanged() { pg.sync() } }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.pad

        ChoiceRow {
            objectName: "weather-units"
            title: "Units"; titleWidth: pg.titleW
            values: ["metric", "imperial"]
            labels: ["Metric", "Imperial"]
            objectNames: ["btn-weather-metric", "btn-weather-imperial"]
            current: Weather.units
            info: "°C, km/h or °F, mph"
            onPicked: v => Weather.setUnits(v)
        }

        SettingRow {
            title: "Location"; titleWidth: pg.titleW
            FieldBox {
                id: field
                objectName: "weather-location"
                Layout.preferredWidth: pg.fieldW
                placeholder: "City or lat,lon"
                error: pg.failed
                outerRadius: Theme.radiusPage; inset: pg.ctrlInset
                implicitHeight: pg.ctrlH
                onAccepted: pg.apply()
            }
            Btn {
                objectName: "btn-weather-apply"
                text: "Apply"
                outerRadius: Theme.radiusPage; inset: pg.ctrlInset
                implicitHeight: pg.ctrlH
                enabledLook: field.text.trim() !== (Weather.coordsOverride ? "" : Weather.location)
                onClicked: pg.apply()
            }
            Btn {
                objectName: "btn-weather-auto"
                glyph: Icons.locationDot
                text: "Auto-detect"
                outerRadius: Theme.radiusPage; inset: pg.ctrlInset
                implicitHeight: pg.ctrlH
                enabledLook: Weather.location !== Weather.defaults.location
                onClicked: Weather.unset("location")
            }
            InfoTip { text: "A city name or latitude,longitude. Auto-detect uses your IP address." }
            Item { Layout.fillWidth: true }
        }

        SettingRow {
            title: "Place"; titleWidth: pg.titleW
            Label {
                objectName: "weather-place"
                text: Weather.loading && !Weather.ok ? "Loading…" : pg.failed ? Weather.problem : Weather.place !== "" ? Weather.place : "–"
                color: pg.failed ? Theme.red : Theme.fgDim
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        AdvancedFold {
            objectName: "fold-weather-blur"
            detail: pg.foldChanged > 0 ? pg.foldChanged + " changed" : ""
            PrefSwitch {
                objectName: "weather-blur"
                title: "Weather blur"; titleWidth: pg.titleW
                store: Weather; key: "blur"
                info: "The weather picks the window blur: rain and storms drops, snow and cold frost, heat a shimmer, fog and overcast haze, clear nights aurora (also on a partly cloudy night with strong geomagnetic activity for your latitude), otherwise solid glass (kawase without it). Your choice under Look & feel > Blur is never changed and applies again when this is off. Drops, heat shimmer and aurora cost GPU while they animate. Needs a Hyprland with the blur variants (0.57+)."
            }
            PrefSlider {
                title: "Cold at or below"; titleWidth: pg.titleW
                store: Weather; key: "coldC"
                unitStep: Weather.stepC
                format: v => pg.degrees(v)
            }
            PrefSlider {
                title: "Hot at or above"; titleWidth: pg.titleW
                store: Weather; key: "hotC"
                unitStep: Weather.stepC
                format: v => pg.degrees(v)
            }
        }

        PageReset {
            objectName_: "btn-weather-reset"
            dirty: Weather.changed
            info: "Saved in weather.json."
            onReset: Weather.resetAll()
        }
    }
}
