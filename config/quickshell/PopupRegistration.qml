import QtQuick

// Registers a click-away thing that is NOT a PopupHost popup (launcher, Settings, modal menus, tray menus) with
// the Popups singleton: while `open`, it is the one open thing (opening it closes every other popup), and when
// anything else opens, or ClickCatcher sees a click on another monitor, `dismissed()` fires: close yourself there.
//   PopupRegistration { kind: "menu"; open: menu.shown; screenName: menu.screen ? menu.screen.name : ""; onDismissed: menu.close() }
Item {
    id: reg
    property string kind: ""
    property bool open: false
    property string screenName: ""
    signal dismissed()

    visible: false
    onOpenChanged: open ? Popups.opened(kind, screenName) : Popups.closed(kind)
    Connections {
        target: Popups
        function onDismiss(except) { if (except !== reg.kind && reg.open) reg.dismissed() }
    }
}
