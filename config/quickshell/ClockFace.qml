import QtQuick
import Quickshell

// What the glass clocks show and how fast their digits change (LockClock, DeskClockView): `text` = HH:mm, or
// HH:mm:ss with `seconds` (12-hour: h:mm[:ss], no AM / PM), `dateText`, and `morphMs` for each GlassText: the default
// morph (popup motion tokens, Settings > Animations speed; none = instant) x `morphTime` (Settings, 0 = plain swap),
// capped at 45 % of a second while seconds show, so a morph ends before the next tick. The clock ticks only as often as
// it shows (minutes or seconds); a tick changes only the characters that differ, each its own GlassText.
// `testEnv` = a test hook's value (QS_LOCK_CLOCK / QS_DESKCLOCK_CLOCK): a fixed text, or several separated by spaces,
// cycled every 3 s. `demo()` (Settings preview): the shown time steps one minute ahead and back, so the morph shows.
// `fitSize(base, maxWidth)` = the digit size at which the clock fits `maxWidth` (never above `base`). `active` false
// (a lock screen without the clock) stops the ticking.
QtObject {
    id: f
    property bool h24: true
    property bool seconds: false
    property real morphTime: 1
    property string testEnv: ""
    property bool active: true

    readonly property var testTimes: String(testEnv || "").split(" ").filter(t => t !== "")
    property int testIdx: 0
    property Timer testTimer: Timer {
        running: f.testTimes.length > 1; interval: 3000; repeat: true
        onTriggered: f.testIdx = (f.testIdx + 1) % f.testTimes.length
    }
    property SystemClock clock: SystemClock { enabled: f.active; precision: f.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    property int demoOffset: 0         // s
    function demo() { demoOffset = 60; demoBack.restart() }
    property Timer demoBack: Timer { interval: Math.max(1400, f.morphMs + 1000); onTriggered: f.demoOffset = 0 }

    readonly property date shown: demoOffset === 0 ? clock.date : new Date(clock.date.getTime() + demoOffset * 1000)
    readonly property string text: testTimes.length > 0 ? testTimes[testIdx]
        : h24 ? Qt.formatDateTime(shown, seconds ? "HH:mm:ss" : "HH:mm")
        : Qt.formatDateTime(shown, seconds ? "h:mm:ss AP" : "h:mm AP").replace(/\s*[AP]M$/i, "")   // "h" alone is 24 h in Qt
    readonly property string dateText: Qt.formatDateTime(clock.date, "dddd, d MMMM")

    readonly property int morphMs: morphTime <= 0 ? 0 : Math.min(seconds ? 450 : 100000, Theme.popupMs(Motion.baseMs * 3 * morphTime))

    // width of the glyph row per px of digit size (monospace advance per character + the rows' 0.03 spacing)
    property FontMetrics metrics: FontMetrics { font.family: Theme.font; font.pixelSize: 100; font.weight: Font.ExtraBold }
    readonly property real rowPerPx: text.length * metrics.advanceWidth("0") / 100 + Math.max(0, text.length - 1) * 0.03
    function fitSize(base, maxWidth) {
        if (!(rowPerPx > 0) || !(maxWidth > 0)) return base
        return Math.max(8, Math.min(base, Math.floor(maxWidth / rowPerPx / 1.02)))
    }
}
