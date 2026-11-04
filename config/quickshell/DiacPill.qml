import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Diacritics pill: the "fix Czech diacritics on a key" feedback, in the dictation pill's glass, where Settings > Diacritics > Pill puts
// it (DiacriticsPrefs pill_* keys through PillPlacement; default: centred past the bar edge of the focused monitor), overlay layer
// `qs-diacritics`, no input or keyboard focus, so typing always goes to the focused window. It only renders what the service reports (DiacClient, subscribed to its socket; the pill never starts the service):
//   loading      the model is starting: a dim, slow neutral loop
//   working      the real words of the text being fixed as dot-matrix letters, chunk by chunk; the service streams the fixed words as the
//                model writes them and each word's diacritics flare in one by one as it arrives (DiacDots / DiacScene.js, live view; before the
//                first word the chunks loop); with Settings > Diacritics "show text" off (DiacriticsPrefs.showText) the generic neutral loop
//   done         the replay carries on from the chunk on screen (what already flared is not played again; a fixed text that could not be
//                followed live is replayed whole), at most 1.5 s, then the dotted check; failed / unsupported: the picture lets go, then a dotted cross / no-sign draws in
//   idle         the card fades out (it keeps the last look while it does)
// Fixed size (pillW x 64) = DiacPillCard (the card and its dot picture, also the Settings preview).
// Test hook: qs ipc call diacritics-pill status
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: pill

    readonly property string svc: DiacClient.state
    // the service goes idle about 1.2 s after done; the replay and the check take longer (DiacDots.busy), so the card stays for them
    readonly property bool open: (svc !== "" && svc !== "idle") || card.dots.busy
    // what the card shows: the last visible state and text, kept while it fades out
    property string look: "working"
    property string shownText: ""
    property string replayText: ""                // the fixed text of the last done, replayed by DiacDots
    property bool engaged: false              // shown since the last finished close: the screen was picked then
    onSvcChanged: {
        if (svc === "" || svc === "idle") return          // (`open` may not have followed yet)
        if (!engaged) { screen = place.pick(); engaged = true }
        const before = look
        if (svc === "done") replayText = DiacClient.fixed
        else replayText = ""
        look = svc
        if (svc === "working" || svc === "loading") shownText = DiacClient.text
        if ((svc === "working" || svc === "loading") && !(before === "working" || before === "loading") || !motion.shown) card.dots.restart()
    }
    // the service sends the text with `working` (the original is what the card shows) and the fixed text with `done`
    readonly property string liveText: DiacClient.text
    onLiveTextChanged: if (svc === "working" || svc === "loading") shownText = liveText

    // while working the service streams the fixed words finished so far: DiacDots puts them in and flares their marks as they come
    readonly property string livePartial: svc === "working" ? DiacClient.partial : ""

    readonly property bool words: DiacriticsPrefs.showText && shownText !== ""

    // ---- geometry (the width is this card's own) ----
    readonly property int pillW: card.pillW
    PillPlacement { id: place; screen: pill.screen; prefs: DiacriticsPrefs; pillW: pill.pillW }
    readonly property bool atTop: place.atTop

    screen: Quickshell.screens[0]
    visible: Theme.glass ? motion.shown : open
    OpenMotion {
        id: motion
        open: pill.open
        delay: 40
        onClosed: if (!pill.open) { pill.engaged = false; pill.shownText = ""; pill.replayText = "" }
    }
    anchors { top: atTop; bottom: !atTop; left: true }
    // qmllint disable missing-property
    margins.top: atTop ? place.edgeInset : 0
    margins.bottom: atTop ? 0 : place.edgeInset
    margins.left: place.margin
    // qmllint enable missing-property
    implicitWidth: place.screenW > 0 ? place.cardW : pillW
    implicitHeight: Math.ceil(card.cardH)
    color: "transparent"
    BarZone { id: zone; screen: pill.screen }
    exclusiveZone: zone.zone
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-diacritics"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: pill.contentItem; active: pill.visible; itemsOnly: true }
    mask: Region {}                           // never takes input

    DiacPillCard {
        id: card
        openMotion: motion
        fromTop: pill.atTop
        width: parent.width
        y: pill.atTop ? 0 : parent.height - height
        running: pill.visible
        kind: pill.look === "loading" ? "loading" : pill.words ? "words" : "neutral"
        phase: pill.look === "loading" ? "working" : pill.look
        text: pill.words ? pill.shownText : ""
        partial: pill.livePartial
        replayText: pill.replayText
    }

    IpcHandler {
        target: "diacritics-pill"
        function status(): string {
            return "svc=" + pill.svc + " look=" + pill.look + " open=" + pill.open + " words=" + pill.words + " text=" + pill.shownText.length
                + " screen=" + place.screenName + " edge=" + (pill.atTop ? "top" : "bottom") + " inset=" + place.edgeInset
                + " left=" + place.left + " margin=" + place.margin + " reserved=" + JSON.stringify(place.reserved) + " window=" + pill.width + "x" + pill.height + " dots=" + card.dots.width + "x" + card.dots.height + " glass=" + Theme.glass
        }
    }
}
