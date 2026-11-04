import QtQuick

// One part of a monitor's wallpaper still, decoded alone (ScreenBackdrop): the still cover-cropped to `screenW` x `screenH`
// (as the wallpaper layer shows it), of that only the rect `view` (screen px), decoded at `decodeScale` px per screen px
// (Image.sourceClipRect: formats that support it decode just that region, the others decode and cut). Fills this item.
// `aspect` = the still's width / height (0 = unknown yet: nothing is drawn).
Item {
    id: wc
    property string source: ""
    property real screenW: 1920
    property real screenH: 1080
    property rect view: Qt.rect(0, 0, screenW, screenH)
    property real decodeScale: 1
    property real aspect: 0

    readonly property bool wide: aspect > screenW / Math.max(1, screenH)
    readonly property real coverW: wide ? screenH * aspect : screenW
    readonly property real coverH: wide ? screenH : screenW / Math.max(0.01, aspect)
    readonly property real k: Math.max(0.01, decodeScale)

    Image {
        anchors.fill: parent
        visible: wc.aspect > 0 && wc.view.width > 0 && wc.view.height > 0
        source: visible ? wc.source : ""
        sourceSize: Qt.size(Math.round(wc.coverW * wc.k), Math.round(wc.coverH * wc.k))
        sourceClipRect: Qt.rect(Math.round(((wc.coverW - wc.screenW) / 2 + wc.view.x) * wc.k),
                                Math.round(((wc.coverH - wc.screenH) / 2 + wc.view.y) * wc.k),
                                Math.max(1, Math.round(wc.view.width * wc.k)), Math.max(1, Math.round(wc.view.height * wc.k)))
        fillMode: Image.Stretch
        asynchronous: true
        retainWhileLoading: true
    }
}
