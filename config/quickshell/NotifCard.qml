pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification, used for toasts (toast: true) and in the notification center.
Rectangle {
    // A standalone glass card: a toast, or a notification-center row (`glass: true`, same look as the toast). Without
    // `glass` the card sits flat on a panel (nobody uses that any more, kept for panels with their own card).
    readonly property bool isGlassItem: toast || glass
    id: card

    required property var n
    property bool toast: false
    property bool glass: false
    // the host popup's glass scale (PopupHost card in motion on a compositor whose glass cannot fade), see Glass.qml
    property real hostGlassScale: 1
    // Glass.qml: the card's own fade (swipe / leaving) shrinks the region too where the glass cannot fade
    readonly property real glassScale: toast ? 1 : hostGlassScale * Theme.glassScaleAt(swipeFade * leaveFade)
    readonly property bool hovered: hover.hovered
    readonly property bool critical: n.urgency === NotificationUrgency.Critical
    // The server hands themed icon *names* over as "image://icon/<name>" in n.image (and leaves
    // appIcon empty); unwrap that so NotifIcon can look for a symbolic variant. Anything else in
    // n.image is genuine image data (avatar, cover art) and is shown as is.
    readonly property bool imageIsIcon: n.image.startsWith("image://icon/")
    readonly property string iconName: imageIsIcon ? decodeURIComponent(n.image.substring(13)) : n.appIcon
    readonly property string realImage: imageIsIcon ? "" : n.image
    readonly property var defaultAction: {
        for (const a of n.actions) if (a.identifier === "default") return a
        return null
    }

    implicitHeight: content.implicitHeight + 24
    radius: isGlassItem ? Theme.radius : Theme.radiusItem      // glass card = outer element; else an item inside a panel
    color: isGlassItem ? Theme.alpha(Theme.bg, Theme.cardFill) : Theme.alpha(Theme.surface, 0.85)
    border.width: 1
    border.color: critical ? Theme.alpha(Theme.red, 0.8) : Theme.alpha(Theme.overlay, 0.5)

    // Notification center: slide out to the right, then let the row collapse (the parent reads `collapse`), then dismiss.
    property real collapse: 1
    property bool leaving: false
    property real leaveFade: 1      // the slide-out fades the card (and with it its glass)
    function leave() {
        if (leaving) return
        leaving = true
        leaveAnim.start()
    }
    SequentialAnimation {
        id: leaveAnim
        // a swiped card is already off to the right: only the gap closes
        ParallelAnimation {
            NumberAnimation { target: card; property: "x"; to: card.width + 40; duration: card.swipedOut ? 0 : 200; easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "leaveFade"; to: 0; duration: card.swipedOut ? 0 : 200; easing.type: Easing.InCubic }
        }
        NumberAnimation { target: card; property: "collapse"; to: 0; duration: Theme.popupMoveMs; easing.type: Theme.popupEaseClose }
        ScriptAction { script: card.n.dismiss() }
    }
    // the one dismiss path (close button, right click, swipe): toast -> leaves the stack and is closed after its exit
    // animation; notification center -> leave()
    function dismiss() {
        if (toast) { Notifs.dismissPopup(n); Notifs.releaseLater(n) }
        else card.leave()
    }

    // Swipe to the right with the mouse to dismiss (SwipeDismiss). Translate, not x: Toasts drives x (slide-in) and
    // leave() animates it. Owners that set their own opacity multiply in `swipeFade`.
    SwipeDismiss { id: swipe; onSwiped: card.dismiss() }
    transform: Translate { x: swipe.offset }
    readonly property real swipeFade: swipe.fade
    readonly property bool swiping: swipe.busy       // dragging / springing back / flying off: toasts pause their timeout
    readonly property bool swipedOut: swipe.gone
    opacity: swipeFade * leaveFade

    HoverHandler { id: hover }
    // Clicking a notification takes you to the app: run its default action (so the app can open the right
    // conversation itself) and focus the app's window. bin/focus-app matches the window from the
    // notification's desktop entry / app name and focuses it, which also switches Hyprland group tabs
    // and workspaces/monitors. The notification is dismissed once acted on.
    function activate() {
        if (defaultAction) defaultAction.invoke()
        const de = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        // Chromium/Brave: every site and web app sends desktop-entry "brave-browser"; the only per-site identity
        // is the x-kde-origin-name hint (the origin), which focus-app matches to the app window's class.
        const origin = n.hints && n.hints["x-kde-origin-name"] ? String(n.hints["x-kde-origin-name"]) : ""
        Quickshell.execDetached([Quickshell.shellDir + "/bin/focus-app", n.desktopEntry || "", n.appName || "",
            de && de.startupClass ? de.startupClass : "", origin])
        card.dismiss()
    }
    TapHandler { onTapped: card.activate() }
    // right click: just dismiss, without going to the app
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: card.dismiss()
    }

    // urgency stripe: flush with the left edge when square; with rounded corners a straight stripe looks cut off
    // by the curve, so it becomes an inset pill (inside the border, level with the content padding)
    Rectangle {
        readonly property bool inset: card.radius > 0
        x: inset ? 6 : 0
        y: inset ? 12 : 0
        width: 3
        height: parent.height - (inset ? 24 : 0)
        radius: inset ? width / 2 : 0
        color: card.critical ? Theme.red : card.n.urgency === NotificationUrgency.Low ? Theme.muted : Theme.accent
    }

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 16 }
        spacing: 12

        NotifIcon {
            Layout.alignment: Qt.AlignTop
            name: card.iconName
            image: card.realImage
            size: 40
            // semantic color: errors/critical red, warnings yellow, everything else the accent
            tint: card.critical || /error|critical/.test(card.iconName) ? Theme.red
                : /warning/.test(card.iconName) ? Theme.yellow : Theme.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: card.n.appName
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: !card.toast
                    text: Notifs.ago(card.n.id)
                    color: Theme.muted
                    font.pixelSize: Theme.fontCaption
                }
                Icon {
                    text: "\uf00d"
                    color: closeArea.containsMouse ? Theme.accent : Theme.muted
                    font.pixelSize: 13
                    MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: card.dismiss() }
                }
            }
            Label {
                Layout.fillWidth: true
                text: card.n.summary
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: card.n.body !== ""
                text: card.n.body
                textFormat: Text.StyledText
                color: Theme.fgDim
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.Wrap
                maximumLineCount: card.toast ? 4 : 8
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: actions.count > 0
                Repeater {
                    id: actions
                    model: card.n.actions.filter(a => a.identifier !== "default")
                    Rectangle {
                        id: actBtn
                        required property var modelData
                        radius: Math.min(Theme.inner(card.radius, 12), Math.floor(height / 3))   // like Btn: concentric, never a pill
                        color: btnGlow.hovered ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.1)
                        implicitWidth: label.implicitWidth + 20
                        implicitHeight: 28
                        Label { id: label; anchors.centerIn: parent; text: actBtn.modelData.text; font.pixelSize: Theme.fontSmall }
                        HoverGlow { id: btnGlow; area: btn; radius: parent.radius }
                        MouseArea { id: btn; anchors.fill: parent; hoverEnabled: true; onClicked: actBtn.modelData.invoke() }
                    }
                }
            }
        }
    }
}
