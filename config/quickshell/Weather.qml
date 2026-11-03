pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather (weather chip + WeatherPanel). All the work happens in bin/weather (Python): Open-Meteo forecast (current,
// hourly, daily), location from IP geolocation (cached) or the override below, last good answer cached (up to 24 h) so
// offline shows stale values. Polled
// every 15 min while the chip is shown or the popup is open, never otherwise. QS_WEATHER_HELPER overrides the script
// (tests; the helper itself takes QS_WEATHER_CACHE / QS_WEATHER_MOCK).
// Settings live in ${XDG_STATE_HOME:-~/.local/state}/quickshell/weather.json (QS_WEATHER_FILE overrides), this singleton is
// the only writer:
//   { "version": 1, "location": "", "units": "metric", "blur": false, "coldC": 0, "hotC": 28 }
//   location  "" = automatic (IP), a place name, or "lat,lon"     units  "metric" (°C, km/h) | "imperial" (°F, mph)
//   blur      Weather blur (WeatherBlur.qml): the weather picks the compositor blur variant. Off by default; while on the
//             helper also fetches the geomagnetic Kp (aurora) and the weather is polled even without the chip.
//   coldC / hotC   the thresholds (°C, always stored in Celsius; the page shows the user's units and steps 1 degree in
//             them) of the cold -> frost and hot -> heat shimmer blur rules, cold < hot always. Missing keys = the defaults.
// The object doubles as the prefs store of PrefSlider / PrefSwitch (value / set / unset / overridden / defaults / spec);
// `changed` / `resetAll()` cover every key (Settings > Weather's PageReset). The blur prefs stay here, not in
// WeatherBlur: this singleton is weather.json's only writer and the switch also drives the polling and --kp.
// `blurState()` is the payload WeatherBlur writes for the compositor.
//   qs ipc call weather get | refresh | units <metric|imperial> | location <place or lat,lon> | auto | blur <on|off>
//                       | thresholds <coldC> <hotC>
Singleton {
    id: wx

    readonly property string script: Quickshell.env("QS_WEATHER_HELPER") || (Quickshell.shellDir + "/bin/weather")
    readonly property string filePath: {
        const env = Quickshell.env("QS_WEATHER_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/quickshell/weather.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    property string location: defaults.location     // "" = automatic
    property string units: defaults.units
    property bool blur: defaults.blur
    property real coldC: defaults.coldC
    property real hotC: defaults.hotC

    // ---- prefs store interface (SettingsWeather: Weather blur switch, threshold sliders, PageReset) ----
    // thresholds: same defaults / ranges / gap as blurweather.lua (tests/blurweather_test.lua checks they match)
    readonly property var defaults: ({ location: "", units: "metric", blur: false, coldC: 0, hotC: 28 })
    readonly property var spec: ({ coldC: [-40, 25, 0], hotC: [0, 50, 0] })  // [min, max, decimals], °C
    readonly property real minGapC: 1                                        // cold is always this far below hot
    readonly property var keys: ["location", "units", "blur", "coldC", "hotC"]
    function value(key) { return key === "location" ? location : key === "units" ? units : key === "blur" ? blur : key === "coldC" ? coldC : key === "hotC" ? hotC : undefined }
    function overridden(key) { return value(key) !== defaults[key] }
    function unset(key) { set(key, defaults[key]) }
    readonly property bool changed: keys.some(k => overridden(k))
    // the thresholds reset together: one at a time the first would clamp against the other's current value
    function resetAll() {
        for (const k of keys) if (k !== "coldC" && k !== "hotC") unset(k)
        setThresholds(defaults.coldC, defaults.hotC)
    }
    // a threshold is clamped to its slider range, snapped to a whole degree in the user's units and never crosses the
    // other one (cold <= hot - gap): the edited one stops
    function set(key, v) {
        if (key === "location") setLocation(v)
        else if (key === "units") setUnits(v)
        else if (key === "blur") {
            if (blur !== !!v) { blur = !!v; save(); if (blur) refresh(false) }   // the helper adds the Kp to a cached answer
        } else if (key === "coldC" || key === "hotC") {
            const x = clampC(key, snapC(key, Number(v)))
            if (isNaN(x)) return
            if (key === "coldC") coldC = Math.min(x, hotC - minGapC)
            else hotC = Math.max(x, coldC + minGapC)
            save()
        }
    }
    // both thresholds at once (IPC): out of order, the hot one wins (as blurweather.lua thresholds())
    function setThresholds(cold, hot) {
        const p = ordered(clampC("coldC", snapC("coldC", Number(cold))), clampC("hotC", snapC("hotC", Number(hot))))
        if (isNaN(p.c) || isNaN(p.h)) return false
        coldC = p.c; hotC = p.h
        save()
        return true
    }
    // °C -> its slider range (4 decimals: a whole °F is a fraction of a °C), NaN stays NaN
    function clampC(key, c) { return Math.round(Math.max(spec[key][0], Math.min(spec[key][1], c)) * 1e4) / 1e4 }
    function ordered(c, h) { return { c: Math.min(c, h - minGapC), h: h } }
    // the thresholds shown in the user's units; a slider step = one degree there
    function toUnits(c) { return units === "imperial" ? c * 9 / 5 + 32 : c }
    function fromUnits(d) { return units === "imperial" ? (d - 32) * 5 / 9 : d }
    // the nearest whole display degree; within half a step of the default = the default itself (82.4 °F stays 28 °C)
    function snapC(key, c) { return Math.abs(c - defaults[key]) < stepC / 2 ? defaults[key] : fromUnits(Math.round(toUnits(c))) }
    readonly property real stepC: fromUnits(1) - fromUnits(0)           // one display degree in °C

    property var data: null                  // the helper's last answer
    property bool loaded: false
    readonly property bool loading: proc.running
    property string error: ""                // helper failed / printed garbage
    readonly property bool ok: data !== null && data.ok === true
    readonly property bool stale: ok && data.stale === true
    readonly property string problem: error !== "" ? error : data !== null && data.error ? String(data.error) : ""
    readonly property var current: ok ? data.current : null
    readonly property var daily: ok ? data.daily : []
    readonly property string place: ok ? String(data.location.name || "") : ""
    readonly property var hourly: ok ? data.hourly : []
    readonly property var today: daily.find(d => d.rel === 0) ?? null    // a stale answer may no longer have today
    readonly property real fetchedAt: ok ? data.generatedAt : 0          // epoch seconds
    // unit labels come from the helper's answer (the single source), empty while there is none
    readonly property string tempUnit: ok ? String(data.unitsLabel.temp) : ""
    readonly property string windUnit: ok ? String(data.unitsLabel.wind) : ""
    // a "lat,lon" override: its numbers are never shown (the helper names it "Custom location")
    readonly property bool coordsOverride: /^\s*-?\d+(\.\d+)?\s*[,;\s]\s*-?\d+(\.\d+)?\s*$/.test(location)

    // timers (ms)
    readonly property int startDelayMs: 6000      // first fetch after login, not in the startup rush
    readonly property int pollMs: 900000          // 15 min
    readonly property int retryMs: 120000         // while there is no data or only stale data

    readonly property bool panelOpen: Popups.name === "weather"
    readonly property bool chipShown: BarWidgets.shown("weather")
    readonly property bool wanted: panelOpen || chipShown || blur
    // geomagnetic activity strong enough for aurora here (helper's aurora block, only fetched while Weather blur is on)
    readonly property bool auroraLikely: ok && data.aurora !== undefined && data.aurora.likely === true

    function temp(v) { return typeof v === "number" ? Math.round(v) + "°" : "–" }
    function tempFull(v) { return typeof v === "number" ? Math.round(v) + tempUnit : "–" }
    // the state WeatherBlur writes for the compositor (weather-blur.json); `usable` false = "enabled": false
    function blurState(usable) {
        const at = Math.floor(Date.now() / 1000)
        const c = current
        if (!usable || !c) return { version: 1, enabled: false, at: at }
        return {
            version: 1, enabled: true, at: at, kind: String(c.kind || ""),
            tempC: typeof c.tempC === "number" ? c.tempC : null, isDay: c.isDay === true,
            aurora: auroraLikely, coldC: coldC, hotC: hotC
        }
    }
    // "5 min ago" / "3 h ago" for the age of the data
    function ageText() {
        const m = Math.max(0, Math.round((Date.now() / 1000 - fetchedAt) / 60))
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : Math.round(m / 60) + " h ago"
    }

    property bool _again: false
    property string _runUnits: ""        // what the running helper was started with
    property string _runLocation: ""
    function refresh(force) {
        if (proc.running) { if (force) _again = true; return }
        _runUnits = units
        _runLocation = location
        proc.command = ["python3", "-I", script, "--units", units, "--location", location].concat(force ? ["--force"] : []).concat(blur ? ["--kp"] : [])
        proc.running = true
    }

    function setUnits(u) {
        if (u !== "metric" && u !== "imperial") return false
        if (u !== units) { units = u; save(); refresh(false) }      // the helper converts its cached answer: keep the old one until it replies
        return true
    }
    function setLocation(text) {
        const t = String(text).trim()
        if (t !== location) { location = t; data = null; save(); refresh(true) }
    }

    function save() { Quickshell.execDetached(["mkdir", "-p", dir]); saver.restart() }
    // mkdir runs detached: give it a moment before the write
    Timer {
        id: saver
        interval: 300
        onTriggered: fileView.setText(JSON.stringify({ version: 1, location: wx.location, units: wx.units, blur: wx.blur, coldC: wx.coldC, hotC: wx.hotC }) + "\n")
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                // units / location changed while it ran: its answer is for the old ones, drop it and run again
                if (wx._runUnits !== wx.units || wx._runLocation !== wx.location) {
                    wx._again = true
                    if (!proc.running) { wx._again = false; wx.refresh(true) }
                    return
                }
                try {
                    const d = JSON.parse(text)
                    if (typeof d !== "object" || d === null) throw new Error("bad")
                    wx.data = d      // a failed answer already carries the last good values (stale) when there are any
                    wx.error = ""
                } catch (e) {
                    wx.error = "weather helper failed"
                }
                wx.loaded = true
            }
        }
        onExited: if (wx._again) { wx._again = false; wx.refresh(true) }
    }

    Component.onCompleted: { fileView.text(); if (chipShown || blur) starter.start() }
    FileView {
        id: fileView
        path: wx.filePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (typeof d.location === "string") wx.location = d.location
                if (d.units === "metric" || d.units === "imperial") wx.units = d.units
                if (typeof d.blur === "boolean") wx.blur = d.blur
                // missing / garbage keys keep the defaults; the pair is put in order like setThresholds() does
                const num = (k) => typeof d[k] === "number" && isFinite(d[k]) ? wx.clampC(k, d[k]) : wx.defaults[k]
                const p = wx.ordered(num("coldC"), num("hotC"))
                wx.coldC = p.c; wx.hotC = p.h
            } catch (e) {}
        }
    }

    onPanelOpenChanged: if (panelOpen) refresh(false)        // the helper reuses an answer younger than 10 min
    onChipShownChanged: if (chipShown) refresh(false)
    Timer { id: starter; interval: wx.startDelayMs; onTriggered: wx.refresh(false) }
    Timer { interval: wx.pollMs; repeat: true; running: wx.wanted; onTriggered: wx.refresh(false) }
    // no network yet right after login (or a blip): sooner retries until there is fresh data
    Timer { interval: wx.retryMs; repeat: true; running: wx.wanted && (!wx.ok || wx.stale); onTriggered: wx.refresh(false) }

    IpcHandler {
        target: "weather"
        function get(): string { return JSON.stringify({ location: wx.coordsOverride ? "custom" : wx.location, units: wx.units, ok: wx.ok, stale: wx.stale, error: wx.problem, place: wx.place, temp: wx.current ? wx.current.temp : null, kind: wx.current ? wx.current.kind : "", blur: wx.blur, aurora: wx.auroraLikely }) }
        function refresh(): void { wx.refresh(true) }
        function units(u: string): string { return wx.setUnits(u) ? "ok" : "bad units (metric|imperial)" }
        function location(text: string): void { wx.setLocation(text) }
        function auto(): void { wx.setLocation("") }
        function blur(state: string): string { if (state === "on" || state === "off") { wx.set("blur", state === "on"); return "ok" } return "bad state (on|off)" }
        function thresholds(cold: string, hot: string): string { return wx.setThresholds(cold, hot) ? wx.coldC + " " + wx.hotC : "bad thresholds (numbers, °C)" }
    }
}
