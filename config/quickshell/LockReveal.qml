import QtQuick

// Lock -> desktop transition (shaders/lockreveal.frag): over `progress` 0..1 a glass ring expands from `centre` and
// reveals `snapshot` (the desktop as it was when the lock was taken) in place of `source` (the lock scene). Drawn only
// while `progress` > 0; the caller animates it and unlocks at 1.
ShaderEffect {
    id: r
    property Item source: null
    property Item snapshot: null
    property point centre: Qt.point(width / 2, height / 2)
    property real progress: 0
    visible: progress > 0 && source !== null && snapshot !== null
    fragmentShader: Qt.resolvedUrl("shaders/lockreveal.frag.qsb")
    property var lockScene: ShaderEffectSource { sourceItem: r.source; live: true; hideSource: r.visible }
    property size itemSize: Qt.size(width, height)
    property real maxRadius: Math.max(Math.hypot(centre.x, centre.y), Math.hypot(width - centre.x, centre.y),
                                      Math.hypot(centre.x, height - centre.y), Math.hypot(width - centre.x, height - centre.y))
    property real band: Math.min(width, height) * 0.08
    readonly property var gv: GlassTuneCtl.effective
    property point lightDir: Qt.point(Math.cos(gv.light_angle * Math.PI / 180), -Math.sin(gv.light_angle * Math.PI / 180))
}
