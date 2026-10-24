import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Keybind-opened modal menu (screenshot / recording mode pickers): fullscreen transparent overlay on the focused monitor
// (layer namespace "qs-<kind>", exclusive keyboard), a centred near-opaque card with an icon + title + close
// header, then the children you add, stacked with 14 px spacing. Registers with Popups (one click-away thing at
// a time; another one opening, or a click on another monitor, closes it). Esc / click outside / X close.
// The user handles keys in onKeyPressed (set ev.accepted) and resets its state in onOpening.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: win

    property string kind: ""                       // Popups kind and the layer namespace suffix
    property string title: ""
    property string titleSub: ""                   // small dim text after the title (optional)
    property string icon: ""
    property color iconColor: Theme.accent
    property string iconFamily: Theme.iconFont    // Theme.brandFont for a brand logo
    property Item focusItem: null                  // gets keyboard focus on open (e.g. a search field); null = onKeyPressed
    property int cardWidth: 520
    property bool shown: false
    property var fixedScreen: null                 // opt-in: always open on this screen instead of the focused one
    property bool respectReserved: false           // opt-in: lay out in the usable area (bar strip, monitor reserved_area) instead of the full monitor
    // opt-in card motion with the bar popup tokens (Theme.popup*: Settings -> Animations speed / curve / style):
    // open / close fade + scale + slide from above, height glides. false = no motion of its own (only Hyprland's
    // layer animation), exactly as before.
    property bool animated: false
    // open progress 0..1; without `animated` it jumps (1 while shown)
    property real t: 0
    // explicit open / close animations from the current t, same as PopupHost.qml (a Behavior whose easing is bound
    // to `shown` still had the open easing when a close started: Back closed early and was cut off)
    NumberAnimation { id: openAnim; target: win; property: "t"; to: 1; easing.type: Theme.popupEaseOpen }
    NumberAnimation { id: closeAnim; target: win; property: "t"; to: 0; easing.type: Theme.popupEaseClose }
    readonly property bool moving: animated && (openAnim.running || closeAnim.running || opener.running || (t > 0 && t < 1))
    onShownChanged: {
        if (!shown) {
            opener.stop(); openAnim.stop(); closeAnim.stop()
            if (!animated || t <= 0) { t = 0; return }
            closeAnim.duration = Math.round(Theme.popupCloseMs * Math.min(1, t))
            closeAnim.start()
        } else if (animated) {
            closeAnim.stop()
            if (t > 0) startOpen(); else opener.restart()   // cold: let the layer surface map first (as PopupHost)
        } else t = 1
    }
    function startOpen() {
        openAnim.stop()
        openAnim.duration = Math.round(Theme.popupOpenMs * Math.max(0, Math.min(1, 1 - t)))
        openAnim.start()
    }
    Timer { id: opener; interval: 40; onTriggered: if (win.shown) win.startOpen() }
    readonly property alias card: cardBox
    default property alias content: body.data

    signal opening()                               // just before it shows (screen already chosen)
    signal keyPressed(var event)

    function open() {
        if (shown) return
        screen = fixedScreen || Popups.focusedScreen()
        opening()
        shown = true
        const f = win.focusItem || keys
        f.forceActiveFocus()
    }
    function close() { shown = false }
    function toggle() {
        if (shown && fixedScreen && screen !== fixedScreen) {   // open on another screen: move it instead of closing
            screen = fixedScreen
            Qt.callLater(() => (win.focusItem || keys).forceActiveFocus())
            return
        }
        shown ? close() : open()
    }

    visible: shown || (animated && (t > 0 || closeAnim.running))
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"                           // no dim backdrop; the window still catches click-outside
    exclusiveZone: respectReserved ? 0 : -1        // 0 = Normal: the compositor lays the surface out inside the other surfaces' zones and the reserved area
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-" + kind
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: win.contentItem; active: visible }

    PopupRegistration { kind: win.kind; open: win.shown; screenName: win.screen ? win.screen.name : ""; onDismissed: win.close() }   // qmllint disable missing-property

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => win.keyPressed(ev)
    }
    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: cardBox
        readonly property bool isGlassItem: true
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, win.cardWidth)
        height: body.implicitHeight + 40
        Behavior on height { enabled: win.animated && win.shown && win.t >= 1; NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
        opacity: win.animated ? Math.max(0, Math.min(1, win.t)) : 1
        readonly property real glassScale: win.animated ? Theme.glassScaleAt(win.t) : 1   // see PopupHost card
        layer.enabled: win.moving
        transform: [
            Scale {
                origin.x: cardBox.width / 2; origin.y: 0
                xScale: win.animated ? Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * win.t : 1
                yScale: xScale
            },
            Translate { y: win.animated ? -(1 - win.t) * Theme.popupSlidePx : 0 }
        ]
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.glass ? 0.3 : 0.85)   // glass behind it (Glass.qml); without solid_glass: blurred by the qs-.* layer rule
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        MouseArea { anchors.fill: parent }   // clicks on the card don't reach the close-scrim

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Icon { text: win.icon; font.family: win.iconFamily; font.pixelSize: 16; color: win.iconColor }
                Label { text: win.title; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { visible: win.titleSub !== ""; text: win.titleSub; font.pixelSize: Theme.fontCaption; color: Theme.fgDim; elide: Text.ElideRight }
                Btn { icon: true; text: ""; inset: 20; onClicked: win.close() }   // 20 px inside the card
            }
        }
    }
}
