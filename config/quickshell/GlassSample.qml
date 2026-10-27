pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Settings > Look & feel > Glass style: the preview inside one preset card. A sketch of that preset's glass over the
// wallpaper (a slab in the middle: frost = blur, refraction x depth = how much it magnifies, darkening + tint = its
// veil, specular / sheen = the light on its top edge, saturation), drawn by the shell, so it works on stock Hyprland
// too and never touches the compositor. The sketch exaggerates (a 70 px card must tell the presets apart): the real
// glass is the Settings window itself, which changes the moment a preset is picked. `preset` = a Presets.glass id, or
// "custom" for the saved values (GlassTuneCtl.values).
Item {
    id: gs
    property string preset: "custom"
    property string wallpaper: LockWallpapers.primary     // the page passes the wallpaper of the monitor Settings is on
    readonly property var p: Presets.glass.find(x => x.id === gs.preset) ?? null
    readonly property var v: p ? p.v : GlassTuneCtl.values
    readonly property color tint: p ? Qt.rgba(((p.tint >>> 16) & 255) / 255, ((p.tint >>> 8) & 255) / 255, (p.tint & 255) / 255, ((p.tint >>> 24) & 255) / 255)
                                     : GlassTuneCtl.effectiveTint
    readonly property Item cornerMask: corners
    readonly property real r: Theme.inner(Theme.radiusPage, Theme.gapRow)
    // the value ranges the sketch maps (GlassTuneCtl.opts)
    readonly property real refractionMax: GlassTuneCtl.spec("refraction")?.max ?? 48
    readonly property real frostMax: GlassTuneCtl.spec("frost")?.max ?? 16
    function unit(x, max) { return Math.max(0, Math.min(1, (x ?? 0) / max)) }

    Item {
        id: frame
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: gs.cornerMask }
        Image {
            id: wall
            anchors.fill: parent
            source: gs.wallpaper ? "file://" + gs.wallpaper : ""
            sourceSize.width: 320
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            Rectangle { anchors.fill: parent; color: Theme.bgAlt; visible: wall.status !== Image.Ready }   // no wallpaper yet / none set
        }
        // the slab: a popup-like card over that part of the wallpaper, blurred / magnified / veiled
        Item {
            id: slab
            x: Math.round(parent.width * 0.12); y: Math.round(parent.height * 0.16)
            width: Math.round(parent.width * 0.76); height: Math.round(parent.height * 0.68)
            // magnification: refraction x depth (up to 1.5x), a little less when the glass is not clear
            readonly property real mag: 1 + 0.5 * gs.unit(gs.v.refraction, gs.refractionMax) * Math.max(0.2, Math.min(3, gs.v.depth ?? 1)) * (0.6 + 0.4 * (gs.v.clarity ?? 1))
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: slabMask }
            ShaderEffectSource {
                id: src
                sourceItem: wall
                sourceRect: Qt.rect(slab.x + slab.width * (1 - 1 / slab.mag) / 2, slab.y + slab.height * (1 - 1 / slab.mag) / 2, slab.width / slab.mag, slab.height / slab.mag)
                visible: false
                live: true
            }
            MultiEffect {
                anchors.fill: parent
                source: src
                blurEnabled: (gs.v.frost ?? 0) > 0.2
                blur: Math.min(1, gs.unit(gs.v.frost, gs.frostMax) * 2.5)
                blurMax: 32
                saturation: Math.max(-1, Math.min(1, (gs.v.saturation ?? 1) - 1))
                brightness: -0.7 * (gs.v.darkening ?? 0)
            }
            Rectangle { anchors.fill: parent; color: Theme.alpha(gs.tint, 0.8 * gs.tint.a) }
            // the light on the top edge (specular / sheen)
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: parent.height * 0.55
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.alpha("white", 0.06 + 0.3 * Math.min(1, gs.v.specular_intensity ?? 1) + 0.6 * (gs.v.sheen ?? 0)) }
                    GradientStop { position: 1; color: Theme.alpha("white", 0) }
                }
            }
            // the card's content: a few text lines
            Column {
                x: Math.round(slab.width * 0.1); y: Math.round(slab.height * 0.22)
                spacing: Math.max(3, Math.round(slab.height * 0.12))
                Repeater {
                    model: [0.6, 0.42, 0.75]
                    Rectangle { required property real modelData; width: slab.width * 0.8 * modelData; height: Math.max(2, Math.round(slab.height * 0.1)); radius: height / 2; color: Theme.alpha(Theme.fg, 0.55) }
                }
            }
            Rectangle { anchors.fill: parent; radius: Math.max(2, gs.r - 2); color: "transparent"; border.width: 1; border.color: Theme.alpha("white", 0.15 + 0.5 * Math.min(1, gs.v.specular_intensity ?? 1)) }
        }
        Rectangle { id: slabMask; x: slab.x; y: slab.y; width: slab.width; height: slab.height; radius: Math.max(2, gs.r - 2); visible: false; layer.enabled: true }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: gs.r; visible: false; layer.enabled: true }
}
