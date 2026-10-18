import QtQuick
import QtQuick.Layouts

// Small group heading: label, a hairline rule, optional detail text and an optional trailing item
// (put a Toggle etc. in as a child).
RowLayout {
    id: head
    property string title: ""
    property string detail: ""
    default property alias trailing: extra.data

    Layout.fillWidth: true
    spacing: 0      // gaps are left margins below, so an empty trailing slot leaves no gap

    Label {
        text: head.title.toUpperCase()
        color: Theme.fgDim
        font.pixelSize: 11
        font.letterSpacing: 1.2
        font.bold: true
    }
    // the rule takes all the width the title, detail and trailing items leave
    Item {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.minimumWidth: 8
        Layout.preferredHeight: 1
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: Theme.alpha(Theme.overlay, 0.55) }
    }
    Label { visible: head.detail !== ""; Layout.leftMargin: 8; text: head.detail; color: Theme.muted; font.pixelSize: 11 }
    // No slot (or gap) while the trailing items are hidden. The slot itself stays visible: binding its own
    // `visible` to `visibleChildren` latched it off for good whenever it was evaluated while the children were
    // still hidden (a hidden parent makes every child report visible = false), e.g. the Wi-Fi switch before
    // NetworkManager listed the adapter.
    RowLayout {
        id: extra
        readonly property bool used: visibleChildren.length > 0
        spacing: 6
        Layout.leftMargin: used ? 8 : 0
        Layout.preferredWidth: used ? implicitWidth : 0
        Layout.maximumWidth: used ? implicitWidth : 0
    }
}
