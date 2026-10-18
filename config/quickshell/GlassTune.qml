import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// solid_glass live configurator: a small card docked to the right edge (the middle of the screen stays free to
// watch the effect). One slider per decoration:blur:solid_glass:* option, applied live by GlassTuneCtl.
//   qs ipc call glasstune toggle      (or the bar button)
// Not a PopupRegistration thing on purpose: it is a tool window that stays open while you click elsewhere.
PanelWindow {
    id: win

    readonly property var tune: GlassTuneCtl
    readonly property int cardWidth: 340
    property bool showSnippet: false

    visible: tune.shown
    screen: Popups.focusedScreen()
    anchors { right: true; top: true }
    margins { right: 12; top: 60 }
    implicitWidth: cardWidth
    implicitHeight: Math.min(col.implicitHeight + 28, (screen ? screen.height : 900) - 80)
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: tune.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-glasstune"
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: contentItem; active: win.visible }

    function tintChannel(shift) { return (Math.round(tune.values.tint) >>> shift) & 255 }
    function setTint(shift, v) {
        const t = Math.round(tune.values.tint) >>> 0
        const nt = (t & ~(255 << shift)) | (Math.round(v) << shift)
        tune.set("tint", nt >>> 0)
    }
    readonly property color tintColor: Qt.rgba(tintChannel(16) / 255, tintChannel(8) / 255, tintChannel(0) / 255, tintChannel(24) / 255)

    Rectangle {
        id: card
        readonly property bool isGlassItem: true
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, 0.45)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        MouseArea { anchors.fill: parent; onWheel: w => w.accepted = true }   // wheel over gaps must not leak

        Flickable {
            id: flick
            anchors { fill: parent; margins: 14 }
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ColumnLayout {
                id: col
                width: flick.width
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Icon { text: ""; font.pixelSize: 15; color: Theme.accent }       // wand-magic
                    Label { text: "Glass tune"; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.fillWidth: true }
                    Btn { icon: true; text: ""; inset: 14; onClicked: tune.shown = false }   // xmark
                }

                Label {
                    visible: tune.guard !== "ok"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: tune.guard === "error" ? Theme.red : Theme.muted
                    font.pixelSize: Theme.fontSmall
                    text: tune.guard === "error" ? "Disabled: " + tune.guardError : "Checking the compositor instance..."
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    enabled: tune.ready
                    opacity: tune.ready ? 1 : 0.4

                    Repeater {
                        model: ["Lens", "Light", "Material"]
                        ColumnLayout {
                            id: grp
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: grp.modelData.toUpperCase(); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; font.letterSpacing: 1; Layout.topMargin: 4 }
                            Repeater {
                                model: tune.opts.filter(o => o.group === grp.modelData)
                                GlassTuneRow {
                                    required property var modelData
                                    label: modelData.label
                                    from: modelData.min; to: modelData.max; def: modelData.def
                                    dec: modelData.dec; unit: modelData.unit || ""; curve: modelData.curve || 1
                                    value: tune.values[modelData.key]
                                    onEdited: v => tune.set(modelData.key, v)
                                }
                            }
                            // tint: swatch + A / R / G / B channels (alpha = absorption)
                            ColumnLayout {
                                visible: grp.modelData === "Material"
                                Layout.fillWidth: true
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Label { text: "Tint"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true }
                                    Label { text: "0x" + ("00000000" + (Math.round(tune.values.tint) >>> 0).toString(16).toUpperCase()).slice(-8); font.pixelSize: Theme.fontSmall }
                                    Rectangle {
                                        implicitWidth: 34; implicitHeight: 20
                                        radius: Math.min(5, Theme.radiusDeep)
                                        color: "#808080"
                                        clip: true
                                        Rectangle { anchors.fill: parent; radius: parent.radius; color: win.tintColor }
                                        Rectangle { width: parent.width / 2; height: parent.height; radius: parent.radius; color: Qt.rgba(win.tintColor.r, win.tintColor.g, win.tintColor.b, 1) }
                                        border.width: 1; border.color: Theme.alpha(Theme.fg, 0.3)
                                    }
                                    Btn {
                                        icon: true; text: ""; implicitHeight: 20; implicitWidth: 24
                                        enabledLook: tune.isChanged("tint")
                                        onClicked: tune.reset("tint")
                                    }
                                }
                                Repeater {
                                    model: [
                                        { n: "Absorption (A)", s: 24, d: 0x14 },
                                        { n: "Red", s: 16, d: 0xEE },
                                        { n: "Green", s: 8, d: 0xF5 },
                                        { n: "Blue", s: 0, d: 0xFF }
                                    ]
                                    GlassTuneRow {
                                        required property var modelData
                                        label: modelData.n
                                        from: 0; to: 255; def: modelData.d; dec: 0
                                        value: win.tintChannel(modelData.s)
                                        onEdited: v => win.setTint(modelData.s, v)
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- actions ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 4
                    Btn { text: "Copy changed"; enabledLook: tune.ready; Layout.fillWidth: true; onClicked: tune.copy(true) }
                    Btn { text: "Copy all"; enabledLook: tune.ready; Layout.fillWidth: true; onClicked: tune.copy(false) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Btn { text: "Reset all"; enabledLook: tune.ready; Layout.fillWidth: true; onClicked: tune.reset("all") }
                    Btn { text: win.showSnippet ? "Hide Lua" : "Show Lua"; active: win.showSnippet; Layout.fillWidth: true; onClicked: win.showSnippet = !win.showSnippet }
                }
                Rectangle {
                    visible: win.showSnippet
                    Layout.fillWidth: true
                    implicitHeight: snip.implicitHeight + 16
                    radius: Theme.radiusItem
                    color: Theme.alpha(Theme.fg, 0.07)
                    TextEdit {
                        id: snip
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        readOnly: true
                        selectByMouse: true
                        text: tune.snippet(true)
                        color: Theme.fg
                        font.family: Theme.font; font.pixelSize: Theme.fontCaption
                        wrapMode: TextEdit.NoWrap
                    }
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                    text: tune.status + (tune.nestedOnly ? (tune.status ? "\n" : "") + "Applies to the nested dev instance only" : "")
                }
            }
        }
    }
}
