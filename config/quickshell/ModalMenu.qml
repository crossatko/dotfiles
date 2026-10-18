import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Keybind-opened modal menu (screenshot / recording mode pickers): fullscreen transparent overlay on the focused monitor
// (layer namespace "qs-<kind>", exclusive keyboard), a centred near-opaque card with an icon + title + close
// header, then the children you add, stacked with 14 px spacing. Registers with Popups (one click-away thing at
// a time; another one opening, or a click on another monitor, closes it). Esc / click outside / X close.
// The user handles keys in onKeyPressed (set ev.accepted) and resets its state in onOpening.
PanelWindow {
    id: win

    property string kind: ""                       // Popups kind and the layer namespace suffix
    property string title: ""
    property string icon: ""
    property color iconColor: Theme.accent
    property string iconFamily: Theme.iconFont    // Theme.brandFont for a brand logo
    property Item focusItem: null                  // gets keyboard focus on open (e.g. a search field); null = onKeyPressed
    property int cardWidth: 520
    property bool shown: false
    readonly property alias card: cardBox
    default property alias content: body.data

    signal opening()                               // just before it shows (screen already chosen)
    signal keyPressed(var event)

    function open() {
        if (shown) return
        screen = Popups.focusedScreen()
        opening()
        shown = true
        const f = win.focusItem || keys
        f.forceActiveFocus()
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open() }

    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"                           // no dim backdrop; the window still catches click-outside
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-" + kind
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: contentItem; active: visible }

    PopupRegistration { kind: win.kind; open: win.shown; screenName: win.screen ? win.screen.name : ""; onDismissed: win.close() }

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
                Btn { icon: true; text: ""; inset: 20; onClicked: win.close() }   // 20 px inside the card
            }
        }
    }
}
