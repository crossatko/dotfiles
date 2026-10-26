import QtQuick
import QtQuick.Layouts

// "Optional bundle not installed" hint: title, explanation, the install command and a button that copies it.
// Shows itself only while the bundle's binaries are missing (OptionalPackages); `desc` overrides the default text.
// Inside a popup: default insets. Inside a settings page set outerRadius / inset like any Btn.
Notice {
    id: mp
    property string bundle: ""
    property string desc: ""
    property real btnRadius: Theme.radiusItem
    readonly property var meta: OptionalPackages.info(bundle)

    visible: OptionalPackages.isMissing(bundle)
    Component.onCompleted: OptionalPackages.refresh()

    Label { Layout.fillWidth: true; text: mp.meta.title; font.bold: true; wrapMode: Text.WordWrap }
    Label {
        Layout.fillWidth: true
        text: mp.desc !== "" ? mp.desc : mp.meta.desc
        color: Theme.fgDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap
    }
    Label {
        Layout.fillWidth: true
        text: OptionalPackages.command(mp.bundle)
        color: Theme.fgDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.WrapAnywhere
    }
    CopyBtn {
        label: "Copy install command"; value: OptionalPackages.command(mp.bundle)
        outerRadius: mp.btnRadius; inset: mp.padX
    }
}
