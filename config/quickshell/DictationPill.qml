import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Push-to-talk dictation pill: a glass card where Settings > Voice > Pill puts it (DictationPrefs pill_edge / pill_gap / pill_x /
// pill_screen through PillPlacement, shared with DiacPill and the Settings preview; default: centred, 2 x popupGap past the bar
// of the focused monitor), never closer than edgeGap to the screen sides.
// Never takes input or keyboard focus (overlay layer, empty mask, keyboardFocus None), so typing always goes to the focused window.
// Look = DictationPillCard (the swoosh with the mode letters, one caption line that grows the card away from its edge; on the
// bottom edge the caption sits above the swoosh). Error: a flat red dotted line and ONE generic line ("An error occurred"), no
// mode; the detail goes to DictationStatus (the persisted last-error record the Voice settings page shows), never onto the
// pill. The caption grows the card (see DictationPillCard, pill_preview_lines).
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
//                shown state while SttModels.statusFor(modelMode) is set (no usable model) becomes that error, code "no-model".
//   mirrored     bottom edge only (default on): caption ABOVE the swoosh, so the swoosh stays beside the edge and never
//                moves when the caption opens; false = the top layout growing upwards (override for tests)
// Test hook (manual): qs ipc call dictation-pill start cs | hide | state <s> | mode <m> | level <0-100> | levels <csv> |
//   caption <text> | error <text> | demo true|false (synthetic levels) | screen <connector> | mirror true|false | status
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: pill

    property string state: "hidden"
    property string mode: "cs"
    property string modelMode: "cs"           // which model pair the service uses for this session: "en" | "cs" | "translate" (SttModels.modeKeyOf(service mode)); not the shown mode, which auto-detection changes
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
        if (!engaged) { screen = place.pick(); engaged = true }
        // no usable speech model: an error instead of recording (the reason, e.g. SttModels.missingMessage, goes to DictationStatus)
        if (state !== "error" && SttModels.statusFor(pill.modelMode) !== "") {
            if (sameShowing && look === "error" && errorCode === "no-model") { keepRecord = true; state = "error"; keepRecord = false; return }   // shown this time already
            errorCode = "no-model"; errorText = SttModels.statusFor(pill.modelMode); state = "error"; return
        }
        look = state
        shownCaption = captionText
        if (state === "error" && errorText !== "" && !keepRecord) DictationStatus.record(errorText, errorCode)
    }
    property bool keepRecord: false           // the no-model error is shown again: not a new error
    onCaptionTextChanged: if (state !== "hidden") shownCaption = captionText
    onErrorTextChanged: if (state === "error" && errorText !== "") DictationStatus.record(errorText, errorCode)

    // ---- geometry (Theme tokens; the width is this card's own content cap) ----
    readonly property int pillW: card.placeW  // the window's width: the card's, plus the room to widen while the text grows
    PillPlacement { id: place; screen: pill.screen; prefs: DictationPrefs; pillW: card.placeW }   // where the card sits (shared with DiacPill)
    readonly property string screenName: place.screenName
    readonly property bool atTop: place.atTop
    readonly property real edgeInset: place.edgeInset
    readonly property bool flip: mirrored && !atTop

    screen: Quickshell.screens[0]
    visible: Theme.glass ? motion.shown : open
    // after a finished close: forget the texts while nothing is drawn, so the next open starts from the bare swoosh
    OpenMotion {
        id: motion
        open: pill.open
        delay: 40
        onClosed: if (!pill.open) { pill.engaged = false; pill.shownCaption = "" }
    }
    anchors { top: atTop; bottom: !atTop; left: true }
    // qmllint disable missing-property
    margins.top: atTop ? edgeInset : 0
    margins.bottom: atTop ? 0 : edgeInset
    margins.left: place.margin
    // qmllint enable missing-property
    implicitWidth: place.screenW > 0 ? place.cardW : pillW
    implicitHeight: Math.ceil(card.fullH)     // room for the grown card: the surface never resizes while it animates
    color: "transparent"
    BarZone { id: zone; screen: pill.screen }
    exclusiveZone: zone.zone
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dictation"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: pill.contentItem; active: pill.visible; itemsOnly: true }   // only the card: the surface is taller (room to grow)
    mask: Region {}                           // never takes input

    DictationPillCard {
        id: card
        openMotion: motion
        fromTop: pill.atTop
        slotW: parent.width
        slotAlign: DictationPrefs.pillX
        previewLines: DictationPrefs.pillPreviewLines
        maxH: place.maxH
        y: pill.atTop ? 0 : parent.height - height     // hangs off its edge, grows away from it
        look: pill.look
        mode: pill.mode
        caption: pill.shownCaption
        level: pill.level
        levels: pill.levels
        running: pill.visible
        flip: pill.flip
        errorLine: pill.errorLine
    }

    // synthetic levels for manual tests (`demo true`)
    SpeechDemoLevel {
        id: demoTimer
        talking: pill.state === "speaking" || pill.state === "translating"
        onLevelChanged: if (running) pill.level = level
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
                + " left=" + place.left + " margin=" + place.margin + " reserved=" + JSON.stringify(place.reserved) + " card=" + card.width + "x" + Math.round(card.height) + " swoosh=" + card.swoosh.width + "x" + card.swoosh.height
                + " caption=" + card.tail.width + "x" + card.tail.height + " lines=" + card.tail.lineCount + "/" + card.maxLines + " overflow=" + card.tail.overflows + " glass=" + Theme.glass
        }
    }
}
