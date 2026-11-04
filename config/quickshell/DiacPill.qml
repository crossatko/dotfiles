import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Diacritics pill: the "fix Czech diacritics on a key" feedback, in the dictation pill's place and glass (PillPlacement: a card centred
// past the bar edge of the focused monitor, overlay layer `qs-diacritics`, no input or keyboard focus, so typing always goes to the
// focused window). It only renders what the service reports (DiacClient, subscribed to its socket; the pill never starts the service):
//   loading      the model is starting: a dim, slow neutral loop
//   working      the real words of the text being fixed as dot-matrix letters, swapped word over word, the diacritics flaring in one by
//                one (DiacDots / DiacScene.js); with Settings > Diacritics "show text" off (DiacPillPrefs.showText) the generic neutral loop
//   done / failed / unsupported   the picture lets go, then a dotted check / cross / no-sign draws in
//   idle         the card fades out (it keeps the last look while it does)
// Fixed size (pillW x 64); the dot row is 300 x 50 (78 x 13 dots of 3.85 px), the base letters on the card's centre line.
// Test hook: qs ipc call diacritics-pill status
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: pill

    readonly property string svc: DiacClient.state
    readonly property bool open: svc !== "" && svc !== "idle"
    // what the card shows: the last visible state and text, kept while it fades out
    property string look: "working"
    property string shownText: ""
    property bool engaged: false              // shown since the last finished close: the screen was picked then
    onSvcChanged: {
        if (svc === "" || svc === "idle") return          // (`open` may not have followed yet)
        if (!engaged) { screen = Popups.focusedScreen(); engaged = true }
        const before = look
        look = svc
        if (svc === "working" || svc === "loading") shownText = DiacClient.fixed !== "" ? DiacClient.fixed : DiacClient.text
        if ((svc === "working" || svc === "loading") && !(before === "working" || before === "loading") || !motion.shown) dots.restart()
    }
    // the service sends the text with `working` and the fixed text later: show the newest while it is working
    readonly property string liveText: DiacClient.fixed !== "" ? DiacClient.fixed : DiacClient.text
    onLiveTextChanged: if (open && look !== "unsupported") shownText = liveText

    readonly property bool words: DiacPillPrefs.showText && shownText !== ""

    // ---- geometry (Theme tokens; the sizes are this card's own) ----
    readonly property int pillW: 336
    readonly property int dotsW: 300          // 78 dots
    readonly property int dotsH: 50           // 13 rows; the 7-row base band is rows 3..9, on the card's centre line
    readonly property int rowH: 40            // the dictation pill's swoosh row: the dots are centred on it
    readonly property real cardH: 2 * Theme.pad + rowH
    PillPlacement { id: place; screen: pill.screen }
    readonly property bool atTop: place.atTop

    screen: Quickshell.screens[0]
    visible: Theme.glass ? motion.shown : open
    OpenMotion {
        id: motion
        open: pill.open
        delay: 40
        onClosed: if (!pill.open) { pill.engaged = false; pill.shownText = "" }
    }
    anchors { top: atTop; bottom: !atTop }
    // qmllint disable missing-property
    margins.top: atTop ? place.edgeInset : 0
    margins.bottom: atTop ? 0 : place.edgeInset
    // qmllint enable missing-property
    implicitWidth: Math.min(pillW, place.screenW > 0 ? place.maxWidth : pillW)
    implicitHeight: Math.ceil(cardH)
    color: "transparent"
    BarZone { id: zone; screen: pill.screen }
    exclusiveZone: zone.zone
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-diacritics"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: pill.contentItem; active: pill.visible; itemsOnly: true }
    mask: Region {}                           // never takes input

    MotionCard {
        id: card
        openMotion: motion
        fromTop: pill.atTop
        width: parent.width
        height: pill.cardH
        y: pill.atTop ? 0 : parent.height - height
        clip: true

        DiacDots {
            id: dots
            x: Math.round((card.width - pill.dotsW) / 2)
            y: Math.round((card.height - pill.dotsH) / 2)
            width: pill.dotsW
            height: pill.dotsH
            running: pill.visible
            kind: pill.look === "loading" ? "loading" : pill.words ? "words" : "neutral"
            phase: pill.look === "loading" ? "working" : pill.look
            text: pill.words ? pill.shownText : ""
        }
    }

    IpcHandler {
        target: "diacritics-pill"
        function status(): string {
            return "svc=" + pill.svc + " look=" + pill.look + " open=" + pill.open + " words=" + pill.words + " text=" + pill.shownText.length
                + " screen=" + place.screenName + " edge=" + (pill.atTop ? "top" : "bottom") + " inset=" + place.edgeInset
                + " window=" + pill.width + "x" + pill.height + " dots=" + dots.width + "x" + dots.height + " glass=" + Theme.glass
        }
    }
}
