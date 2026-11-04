import QtQuick

// Dithered "swoosh" level meter (dictation pill): a flowing two-strand ribbon drawn as a dot grid (shaders/dotswoosh.frag),
// driven by a live input level. Optional dot-matrix labels at the left / right end sit in the ribbon's own grid
// (`leftText` / `rightText`, A-Z, 3x5 glyphs; the ribbon runs between them, never under them). `error` = one flat
// dotted line in `errorColor`, no labels. Colour runs `colorLeft` -> `colorRight` along the ribbon.
// Input: `level` 0..1 (smoothed here, rises fast, falls slower), or `levels` (up to 16 recent
// values 0..1, oldest first, spread across the ribbon: louder parts swell where they land) when the source has them.
// Level 0 (silence: the service sends a true 0 at the noise floor) still waves gently at `idleAmp` of the full swing;
// the swing grows linearly with the level up to 1.
// Cost: one fragment shader over the item; per frame only `time` and the smoothed level change (FrameAnimation,
// stopped while `running` is false or the item is hidden). Reduced motion (Motion.reduced): the ribbon stops
// flowing, its thickness still follows the level.
Item {
    id: sw
    property real level: 0
    property var levels: []
    property string leftText: ""
    property string rightText: ""
    property color colorLeft: Theme.accent
    property color colorRight: colorLeft
    property bool error: false
    property color errorColor: Theme.red
    property real labelAlpha: 1           // full: the label already sits at ~2:1 on a dark glass card over a mid-tone wallpaper
    property bool running: true
    // the grid: a dot every `pitch` px, `dotFrac` of the cell (3 px / 0.8)
    property real pitch: 3
    property real dotFrac: 0.8
    // swing of the ribbon at level 0, as a fraction of the full swing (level 1): alive, but clearly flat
    property real idleAmp: 0.2

    property real time: 0
    property real shownLevel: 0
    // the clock is a plain Timer, not a FrameAnimation / NumberAnimation: a running QML animation keeps Qt's animation
    // driver on, and then EVERY shell window re-renders each frame (measured: 5 windows at 60 fps); a Timer only dirties
    // this item, so only the pill's window draws
    property double last: 0
    Timer {
        interval: 16
        repeat: true
        running: sw.running && sw.visible
        onRunningChanged: sw.last = Date.now()
        onTriggered: {
            const now = Date.now(), dt = Math.min(0.1, (now - sw.last) / 1000)
            sw.last = now
            if (!Motion.reduced) sw.time = (sw.time + dt) % 3600
            // ~16 % of the way per 60 Hz frame, frame-rate independent
            sw.shownLevel += (Math.max(0, Math.min(1, sw.level)) - sw.shownLevel) * (1 - Math.pow(0.84, dt * 60))
        }
    }

    // 3x5 dot font, rows top to bottom ("1" = dot); M / N / W are wider
    readonly property var font: ({
        A: ["010", "101", "111", "101", "101"], B: ["110", "101", "110", "101", "110"], C: ["111", "100", "100", "100", "111"],
        D: ["110", "101", "101", "101", "110"], E: ["111", "100", "111", "100", "111"], F: ["111", "100", "111", "100", "100"],
        G: ["111", "100", "101", "101", "111"], H: ["101", "101", "111", "101", "101"], I: ["111", "010", "010", "010", "111"],
        J: ["001", "001", "001", "101", "111"], K: ["101", "101", "110", "101", "101"], L: ["100", "100", "100", "100", "111"],
        M: ["10001", "11011", "10101", "10001", "10001"], N: ["1001", "1101", "1011", "1001", "1001"],
        O: ["111", "101", "101", "101", "111"], P: ["111", "101", "111", "100", "100"], Q: ["111", "101", "101", "111", "001"],
        R: ["111", "101", "110", "101", "101"], S: ["111", "100", "111", "001", "111"], T: ["111", "010", "010", "010", "010"],
        U: ["101", "101", "101", "101", "111"], V: ["101", "101", "101", "101", "010"], W: ["10001", "10001", "10101", "11011", "10001"],
        X: ["101", "101", "010", "101", "101"], Y: ["101", "101", "010", "010", "010"], Z: ["111", "001", "010", "100", "111"]
    })
    // text -> { v: 4 x 4 columns of 5 bits (shader layout), w: columns }; at most 16 columns, unknown characters skipped
    function encode(text) {
        const cols = []
        for (const ch of String(text).toUpperCase()) {
            const g = font[ch]
            if (!g) continue
            if (cols.length) cols.push(0)
            for (let x = 0; x < g[0].length; x++) {
                let bits = 0
                for (let y = 0; y < 5; y++) if (g[y][x] === "1") bits |= 1 << y
                cols.push(bits)
            }
        }
        cols.length = Math.min(cols.length, 16)
        const c = [0, 0, 0, 0]
        cols.forEach((b, i) => c[i >> 2] += b * Math.pow(32, i & 3))
        return { v: Qt.vector4d(c[0], c[1], c[2], c[3]), w: cols.length }
    }
    readonly property var labL: encode(error ? "" : leftText)
    readonly property var labR: encode(error ? "" : rightText)
    readonly property var hist: {
        const a = Array.isArray(levels) ? levels.slice(-16).map(v => Math.max(0, Math.min(1, Number(v) || 0))) : []
        const h = a.concat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).slice(0, 16)
        return { n: a.length, v: [0, 4, 8, 12].map(i => Qt.vector4d(h[i], h[i + 1], h[i + 2], h[i + 3])) }
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("DotSwoosh shader failed:", log)
        readonly property size itemSize: Qt.size(width, height)
        readonly property real pitch: sw.pitch
        readonly property real dotFrac: sw.dotFrac
        readonly property real time: sw.time
        readonly property real level: sw.shownLevel
        readonly property real histN: sw.hist.n
        readonly property vector4d hist0: sw.hist.v[0]
        readonly property vector4d hist1: sw.hist.v[1]
        readonly property vector4d hist2: sw.hist.v[2]
        readonly property vector4d hist3: sw.hist.v[3]
        readonly property color colA: sw.colorLeft
        readonly property color colB: sw.colorRight
        readonly property color errCol: sw.errorColor
        readonly property real error: sw.error ? 1 : 0
        readonly property vector4d labL: sw.labL.v
        readonly property real labLW: sw.labL.w
        readonly property vector4d labR: sw.labR.v
        readonly property real labRW: sw.labR.w
        readonly property real labAlpha: sw.labelAlpha
        readonly property real strand2Alpha: 0.6
        readonly property real idleAmp: sw.idleAmp
        fragmentShader: Qt.resolvedUrl("shaders/dotswoosh.frag.qsb")
    }
}
