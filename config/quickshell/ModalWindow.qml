import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Keybind-opened modal menu as a real floating window (screenshot / recording mode pickers): a toplevel with the
// title "qs-<kind>" that is just the card (an icon + heading + close header, then the children you add, stacked
// with 14 px spacing). Hyprland owns its placement (hypr/scripts/modal-windows.lua + the qs-modal window rule):
// SUPER+LMB drags it, the position is remembered per kind, a double-click on the header re-centres it. Esc / X close it;
// there is no click-outside (it is a window), and it does not register with Popups (a click on another monitor or
// a bar popup leaves it open), but opening it closes the bar popups and the launcher.
// ModalMenu is the layer-shell sibling (launcher / dmenu, whose height follows the result list).
// The user handles keys in onKeyPressed (set ev.accepted) and resets its state in onOpening.
FloatingWindow {
    id: win

    property string kind: ""                       // the window title is "qs-" + kind (what the Hyprland rule matches)
    property string heading: ""
    property string icon: ""
    property color iconColor: Theme.accent
    property string iconFamily: Theme.iconFont    // Theme.brandFont for a brand logo
    property Item focusItem: null                  // gets keyboard focus on open (e.g. a search field); null = onKeyPressed
    property int cardWidth: 520
    property bool shown: false
    readonly property alias card: cardBox
    default property alias content: body.data

    signal opening()                               // just before it shows
    signal keyPressed(var event)

    function open() {
        if (shown) return
        Popups.closeAll()
        opening()
        shown = true
        const f = win.focusItem || keys
        f.forceActiveFocus()
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open() }

    title: "qs-" + kind
    visible: shown
    color: "transparent"
    implicitWidth: cardWidth
    implicitHeight: body.implicitHeight + 40
    minimumSize: Qt.size(implicitWidth, implicitHeight)   // fixed size: the compositor follows the card
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: contentItem; active: visible }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => win.keyPressed(ev)
    }

    Rectangle {
        id: cardBox
        readonly property bool isGlassItem: true
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.glass ? 0.3 : 0.85)   // glass behind it (Glass.qml); without solid_glass: blurred by the qs-modal window rule
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            Item {   // header: double-click re-centres the window
                Layout.fillWidth: true
                Layout.preferredHeight: headerRow.implicitHeight
                ModalReset { windowTitle: win.title; anchors.fill: parent }
                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    spacing: 10
                    Icon { text: win.icon; font.family: win.iconFamily; font.pixelSize: 16; color: win.iconColor }
                    Label { text: win.heading; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                    Btn { icon: true; text: ""; inset: 20; onClicked: win.close() }   // 20 px inside the card
                }
            }
        }
    }
}
