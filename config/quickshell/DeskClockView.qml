pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell

// The desktop clock's picture (DeskClock.qml shows it on the desktop, DeskClockPreview in Settings): the time in glass
// lettering (one GlassText per character, as the lock clock) and the date in the UI font, refracting what the desktop
// shows under it: the play-once video wallpaper of `connector` (DeskClockVideo: the same clip in step with the desktop
// player, moving during a burst), else `wallpaper` (the still / image, cropped like hyprpaper's cover). Nothing else is
// drawn behind the lettering; all optics come from Settings > Glass (GlassTuneCtl.effective).
// This item is SCREEN sized (backdrop coordinates); the clock sits in `area` (DeskClockPrefs size / position), the caller
// shows only that part. Until a source has a frame the lettering is GlassTextFlat, then the glass forms (popup motion
// tokens; none = instant). Without Theme.glass GlassText is flat anyway.
// Idle: nothing animates; a minute change morphs one digit; a burst redraws the clock with the video's frames.
Item {
    id: v
    property string wallpaper: ""
    property string connector: ""           // "" = no video (Settings preview)
    property bool preview: false            // Settings: the wallpaper is drawn too (on the desktop it is under the window)
    readonly property bool wallReady: img.status === Image.Ready && img.source !== ""
    readonly property bool videoOn: video.ready
    readonly property Item source: videoOn ? video.output : stage
    readonly property bool sourceReady: videoOn || wallReady

    readonly property real unit: Math.min(width, height)
    readonly property int pixelSize: Math.max(24, Math.round(unit * DeskClockPrefs.size))
    readonly property real margin: Math.round(unit * 0.03)
    readonly property real pad: Math.round(pixelSize * 0.4)           // the glass's shadow / caustic around the glyphs
    readonly property real boxW: col.width
    readonly property real boxH: col.height
    readonly property real boxX: Math.round(margin + DeskClockPrefs.posX * Math.max(0, width - 2 * margin - boxW))
    readonly property real boxY: Math.round(margin + DeskClockPrefs.posY * Math.max(0, height - 2 * margin - boxH))
    // the drawn part, in screen coordinates (the window's geometry)
    readonly property rect area: Qt.rect(Math.max(0, boxX - pad), Math.max(0, boxY - pad),
                                         Math.min(width, boxX + boxW + pad) - Math.max(0, boxX - pad),
                                         Math.min(height, boxY + boxH + pad) - Math.max(0, boxY - pad))

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property string text: DeskClockPrefs.clock24h ? Qt.formatDateTime(clock.date, "HH:mm") : Qt.formatDateTime(clock.date, "h:mm AP").replace(/\s*[AP]M$/i, "")

    // flat <-> glass: 1 = flat lettering (no source yet), 0 = glass
    readonly property bool wantFlat: !sourceReady
    property real flatT: 1
    onWantFlatChanged: {
        flatAnim.stop()
        flatAnim.to = wantFlat ? 1 : 0
        flatAnim.duration = wantFlat ? Theme.popupCloseMs : Theme.popupMs(Motion.baseMs * 3)
        if (flatAnim.duration <= 0) flatT = flatAnim.to
        else flatAnim.start()
    }
    Component.onCompleted: flatT = wantFlat ? 1 : 0
    NumberAnimation { id: flatAnim; target: v; property: "flatT"; easing.type: Easing.InOutSine }

    // ---- what the glass refracts ----
    Item {
        id: stage
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true      // sampled bent by the glass
        Image {
            id: img
            anchors.fill: parent
            source: v.wallpaper !== "" && v.width > 0 ? "file://" + v.wallpaper : ""
            sourceSize: Qt.size(v.width, v.height)
            fillMode: Image.PreserveAspectCrop        // = hyprpaper's cover
            asynchronous: true
        }
    }
    // the video copy: drawn (an invisible VideoOutput gets no frames), but all but transparent, so the window shows
    // only the lettering; the desktop's own player is right under it
    DeskClockVideo {
        id: video
        anchors.fill: parent
        connector: v.preview ? "" : v.connector
        opacity: 0.004
    }

    // Settings preview: the desktop under the clock
    ShaderEffectSource { anchors.fill: parent; visible: v.preview; sourceItem: stage; hideSource: false }

    // ---- the clock ----
    Column {
        id: col
        x: v.boxX; y: v.boxY
        spacing: -Math.round(v.pixelSize * 0.04)     // the glyph box has room for descenders the digits do not use
        Row {
            id: glyphs
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(v.pixelSize * 0.03)
            Repeater {
                model: v.text.length
                Item {
                    id: slot
                    required property int index
                    implicitWidth: g.implicitWidth
                    implicitHeight: g.implicitHeight
                    GlassText {
                        id: g
                        text: v.text.charAt(slot.index)
                        pixelSize: v.pixelSize
                        backdrop: v.source
                        sharpBackdrop: v.source
                        backdropSize: Qt.size(v.width, v.height)
                        origin: Qt.point(col.x + glyphs.x + slot.x, col.y + glyphs.y + slot.y)
                        strength: Math.max(0.001, 1 - v.flatT)
                        opacity: Math.min(1, (1 - v.flatT) * 1.4)
                        visible: v.flatT < 1
                    }
                    GlassTextFlat {
                        x: -g.pad; y: -g.pad
                        visible: v.flatT > 0 && Theme.glass      // without Theme.glass GlassText shows this itself
                        opacity: v.flatT
                        text: g.text; pixelSize: g.pixelSize; weight: g.weight; pad: g.pad
                    }
                }
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: DeskClockPrefs.showDate
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
            font.pixelSize: Math.max(Theme.fontTitle, Math.round(v.pixelSize * 0.09))
            font.weight: Font.Medium
            color: Theme.fg
            layer.enabled: true
            // 2x on a scale-1 output (smooth halo, no colour fringes from the text in the layer), 1x on scaled outputs
            layer.smooth: true
            layer.textureSize: Screen.devicePixelRatio > 1 ? Qt.size(0, 0) : Qt.size(width * 2, height * 2)
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 1; shadowHorizontalOffset: 0; shadowColor: Theme.alpha(Theme.bg, 0.9) }
        }
    }
}
