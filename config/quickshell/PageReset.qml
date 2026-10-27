import QtQuick
import QtQuick.Layouts

// The last row of a Settings page: "Reset this page" (active while anything on the page is changed from its default),
// an optional info glyph (`info`: where the values are saved) and nothing else.
RowLayout {
    id: pr
    property bool dirty: false
    property string label: "Reset this page"
    property string info: ""
    property string objectName_: "btn-page-reset"
    signal reset()

    Layout.fillWidth: true
    Layout.topMargin: 6
    spacing: 12
    Btn {
        objectName: pr.objectName_
        text: pr.label
        outerRadius: Theme.radiusPage; inset: 9
        implicitHeight: 26
        enabledLook: pr.dirty
        onClicked: if (pr.dirty) pr.reset()
    }
    InfoTip { text: pr.info }
    Item { Layout.fillWidth: true }
}
