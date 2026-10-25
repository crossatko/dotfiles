pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// The window of the notification stack (NotifStack): the toasts, and the notification center, which is the same stack
// expanded (the clock chip toggles popup `notif` in Popups; this window shows it, PopupHost does not). One window for
// both because the toasts that are already on screen must stay exactly where they are when the center opens, and a
// separate popup window could only draw over them. It behaves like a PopupHost popup: it is registered in Popups
// (`Popups.name === "notif"`, so the chip highlights, only one popup is open, the other monitors' ClickCatcher closes
// it), a click on the empty screen and Esc close it, the bar strip is cut out of its input so another chip opens in one
// click.
// The window is FULL SCREEN and never resized (a layer surface that is resized is shown stretched to its new size
// until the matching buffer arrives, which squashed and overlapped the cards while the stack grew and shrank): only
// the cards are glass (Glass.qml) and only the cards take input (mask), or in list mode the whole screen minus the bar.
// Top-right of the focused monitor, below a top bar if that screen has one; the list opens at the same place.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: win

    property var bars: ({})
    property var target: Quickshell.screens[0]

    screen: target
    // the center is open on this window's screen
    readonly property bool centerOpen: Popups.name === "notif" && !!target && Popups.screen === target.name
    visible: Notifs.popups.length > 0 || centerOpen || stack.count > 0 || stack.animating   // stays up while the last card / the header is still animating out
    anchors { top: true; bottom: true; left: true; right: true }
    readonly property string edge: bars[(target ? target.name : "")] ?? ""
    // Theme.edgeGap from the screen edge, or past a bar (incl. a floating bar's gap) by the same amount
    readonly property real gap: BarConfig.edgeGapOf(screen)
    readonly property real topInset: gap + (edge === "top" ? BarConfig.insetOf(screen) : 0)
    readonly property real bottomInset: gap + (edge === "bottom" ? BarConfig.insetOf(screen) : 0)
    color: "transparent"
    // -1 = ignore the monitor's reserved area (the pinned-video strip), so it stays in the screen corner; 0 = follow the bar
    // (Settings > Bar). This window hops between screens: a zone changed in the same tick as the screen was not applied to the
    // re-created layer surface, so it is set a moment after the screen / the option changed.
    readonly property bool respectReserved: BarConfig.respectReserved(screen)
    property int zone: -1
    onRespectReservedChanged: zoneTimer.restart()
    onScreenChanged: zoneTimer.restart()
    Component.onCompleted: zone = respectReserved ? 0 : -1
    Timer { id: zoneTimer; interval: 80; onTriggered: win.zone = win.respectReserved ? 0 : -1 }
    exclusiveZone: zone
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-toast"
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: win.contentItem; active: visible }

    // The list mode takes keyboard focus on demand like a popup, but only once it has been open for a moment (see
    // PopupHost: a surface that maps asking for keyboard focus pulls the pointer off the bar). Esc also arrives from
    // the Hyprland keybind (`popup esc`), which works without focus.
    property bool armed: false
    Timer { interval: 150; running: win.centerOpen; onTriggered: win.armed = true }
    onCenterOpenChanged: { if (!centerOpen) armed = false; else keys.forceActiveFocus() }
    WlrLayershell.keyboardFocus: armed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    Item { id: keys; focus: true; Keys.onEscapePressed: Popups.close() }

    // click on the empty screen closes the list; the bar strip is cut out of the input region
    MouseArea { id: scrim; anchors.fill: parent; enabled: win.centerOpen; onClicked: Popups.close() }
    Item {
        id: barStrip
        width: parent.width
        height: win.centerOpen && win.edge !== "" ? BarConfig.reserveOf(win.screen) : 0
        y: win.edge === "bottom" ? parent.height - height : 0
    }
    // toast mode: only the cards take clicks, the rest falls through
    mask: Region { item: win.centerOpen ? scrim : stack; regions: [ Region { item: barStrip; intersection: Intersection.Subtract } ] }

    // follow focus, but only when a new stack starts (0 -> 1), so a toast never jumps monitors; the list opens on
    // the monitor whose clock was clicked
    property int lastCount: 0
    Connections {
        target: Notifs
        function onPopupsChanged() {
            const n = Notifs.popups.length
            if (win.lastCount === 0 && n > 0 && !win.centerOpen) win.target = Popups.focusedScreen()
            win.lastCount = n
        }
    }
    Connections {
        target: Popups
        function onNameChanged() { win.followCenter() }
        function onScreenChanged() { win.followCenter() }
    }
    function followCenter() {
        if (Popups.name !== "notif") return
        const s = Quickshell.screens.find(s => s.name === Popups.screen)
        if (s && s !== target) target = s
    }

    NotifStack {
        id: stack
        x: win.width - cardWidth - win.gap
        y: win.topInset
        open: win.centerOpen
        maxHeight: win.height - win.topInset - win.bottomInset
        onCardAdded: glass.refresh()     // the new card has its glass from its first frame
    }
}
