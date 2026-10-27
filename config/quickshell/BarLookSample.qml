pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Settings > Bar > Bar look: the preview inside one look card. A 16:9 mini screen with the wallpaper and a sketch of the
// bar on the picked monitor's edge: Floating = a rounded pill inset from the edges, Docked = a flush strip with its
// fill, Transparent = no strip, just the chips' ink straight on the wallpaper (dark ink on a bright wallpaper, light on
// a dark one, or the forced Dark / Light text mode; Theme text mode = the palette). `preset` = a Presets.barLook id.
Item {
    id: bs
    property string preset: "docked"
    property string wallpaper: ""
    property string edge: "top"            // BarConfig.edge of the picked monitor
    property string contrast: "auto"       // BarConfig.contrast of the picked monitor
    readonly property real r: Theme.inner(Theme.radiusPage, 8)
    readonly property bool atTop: edge === "top"

    // rough brightness of the wallpaper (an 8x8 sample), for Auto ink; unknown = dark
    property real luma: 0
    Canvas {
        id: probe
        width: 8; height: 8
        visible: false
        renderTarget: Canvas.Image
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, 8, 8)
            ctx.drawImage(bs.wallpaper, 0, 0, 8, 8)
            const d = ctx.getImageData(0, 0, 8, 8).data
            let s = 0
            for (let i = 0; i < d.length; i += 4) s += 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]
            bs.luma = s / (d.length / 4) / 255
        }
        Component.onCompleted: if (bs.wallpaper) loadImage(bs.wallpaper)
        Connections { target: bs; function onWallpaperChanged() { if (bs.wallpaper) probe.loadImage(bs.wallpaper) } }
    }
    readonly property bool inkDark: contrast === "dark" || (contrast !== "light" && luma > 0.5)
    // chip colour for the Transparent look: forced / measured ink; Theme text mode keeps the palette
    readonly property var inkSet: inkDark ? Theme.barInkDark : Theme.barInkLight
    readonly property color bareInk: contrast === "off" ? Theme.fg : inkSet.fg

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: corners }
        Image {
            id: wall
            anchors.fill: parent
            source: bs.wallpaper ? "file://" + bs.wallpaper : ""
            sourceSize.width: 320
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            Rectangle { anchors.fill: parent; color: Theme.bgAlt; visible: wall.status !== Image.Ready }
        }
        // the bar sketch
        Rectangle {
            id: strip
            readonly property bool floating: bs.preset === "floating"
            readonly property bool bare: bs.preset === "transparent"
            readonly property real inset: floating ? Math.round(parent.width * 0.05) : 0
            x: inset
            width: parent.width - 2 * inset
            height: Math.round(parent.height * 0.17)
            y: bs.atTop ? inset * 0.8 : parent.height - height - inset * 0.8
            radius: floating ? height / 2 : 0
            color: bare ? "transparent" : Theme.alpha(Theme.surface2, 0.92)
            border.width: bare ? 0 : 1
            border.color: Theme.alpha(Theme.overlay, 0.6)
            readonly property color ink: bare ? bs.bareInk : Theme.fg
            readonly property real pad: floating ? height * 0.5 : Math.round(width * 0.04)
            // three groups of chips: left, centre, right
            Row {
                anchors { left: parent.left; leftMargin: strip.pad; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater { model: [0.07, 0.05]; Rectangle { required property real modelData; width: strip.width * modelData; height: strip.height * 0.4; radius: height / 2; color: Theme.alpha(strip.ink, 0.8) } }
            }
            Rectangle { anchors.centerIn: parent; width: strip.width * 0.1; height: strip.height * 0.4; radius: height / 2; color: Theme.alpha(strip.ink, 0.8) }
            Row {
                anchors { right: parent.right; rightMargin: strip.pad; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater { model: [0.05, 0.07]; Rectangle { required property real modelData; width: strip.width * modelData; height: strip.height * 0.4; radius: height / 2; color: Theme.alpha(strip.ink, 0.8) } }
            }
        }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: bs.r; visible: false; layer.enabled: true }
}
