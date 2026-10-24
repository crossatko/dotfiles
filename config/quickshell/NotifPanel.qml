pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Notification center (opened by the clock chip). A BARE popup (PopupHost draws no card, fill, border or blur for
// it): a glass header strip (title, count, Clear) and one glass NotifCard per notification, newest first, same look
// as the toasts. The cards are standalone glass items, each with its own blur region (Glass.qml), which skips
// scrolling views: so the list is not a ListView/Flickable but a Column that scrolls by WHOLE cards
// (mouse wheel); a card that does not fit completely is hidden (opacity 0), so no half-visible glass is left behind.
// Nothing is clipped on purpose: a glass region cannot be clipped, so a card that slides out (swipe / dismiss) fades
// out together with its glass instead of being cut off by a clip while its blur box stays.
ColumnLayout {
    id: panel
    spacing: 8

    // PopupHost's card glass scale while the popup is in motion (see NotifCard.hostGlassScale)
    property real popupScale: 1
    property int scroll: 0                       // index of the first card shown
    readonly property int count: rep.count
    readonly property bool overflow: column.height > view.height + 1

    // the largest `scroll` that still fills the view (no gap at the bottom after the last card)
    function maxFirst() {
        void column.height; void view.height
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && column.height - it.y <= view.height + 1) return i
        }
        return Math.max(0, rep.count - 1)
    }
    readonly property int first: Math.max(0, Math.min(scroll, maxFirst()))

    NotifHeader { Layout.fillWidth: true; overflow: panel.overflow; popupScale: panel.popupScale }

    Item {
        id: view
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Notifs.count === 0 ? 46 : 0
        Layout.preferredHeight: Notifs.count === 0 ? 46 : column.height

        readonly property real topY: { void rep.count; const it = rep.itemAt(panel.first); return it ? it.y : 0 }

        // empty / do-not-disturb state: one glass strip like the others
        Rectangle {
            readonly property bool isGlassItem: true
            readonly property real glassScale: panel.popupScale
            visible: Notifs.count === 0
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.alpha(Theme.bg, Theme.cardFill)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.5)
            Label {
                anchors.centerIn: parent
                text: Notifs.dnd ? "Do not disturb is on" : "No notifications"
                color: Theme.muted
            }
        }

        Column {
            id: column
            width: view.width
            y: -view.topY
            Repeater {
                id: rep
                model: ScriptModel { values: Notifs.all.values.slice().reverse() }      // newest first; rows keep their identity (and scroll position) when another one goes
                onItemAdded: Qt.callLater(() => panel.scroll = 0)   // a new one lands on top: show it
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property real cardH: card.implicitHeight * card.collapse
                    // whole cards only: the first one shown always, others when they fit completely
                    readonly property bool fits: index === panel.first
                        || (y >= view.topY - 1 && y + cardH <= view.topY + view.height + 1)
                    width: column.width
                    height: cardH + (index < rep.count - 1 ? 8 * card.collapse : 0)
                    opacity: fits ? 1 : 0
                    enabled: fits
                    NotifCard {
                        id: card
                        n: row.modelData
                        glass: true
                        hostGlassScale: panel.popupScale
                        width: row.width
                    }
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: ev => {
                acc += ev.angleDelta.y
                while (Math.abs(acc) >= 120) {
                    panel.scroll = Math.max(0, Math.min(panel.first + (acc < 0 ? 1 : -1), panel.maxFirst()))
                    acc += acc < 0 ? 120 : -120
                }
            }
        }
    }
}
