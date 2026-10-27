import QtQuick

// One glass character that can FORM (GlassReveal): GlassText whose glass inflates with `pop` (0 = not there, 1 = full;
// refraction, rim and highlights grow with it, a small scale 0.96 -> 1 from the baseline, opacity leading it). `land`
// runs it after `delay` ms over `ms` ms with a very soft settle (OutBack 0.5); `ms` 0 = at once. `presence` (0..1)
// fades the glass by its owner (the desktop clock while its backdrop is missing); 1 = no effect. Used by LockClock and
// DeskClockView so both clocks form the same way.
GlassText {
    id: ch
    property real pop: 1
    property real presence: 1
    strength: Math.max(0.001, pop * presence)
    opacity: Math.min(1, pop * 1.4) * Math.min(1, presence * 1.4)
    scale: 0.96 + 0.04 * pop
    transformOrigin: Item.Bottom
    function land(delay, ms) {
        landAnim.stop()
        if (ms <= 0) { pop = 1; return }
        pop = 0
        landDelay.duration = Math.max(0, delay)
        landStep.duration = ms
        landAnim.restart()
    }
    SequentialAnimation {
        id: landAnim
        PauseAnimation { id: landDelay; duration: 0 }
        NumberAnimation { id: landStep; target: ch; property: "pop"; from: 0; to: 1; duration: 0; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
    }
}
