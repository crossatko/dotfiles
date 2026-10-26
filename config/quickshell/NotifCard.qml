pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification card of the notification stack (NotifStack): the same glass card as a toast and as a row of the
// notification center. The owner (NotifSlot) animates it in and out and runs the actual dismissal.
Rectangle {
    id: card
    // a standalone glass surface (Glass.qml gives it its own blur region)
    readonly property bool isGlassItem: true

    required property var n
    property bool showTime: false       // the notification center shows the arrival time; a plain toast does not
    // the owner's own fade (entering / leaving): multiplied into the opacity, and shrinks the glass region too where
    // the glass itself cannot fade (Glass.qml)
    property real fade: 1
    // the card's own fade (swipe) times the owner's
    readonly property real glassScale: Theme.glassScaleAt(fade * swipeFade)
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

    // What the text offers besides the app's own actions: a verification code to copy, a link to open. A code is only
    // taken when the text talks about one (a bare 4-8 digit number is as likely a year or an amount); a link comes from
    // an <a href> or a plain http(s) address.
    readonly property string text: n.summary + " " + n.body
    readonly property string code: {
        if (!/code|otp|verif|passcode|passwort|password|2fa|one-time|token|kod\b|k\u00f3d/i.test(text)) return ""
        const m = /(?:^|[^\d.,-])(\d{4,8})(?![\d.,]*\d)/.exec(text.replace(/<[^>]*>/g, " "))
        return m ? m[1] : ""
    }
    readonly property string link: {
        const m = /href="(https?:\/\/[^"]+)"/i.exec(n.body) || /(https?:\/\/[^\s<>"']+)/i.exec(n.body)
        return m ? m[1].replace(/&amp;/g, "&").replace(/[.,;:!?)]+$/, "") : ""      // the body is markup: & arrives as &amp;
    }
    readonly property string linkHost: link ? link.replace(/^https?:\/\//i, "").split(/[\/?#]/)[0] : ""
    // buttons: the app's actions, then copy code, then open link
    readonly property var buttons: {
        const out = n.actions.filter(a => a.identifier !== "default").map(a => ({ text: a.text, run: () => a.invoke() }))
        if (code) out.push({ text: "Copy " + code, run: () => Quickshell.execDetached(["wl-copy", "--", card.code]) })
        if (link) out.push({ text: "Open " + linkHost, run: () => { Quickshell.execDetached(["xdg-open", card.link]); card.dismiss() } })
        return out
    }

    implicitHeight: content.implicitHeight + 24
    radius: Theme.radius
    color: Theme.alpha(Theme.bg, Theme.cardFill)
    border.width: 1
    border.color: critical ? Theme.alpha(Theme.red, 0.8) : Theme.alpha(Theme.overlay, 0.5)

    // the one dismiss path (close button, right click, swipe, click): the owner animates the card out and then closes
    // the notification
    signal dismissRequested()
    function dismiss() { dismissRequested() }
    // dismiss with the swipe's fly-out to the right (Clear sweeps the cards one by one); `dismissRequested` follows
    // when it has flown off
    function flyOut() { if (!swipe.busy) swipe.settle(true, 0) }

    // Swipe to the right with the mouse to dismiss (SwipeDismiss). Translate, not x: NotifSlot drives x (slide-in /
    // slide-out).
    SwipeDismiss { id: swipe; onSwiped: card.dismiss() }
    transform: Translate { x: swipe.offset }
    readonly property real swipeFade: swipe.fade
    readonly property bool swiping: swipe.busy       // dragging / springing back / flying off: toasts pause their timeout
    readonly property bool swipedOut: swipe.gone
    opacity: fade * swipeFade

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
                    visible: (Notifs.repeats[card.n.id] ?? 1) > 1
                    text: "\u00d7" + (Notifs.repeats[card.n.id] ?? 1)
                    color: Theme.accent
                    font.pixelSize: Theme.fontCaption
                }
                Label {
                    visible: card.showTime
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
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: card.buttons.length > 0
                Repeater {
                    id: actions
                    model: card.buttons
                    Rectangle {
                        id: actBtn
                        required property var modelData
                        radius: Math.min(Theme.inner(card.radius, 12), Math.floor(height / 3))   // like Btn: concentric, never a pill
                        color: btnGlow.hovered ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.1)
                        implicitWidth: label.implicitWidth + 20
                        implicitHeight: 28
                        Label { id: label; anchors.centerIn: parent; text: actBtn.modelData.text; elide: Text.ElideRight; width: Math.min(implicitWidth, card.width - 100); font.pixelSize: Theme.fontSmall }
                        HoverGlow { id: btnGlow; area: btn; radius: parent.radius }
                        MouseArea { id: btn; anchors.fill: parent; hoverEnabled: true; onClicked: actBtn.modelData.run() }
                    }
                }
            }
        }
    }
}
