import QtQuick

// Round-dot renderer for a dot-matrix grid (DiacFont.js layout: { c, r, v, m, fv, fs, lf }): ONLY lit dots are drawn, the pitch is
// width / columns, a dot is 0.8 of the pitch. The item's height is rows x pitch. Set `grid` to a new object for every frame to draw.
// Layers, back to front: dark halos under the lit dots (legible on a bright backdrop), then, with `flare`, the accent flare
// (a radial halo about twice the mark, then the dot in `flareColor`; a mark with a live flare is drawn oversize), then the dots in `color` (`markColor` where m = 1), a dot pulsing toward the
// flare colour by its lf.
Item {
    id: dg
    property var grid: null
    property color color: "white"
    property color markColor: "white"
    property color flareColor: "white"
    property bool flare: false
    readonly property real cols: grid ? grid.c : 78
    readonly property real rows: grid ? grid.r : 13
    readonly property real pitch: width / cols
    implicitHeight: pitch * rows

    onGridChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    onMarkColorChanged: cv.requestPaint()
    onFlareColorChanged: cv.requestPaint()
    onFlareChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
        function rgb(c) { return [c.r * 255, c.g * 255, c.b * 255] }
        function mixc(a, b, k) { return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k] }
        function css(c, a) { return "rgba(" + (c[0] | 0) + "," + (c[1] | 0) + "," + (c[2] | 0) + "," + a + ")" }
        onPaint: {
            const ctx = getContext("2d"), g = dg.grid
            ctx.reset()
            if (!g) return
            const p = dg.pitch, rad = p * 0.8 / 2, W = g.c, H = g.r, n = W * H
            const a = rgb(dg.color), b = rgb(dg.markColor), fc = rgb(dg.flareColor)
            const lfc = mixc(fc, [255, 255, 255], 0.3)
            const dot = (x, y, r) => { ctx.beginPath(); ctx.arc(x * p + p / 2, y * p + p / 2, r, 0, 6.2832); ctx.fill() }
            for (let i = 0; i < n; i++) {             // 1: halos under the letters
                const v = g.v[i]
                if (v <= 0.03) continue
                ctx.fillStyle = "rgba(0,0,0," + (0.5 * Math.min(1, v)) + ")"
                dot(i % W, (i / W) | 0, rad * 1.7)
            }
            if (dg.flare) {
                for (let i = 0; i < n; i++) {         // 2a: the flare's glow: a bright accent halo about twice the mark's size
                    const v = g.fv[i]
                    if (v <= 0.04 || g.fs[i] >= 0.05) continue
                    const x = i % W * p + p / 2, y = ((i / W) | 0) * p + p / 2, R = rad * 9
                    const gr = ctx.createRadialGradient(x, y, 0, x, y, R)
                    gr.addColorStop(0, css(lfc, Math.min(1, 1.2 * v)))
                    gr.addColorStop(0.3, css(fc, 0.7 * v))
                    gr.addColorStop(0.65, css(fc, 0.25 * v))
                    gr.addColorStop(1, css(fc, 0))
                    ctx.fillStyle = gr
                    ctx.beginPath(); ctx.arc(x, y, R, 0, 6.2832); ctx.fill()
                }
                for (let i = 0; i < n; i++) {         // 2b: the flare dots under the mark
                    const v = g.fv[i]
                    if (v <= 0.03) continue
                    ctx.fillStyle = css(fc, Math.min(1, 0.3 + v))
                    dot(i % W, (i / W) | 0, rad * (1 + 0.9 * v))
                }
            }
            for (let i = 0; i < n; i++) {             // 3: letters and marks
                const v = g.v[i]
                if (v <= 0.03) continue
                let col = mixc(a, b, g.m[i])
                const lf = g.lf[i]
                if (lf > 0.02 && dg.flare) col = mixc(col, lfc, Math.min(1, lf))
                ctx.fillStyle = css(col, Math.min(1, 0.25 + v))
                // a new mark starts oversize (by its flare) and settles; the letter under it pulses once (lf)
                dot(i % W, (i / W) | 0, rad * (1 + 0.45 * lf + (g.m[i] > 0.5 && dg.flare ? 0.7 * g.fv[i] : 0)))
            }
        }
    }
}
