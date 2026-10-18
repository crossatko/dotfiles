import QtQuick
import Quickshell

// Measures where a string's glyphs actually put ink, by rasterising it once with the same font into an invisible
// Canvas and scanning the alpha. Font metrics (TextMetrics.tightBoundingRect) are rounded outward to whole pixels
// and ignore anti-aliasing, which left icons up to 1 px off. Result `ink` (px, x from the text origin, y from the
// baseline; edges are fractional: a half-covered edge column counts as half a pixel):
//   { ok, l, r, t, b, adv }   ok = false until the first paint (callers fall back to font metrics meanwhile).
// Re-measures whenever text/font change. Used by BarIcon (glyph placement) and BarLabel (side bearings for Chip).
// The Canvas image is backed at the window's devicePixelRatio and getImageData() returns raw device pixels from
// the top-left (a w x h request at scale 2 is the top-left quarter), so the scan runs over the whole device-pixel
// buffer and divides by `dpr`; `ink` is always in logical px, at the resolution the screen really renders.
Canvas {
    id: m
    property string text
    property string family
    property int weight: Font.Normal
    property real pixelSize: 13
    property var ink: ({ ok: false, l: 0, r: 0, t: 0, b: 0, adv: 0 })
    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1

    readonly property int pad: Math.ceil(pixelSize)
    width: Math.max(1, text.length) * Math.ceil(pixelSize * 1.5) + 2 * pad
    height: 3 * pad
    opacity: 0                       // never shown; Image target + Immediate still paints off-screen
    enabled: false
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onTextChanged: requestPaint()
    onFamilyChanged: requestPaint()
    onWeightChanged: requestPaint()
    onPixelSizeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onAvailableChanged: requestPaint()
    onDprChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (!text) { ink = { ok: false, l: 0, r: 0, t: 0, b: 0, adv: 0 }; return }
        ctx.font = weight + " " + pixelSize + "px '" + family + "'"
        ctx.fillStyle = "#ffffff"
        const ox = pad, oy = 2 * pad            // text origin / baseline in the canvas
        ctx.fillText(text, ox, oy)
        const k = dpr, w = Math.ceil(width * k), h = Math.ceil(height * k)
        const d = ctx.getImageData(0, 0, w, h).data
        const col = new Array(w).fill(0), row = new Array(h).fill(0)
        for (let y = 0; y < h; y++)
            for (let x = 0; x < w; x++) {
                const a = d[(y * w + x) * 4 + 3]
                if (a > col[x]) col[x] = a
                if (a > row[y]) row[y] = a
            }
        const th = 5   // ~2 % alpha: ignore rounding dust, keep faint anti-aliased edges
        let l = -1, r = -1, t = -1, b = -1
        for (let x = 0; x < w; x++) if (col[x] > th) { if (l < 0) l = x; r = x }
        for (let y = 0; y < h; y++) if (row[y] > th) { if (t < 0) t = y; b = y }
        ctx.clearRect(0, 0, width, height)
        if (l < 0) { ink = { ok: true, l: 0, r: 0, t: 0, b: 0, adv: ctx.measureText(text).width }; return }
        // fractional edges: an edge pixel covered to 30 % adds 0.3 device px of ink
        ink = {
            ok: true,
            l: (l + 1 - col[l] / 255) / k - ox,
            r: (r + col[r] / 255) / k - ox,
            t: (t + 1 - row[t] / 255) / k - oy,
            b: (b + row[b] / 255) / k - oy,
            adv: ctx.measureText(text).width
        }
    }
}
