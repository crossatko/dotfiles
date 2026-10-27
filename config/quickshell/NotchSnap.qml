import QtQuick

// Magnetic notches (detents) of a track, shared by Slider and HaStrip (NotchTicks draws them).
// `notches`: values 0..1 of the track, each a number or { v, kind: "default" | "extra" }; a bare number is the
// default when it comes first, else an extra. The default is what a double-click resets to. `start` / `length` = the
// pixel travel of the handle centre (value v sits at start + v * length), `floor` = the lowest reachable value.
// Feel: while a pointer drags, a value within `capture` px of a notch snaps onto it and stays there until the pointer
// is `release` px away (sticky, never a trap); a wheel / arrow step stops on a notch it crosses; `jump` goes notch to
// notch (Shift + arrow). Each snap gives `pulse` (1 -> 0), the handle's small "click" (Motion.moveMs, none when reduced).
Item {
    id: ns
    property var notches: []
    property real floor: 0
    property real start: 0
    property real length: 100
    visible: false

    readonly property real captureShare: 0.02      // capture radius: 2 % of the travel ...
    readonly property real captureMin: 8           // ... but at least 8 px
    readonly property real releaseMin: 14          // leaving a notch takes this many px (and always more than capture)
    readonly property real eps: 0.0005

    readonly property var list: {
        const out = []
        const src = notches || []
        for (let i = 0; i < src.length; i++) {
            const n = src[i]
            const v = typeof n === "number" ? n : n ? n.v : NaN
            if (typeof v !== "number" || !isFinite(v) || v < floor - eps || v > 1 + eps) continue
            if (out.some(o => Math.abs(o.v - v) < eps)) continue
            const kind = typeof n === "number" ? (i === 0 ? "default" : "extra") : (n.kind === "default" ? "default" : "extra")
            out.push({ v: Math.max(0, Math.min(1, v)), kind: kind })
        }
        return out
    }
    readonly property real defaultValue: { const d = list.find(n => n.kind === "default"); return d ? d.v : -1 }
    readonly property real capture: Math.max(captureShare * length, captureMin)
    readonly property real release: Math.max(releaseMin, capture + 6)

    property int stuck: -1          // index in `list` the pointer is held on, -1 = free
    property real pulse: 0

    function pxOf(v) { return start + v * length }
    function free() { stuck = -1 }
    function click() {
        if (Motion.reduced || Motion.moveMs <= 0) { pulse = 0; return }
        pulseAnim.restart()
    }
    // pointer at `px` (track coordinates) whose plain value is `raw` -> the value to emit
    function snap(px, raw) {
        if (stuck >= 0 && stuck < list.length && Math.abs(px - pxOf(list[stuck].v)) <= release) return list[stuck].v
        stuck = -1
        let best = -1, bd = capture
        for (let i = 0; i < list.length; i++) {
            const d = Math.abs(px - pxOf(list[i].v))
            if (d <= bd) { best = i; bd = d }
        }
        if (best < 0) return raw
        stuck = best
        click()
        return list[best].v
    }
    // value + delta (clamped to floor..1), stopping on the first notch on the way
    function stepFrom(value, delta) {
        const to = Math.max(floor, Math.min(1, value + delta))
        let hit = -1
        for (const n of list) {
            const crossed = delta > 0 ? n.v > value + eps && n.v <= to + eps : n.v < value - eps && n.v >= to - eps
            if (crossed && (hit < 0 || Math.abs(n.v - value) < Math.abs(hit - value))) hit = n.v
        }
        if (hit < 0) return to
        click()
        return hit
    }
    // the next notch in direction `dir` (+1 / -1), else that end of the track
    function jump(value, dir) {
        let hit = -1
        for (const n of list) {
            const ahead = dir > 0 ? n.v > value + eps : n.v < value - eps
            if (ahead && (hit < 0 || Math.abs(n.v - value) < Math.abs(hit - value))) hit = n.v
        }
        if (hit < 0) return dir > 0 ? 1 : floor
        click()
        return hit
    }

    NumberAnimation { id: pulseAnim; target: ns; property: "pulse"; from: 1; to: 0; duration: Motion.moveMs; easing.type: Easing.OutCubic }
}
