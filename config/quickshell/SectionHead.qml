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
        font.pixelSize: Theme.fontCaption
        font.letterSpacing: 1.2
        font.bold: true
    }
    // the rule takes all the width the title, detail and trailing items leave
    Item {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.gapRow
        Layout.minimumWidth: Theme.gapRow
        Layout.preferredHeight: 1
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: Theme.edge }
    }
    // the detail gives way first on a narrow page (elided), the rule after it (minimum 8)
    Label { visible: head.detail !== ""; Layout.leftMargin: Theme.gapRow; Layout.maximumWidth: Math.max(80, head.width * 0.45); elide: Text.ElideRight; text: head.detail; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    // No slot (or gap) while the trailing items are hidden. The slot itself stays visible: binding its own
    // `visible` to `visibleChildren` latched it off for good whenever it was evaluated while the children were
    // still hidden (a hidden parent makes every child report visible = false), e.g. the Wi-Fi switch before
    // NetworkManager listed the adapter.
    RowLayout {
        id: extra
        readonly property bool used: visibleChildren.length > 0
        spacing: Theme.controlGap
        Layout.leftMargin: used ? Theme.gapRow : 0
        Layout.preferredWidth: used ? implicitWidth : 0
        Layout.maximumWidth: used ? implicitWidth : 0
    }
}
