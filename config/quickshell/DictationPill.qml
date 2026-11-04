import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Push-to-talk dictation pill: a glass card centred on the bar edge of the focused monitor, edgeGapFactor (2) x popupGap past
// the bar (the bar popups' gap, doubled), or on the bottom edge whatever the bar (DictationPrefs.pillBottom, Settings > Voice;
// with a top bar then edgeGapFactor x edgeGap from the screen edge), never closer than edgeGap to the screen sides.
// Never takes input or keyboard focus (overlay layer, empty mask, keyboardFocus None), so typing always goes to the focused window.
// Look: a full-width dithered swoosh driven by the live mic level (DotSwoosh)
// with the mode as dot letters in the swoosh's own grid ("CS" / "EN" left; translating: "CS" left, "EN" right, colour
// accent -> accent2); beside it (below; above on a bottom bar) ONE caption line with the tail of the text (TailLine)
// that opens when there is text: the pill grows away from the bar (top bar: downwards; bottom bar: upwards, the swoosh
// stays beside the bar). Error: a flat red dotted
// line and ONE generic line ("An error occurred"), no mode; the detail goes to DictationStatus (the persisted last-error
// record the Voice settings page shows), never onto the pill. Fixed width (pillW): text never changes it.
//
// API (set by DictationController; nothing here talks to the service):
//   state        "hidden" | "listening" | "speaking" | "translating" | "error"   (hidden = fade out; shown = fade in on the
//                focused monitor, `screen` is set then)
//   mode         a language code, "auto" (until the service has detected the language), or "cs-en" (source[-target]; "translating"
//                without a target shows "en"); shown as dot letters (any code of two or three letters, A-Z glyphs only)
//   level        0..1 mic level (smoothed here), or `levels`: up to 16 recent values, oldest first
//   captionText  the text so far (the end is shown)
//   errorText / errorCode  the error detail (and an optional short code): recorded in DictationStatus when the state
//                becomes "error" (set them before the state; a new text while in "error" is a new error). Any other
//                shown state while SttModels.statusMessage is set (no usable model) becomes that error, code "no-model".
//   mirrored     bottom bar only (default on): caption ABOVE the swoosh, so the swoosh stays beside the bar and never
//                moves when the caption opens; false = the top-bar layout growing upwards (override for tests)
// Test hook (manual): qs ipc call dictation-pill start cs | hide | state <s> | mode <m> | level <0-100> | levels <csv> |
//   caption <text> | error <text> | demo true|false (synthetic levels) | screen <connector> | mirror true|false | status
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: pill

    property string state: "hidden"
    property string mode: "cs"
    property real level: 0
    property var levels: []
    property string captionText: ""
    property string errorText: ""
    property string errorCode: ""
    property bool mirrored: true              // bottom bar: caption above the swoosh (user decision); false = test override
    readonly property var status: DictationStatus   // created with the pill, so its IPC target exists from the start
    readonly property var models: SttModels        // created with the pill: install state is listed before the first press
    readonly property string errorLine: "An error occurred"

    readonly property bool open: state !== "hidden"
    // what the card shows: the last visible state and texts, kept while it fades out after `hidden`
    property string look: "listening"
    property string shownCaption: ""
    property bool engaged: false              // shown since the last finished close: the screen was picked then
    onStateChanged: {
        if (state === "hidden") { SttModels.refresh(); return }   // fresh install state for the next no-model check
        // (not `open` / `motion.shown` above: those bindings may not have followed yet)
        const sameShowing = engaged
        if (!engaged) { screen = Popups.focusedScreen(); engaged = true }
        // no usable speech model: an error instead of recording (the reason, e.g. SttModels.missingMessage, goes to DictationStatus)
        if (state !== "error" && SttModels.statusMessage !== "") {
            if (sameShowing && look === "error" && errorCode === "no-model") { keepRecord = true; state = "error"; keepRecord = false; return }   // shown this time already
            errorCode = "no-model"; errorText = SttModels.statusMessage; state = "error"; return
        }
        look = state
        shownCaption = captionText
        if (state === "error" && errorText !== "" && !keepRecord) DictationStatus.record(errorText, errorCode)
    }
    property bool keepRecord: false           // the no-model error is shown again: not a new error
    onCaptionTextChanged: if (state !== "hidden") shownCaption = captionText
    onErrorTextChanged: if (state === "error" && errorText !== "") DictationStatus.record(errorText, errorCode)

    readonly property bool isError: look === "error"
    readonly property var langs: String(mode).toLowerCase().split("-")
    readonly property string srcLang: langs[0] || ""
    readonly property string dstLang: langs[1] || (look === "translating" ? "en" : "")
    // Czech and English keep their colours, Auto and every other language one of the palette's, by its code
    // (a colour whose hue is near accent or accent2 would read as Czech or English: left out)
    function hueGap(a, b) { const d = Math.abs(a.hsvHue - b.hsvHue); return Math.min(d, 1 - d) }
    readonly property var langPalette: {
        const all = [Theme.blue, Theme.green, Theme.orange, Theme.cyan, Theme.yellow, Theme.red, Theme.fg]
        const ok = all.filter(c => c.hsvHue < 0 || (hueGap(c, Theme.accent) > 0.07 && hueGap(c, Theme.accent2) > 0.07))
        return ok.length ? ok : [Theme.fg]
    }
    function langColor(code) {
        if (code === "en") return Theme.accent2
        if (code === "cs") return Theme.accent
        if (code === "auto" || code === "") return Theme.fg
        let h = 0
        for (const c of String(code)) h = (h * 31 + c.charCodeAt(0)) % 997
        return langPalette[h % langPalette.length]
    }
    readonly property bool hasText: isError || shownCaption !== ""

    // ---- geometry (Theme tokens; the two sizes below are this card's own content caps) ----
    readonly property int pillW: 336          // fixed card width, shrinks only on a narrow screen
    readonly property int waveH: 40           // the swoosh row
    readonly property int sidePad: Theme.pad + Theme.controlGap   // 18, as the OSD pill
    PillPlacement { id: place; screen: pill.screen }   // where the card hangs (shared with DiacPill)
    readonly property string screenName: place.screenName
    readonly property int screenW: place.screenW > 0 ? place.screenW : pillW
    readonly property bool barAtTop: place.barAtTop
    readonly property bool atTop: place.atTop
    readonly property real edgeInset: place.edgeInset
    readonly property bool flip: mirrored && !atTop
    readonly property real baseH: 2 * Theme.pad + waveH
    readonly property real capH: tail.implicitHeight        // one line, caption or error
    readonly property real fullH: baseH + Theme.gapRow + capH

    screen: Quickshell.screens[0]
    visible: Theme.glass ? motion.shown : open
    // after a finished close: forget the texts while nothing is drawn, so the next open starts from the bare swoosh
    OpenMotion {
        id: motion
        open: pill.open
        delay: 40
        onClosed: if (!pill.open) { pill.engaged = false; pill.shownCaption = "" }
    }
    anchors { top: atTop; bottom: !atTop }
    // qmllint disable missing-property
    margins.top: atTop ? edgeInset : 0
    margins.bottom: atTop ? 0 : edgeInset
    // qmllint enable missing-property
    implicitWidth: Math.min(pillW, place.screenW > 0 ? place.maxWidth : pillW)
    implicitHeight: Math.ceil(fullH)          // room for the grown card: the surface never resizes while it animates
    color: "transparent"
    BarZone { id: zone; screen: pill.screen }
    exclusiveZone: zone.zone
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dictation"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: pill.contentItem; active: pill.visible; itemsOnly: true }   // only the card: the surface is taller (room to grow)
    mask: Region {}                           // never takes input

    // caption row share of the card height: opens / closes with the text (move tokens), instant while hidden
    property real capShare: hasText ? Theme.gapRow + capH : 0
    Behavior on capShare { enabled: motion.shown; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }

    MotionCard {
        id: card
        openMotion: motion
        fromTop: pill.atTop
        width: parent.width
        height: pill.baseH + pill.capShare
        y: pill.atTop ? 0 : parent.height - height     // hangs off the bar edge, grows away from it
        clip: true

        DotSwoosh {
            id: swoosh
            x: pill.sidePad
            y: pill.flip ? card.height - Theme.pad - height : Theme.pad
            width: card.width - 2 * pill.sidePad
            height: pill.waveH
            running: pill.visible
            level: pill.level
            levels: pill.levels
            error: pill.isError
            leftText: pill.srcLang
            rightText: pill.dstLang
            colorLeft: pill.langColor(pill.srcLang)
            colorRight: pill.dstLang !== "" ? pill.langColor(pill.dstLang) : colorLeft
        }

        // the caption / error line, under the swoosh (above it when flipped); fades with its share of the height
        Item {
            id: capRow
            x: pill.sidePad
            width: card.width - 2 * pill.sidePad
            height: pill.capH
            y: pill.flip ? Theme.pad : Theme.pad + pill.waveH + Theme.gapRow
            opacity: pill.hasText ? Math.max(0, Math.min(1, (pill.capShare - Theme.gapRow) / Math.max(1, pill.capH))) : 0
            TailLine {
                id: tail
                anchors.left: parent.left
                anchors.right: parent.right
                visible: !pill.isError
                text: pill.shownCaption
                label.font.pixelSize: Theme.fontLead
                label.font.weight: Font.Medium
            }
            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height
                visible: pill.isError
                text: pill.errorLine
                color: Theme.red
            }
        }
    }

    // synthetic levels for manual tests (`demo true`): a speech-like envelope at ~30 Hz
    Timer {
        id: demoTimer
        interval: 33
        repeat: true
        onTriggered: {
            const t = Date.now() / 1000
            const talking = pill.state === "speaking" || pill.state === "translating"
            const env = (.5 + .5 * Math.sin(t * 2.6)) * (.55 + .45 * Math.sin(t * .8 + 1)) * (.7 + .3 * Math.sin(t * 7.3) * Math.sin(t * 4.1))
            pill.level = talking ? Math.min(1, .1 + env * .95) : 0   // the service sends a true 0 at its noise floor
        }
    }

    IpcHandler {
        target: "dictation-pill"
        function start(mode: string): void { if (mode !== "") pill.mode = mode; pill.state = "listening" }   // (not "show" / "listen": the qs ipc CLI takes those words)
        function hide(): void { pill.state = "hidden" }
        function state(s: string): void { pill.state = s }
        function mode(m: string): void { pill.mode = m }
        function level(percent: int): void { pill.level = percent / 100 }
        function levels(csv: string): void { pill.levels = csv === "" ? [] : csv.split(",").map(v => Number(v) / 100) }
        function caption(text: string): void { pill.captionText = text }
        function error(text: string): void { pill.errorCode = ""; pill.errorText = text; pill.state = "error" }   // detail -> DictationStatus
        function demo(on: bool): void { demoTimer.running = on }
        function screen(name: string): void { const s = Quickshell.screens.find(x => x.name === name); if (s) pill.screen = s }   // qmllint disable missing-property
        function mirror(on: bool): void { pill.mirrored = on }
        function status(): string {
            return "state=" + pill.state + " look=" + pill.look + " mode=" + pill.mode + " screen=" + pill.screenName
                + " edge=" + (pill.atTop ? "top" : "bottom") + " inset=" + pill.edgeInset + " window=" + pill.width + "x" + pill.height
                + " card=" + card.width + "x" + Math.round(card.height) + " swoosh=" + swoosh.width + "x" + swoosh.height
                + " caption=" + tail.width + " overflow=" + tail.overflows + " glass=" + Theme.glass
        }
    }
}
