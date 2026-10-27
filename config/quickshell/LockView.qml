pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

// One lock surface (one per screen, Lock.qml): blurred wallpaper (or the paused / bursting video), the glass-lettered
// clock and the password field, nothing else. The password lives in Lock.qml (`password`), so every screen shows the
// same dots; the screen that has keyboard focus is the one being typed on. Look and motion: LockPrefs (Settings > Lock).
// `preview` (Settings > Lock, LockPreview): the same visuals with no keyboard focus, no input, no video and
// `previewDots` sample beads. Per screen (LockPrefs.clockOn, Settings > Lock "Screens"): the clock and date may be off;
// the password dots stay where they would be. Under the dots: the playback card (LockMedia) on the screens with the clock.
Item {
    id: view
    property string wallpaper: ""
    property string screenName: ""     // connector: the video wallpaper of that output (LockVideo)
    property bool authenticating: false
    property string failureMessage: ""
    property string password: ""
    property bool preview: false
    property int previewDots: 0
    onPreviewDotsChanged: if (preview) field.text = "x".repeat(previewDots)
    // the lock is up (every output covered). The surfaces exist before that: the entrance motion and the video's
    // opening burst start here, once per lock
    property bool engaged: false
    function engage() {
        revealAnim.stop()
        revealProgress = 0
        // the same ring closing over the desktop as the lock comes up: the snapshot covers the surface (no blank frames
        // while the wallpaper decodes), then the ring closes once the backdrop is there (closeWait)
        if (snap.status === Image.Ready && Theme.lockRevealMs > 0) { revealProgress = 1; closeWait.restart() }
        clockBox.form()
        if (LockPrefs.burstOnLock) video.burstWhenReady()
    }
    onEngagedChanged: if (engaged) engage()
    // unlock transition (Lock.qml): `snapshot` = this output's desktop as it was when the lock was taken (a file in
    // $XDG_RUNTIME_DIR); it is decoded but never drawn until `revealing` (after a correct password) runs LockReveal
    property string snapshot: ""
    // the desktop clock's clean rect (DeskClock.patches entry) when the snapshot still shows the clock: it fades out
    // over the snapshot once the lock is up (LockClockPatch)
    property var clockPatch: null
    property bool revealing: false
    property real revealProgress: 0
    onRevealingChanged: if (revealing && snap.status === Image.Ready) { closeAnim.stop(); revealAnim.restart() }
    NumberAnimation { id: revealAnim; target: view; property: "revealProgress"; from: 0; to: 1; duration: Theme.lockRevealMs; easing.type: Easing.InOutCubic }
    NumberAnimation { id: closeAnim; target: view; property: "revealProgress"; from: 1; to: 0; duration: Theme.lockRevealMs; easing.type: Easing.OutCubic }   // moving from the first frame
    Timer {
        id: closeWait
        interval: 16; repeat: true
        property int left: 40
        onRunningChanged: if (running) left = 40
        onTriggered: if (view.backdropReady || --left <= 0) { stop(); closeAnim.restart() }
    }
    // this surface's screen (by connector): whether it shows the clock (LockPrefs.hidden)
    readonly property var screen: Quickshell.screens.find(s => s && s.name === screenName) ?? null
    readonly property bool clockShown: LockPrefs.clockOn(screen)
    signal passwordEdited(string p)
    signal submit(string p)

    readonly property real unit: Math.min(width, height)
    property bool wallReady: false
    readonly property bool backdropReady: wallReady || video.ready
    // what this surface's backdrop is made of (Lock.status(), `qs ipc call lock status`): file names only
    function demo() { clockBox.demo() }    // Settings preview: one minute ahead and back (the morph)
    function wallState() {
        const base = p => p ? String(p).replace(/^.*\//, "") : ""
        return { screen: screenName, still: base(wallpaper), stillReady: wallReady, video: base(video.info ? video.info.file : ""),
                 videoReady: video.ready, playing: video.playing, shows: video.ready ? "video" : wallReady ? "still" : "none" }
    }

    // ---- backdrop: wallpaper (or video), blurred and dimmed, kept as a static texture while nothing moves ----
    // Everything up to the blur is `bleed` px larger than the screen on each side and cropped afterwards, so the blur
    // does not pull transparent black in at the screen edges.
    readonly property int bleed: LockPrefs.blurMax   // >= the blur radius; = Lock.blurBleed (its pre-decoded stills have this margin)
    readonly property rect inner: Qt.rect(bleed, bleed, width, height)
    readonly property Item scene: video.ready ? video.output : stage
    Connections { target: video; function onReadyChanged() { settle.restart() } }
    // a changed blur / dim (Settings > Lock, dragged live): re-render the frozen backdrop for a moment, then freeze again
    Connections {
        target: LockPrefs
        function onBlurChanged() { settle.restart() }
        function onDimChanged() { settle.restart() }
    }
    Timer { id: settle; property bool done: false; interval: 600; onTriggered: done = true; onRunningChanged: if (running) done = false }

    // ---- clock (forms when the lock is up, LockClock.form) + password field ----
    Component.onCompleted: {
        if (preview) field.text = "x".repeat(previewDots)
        else field.focusField()
        if (engaged) engage()
    }
    Timer { interval: 300; running: !view.preview; onTriggered: field.focusField() }
    // everything drawn, in one item: LockReveal reads it as a texture for the unlock transition
    Item {
        id: content
        anchors.fill: parent
        LockVideo {
            id: video
            x: -view.bleed; y: -view.bleed
            width: view.width + 2 * view.bleed; height: view.height + 2 * view.bleed
            connector: view.preview ? "" : view.screenName
            z: -5           // drawn (under the blurred backdrop, which covers it): an invisible VideoOutput gets no frames
        }
        // what is blurred: the still, or the video once it has a frame (a paused video = a static texture). The video goes
        // in as its own layer: a ShaderEffectSource of the VideoOutput inside another layer stayed empty.
        Item {
            id: stage
            x: -view.bleed; y: -view.bleed
            width: view.width + 2 * view.bleed; height: view.height + 2 * view.bleed
            visible: false
            layer.enabled: true
            layer.smooth: true      // sampled bent by the glass
            Image {
                anchors.fill: parent
                // only at the real size (the surface is 0 x 0 at creation): one decode, a cache hit on Lock.qml's pre-decoded copy
                source: view.wallpaper !== "" && view.width > 0 ? "file://" + view.wallpaper : ""
                sourceSize: Qt.size(stage.width, stage.height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: false     // Lock.qml pre-decodes it at the same url / size: a cache hit, there on the first frame
                onStatusChanged: if (status === Image.Ready) { view.wallReady = true; settle.restart() }
            }
        }
        // dimmed by a black veil (x (1 - dim), as glasstext.frag dims the sharp scene), not MultiEffect brightness: that
        // SUBTRACTS dim, and a dark wallpaper (a play-once clip's held frame, blurred) went entirely black at 0.5
        Item {
            id: blurred
            x: -view.bleed; y: -view.bleed
            width: view.width + 2 * view.bleed; height: view.height + 2 * view.bleed
            visible: false
            MultiEffect {
                anchors.fill: parent
                source: view.scene
                autoPaddingEnabled: false
                blurEnabled: LockPrefs.blur > 0
                blur: 1.0
                blurMax: Math.max(1, LockPrefs.blur)
                saturation: -0.1
            }
            Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.lockDim }
        }
        ShaderEffectSource {
            id: backdropTex
            anchors.fill: parent
            sourceItem: blurred
            sourceRect: view.inner
            live: !settle.done || video.playing   // the blur chain needs a few frames; after that (and while the video rests) a frozen texture
            hideSource: false
        }
        Rectangle { anchors.fill: parent; color: Theme.bg; z: -10 }
        LockClock {
            id: clockBox
            x: Math.round((view.width - width) / 2)
            y: Math.round(view.height * 0.42 - height / 2)
            pixelSize: Math.round(view.unit * LockPrefs.clockSize)
            maxWidth: view.width - 2 * Theme.edgeGap     // seconds: the digits shrink only if the clock would not fit
            visible: view.clockShown                     // off: the dots keep their place
            backdrop: backdropTex
            sharpBackdrop: view.scene       // bleed px larger than the screen (a cropping ShaderEffectSource of it stayed empty)
            sharpInset: view.bleed
            origin: Qt.point(x, y)
            backdropSize: Qt.size(view.width, view.height)
        }
        LockField {
            id: field
            width: Math.min(view.width - 2 * Theme.edgeGap, clockBox.width)
            x: Math.round((view.width - width) / 2)
            y: Math.round(clockBox.y + clockBox.height + view.unit * 0.05)
            beadSize: Math.round(clockBox.pixelSize * LockPrefs.dotSize)
            enabled: !view.preview
            busy: view.authenticating
            backdrop: backdropTex
            sharpBackdrop: view.scene       // bleed px larger than the screen (a cropping ShaderEffectSource of it stayed empty)
            sharpInset: view.bleed
            origin: Qt.point(x, y)
            backdropSize: Qt.size(view.width, view.height)
            property int submitted: 0
            onTextChanged: if (text !== view.password && !view.preview) { if (LockPrefs.burstOnType) video.burst(); view.passwordEdited(text) }
            onAccepted: { submitted = text.length; if (LockPrefs.burstOnSubmit) video.burst(); view.submit(text) }
            onCancelled: text = ""
            Connections {
                target: view
                function onPasswordChanged() { if (!view.preview && field.text !== view.password) field.text = view.password }
                function onFailureMessageChanged() { if (view.failureMessage !== "") field.reject(field.submitted) }
            }
        }
        LockMedia {
            id: media
            width: Math.min(view.width - 2 * Theme.edgeGap, Math.round(view.unit * 0.42))
            x: Math.round((view.width - width) / 2)
            y: Math.round(field.y + field.height + view.unit * 0.04)
            shown: LockPrefs.mediaCard && view.clockShown
            sample: view.preview
            dim: Theme.lockDim
            backdrop: backdropTex
            sharpBackdrop: view.scene
            sharpInset: view.bleed
            origin: Qt.point(x, y)
            backdropSize: Qt.size(view.width, view.height)
        }
    }
    Image {
        id: snap
        anchors.fill: parent
        visible: false
        source: view.snapshot
        cache: false
        asynchronous: false    // there on the first frame: it covers the surface while the lock comes up
        // from the first frame until the lock is up (engage() then closes the ring over it): no blank / half-drawn frames
        onStatusChanged: if (status === Image.Ready && !view.engaged && !view.revealing && Theme.lockRevealMs > 0) view.revealProgress = 1
    }
    LockClockPatch {
        id: snapNoClock
        anchors.fill: parent
        snapshot: snap
        patch: view.clockPatch
        fading: view.engaged || view.revealing
    }
    LockReveal {
        anchors.fill: parent
        source: content
        snapshot: snapNoClock.active ? snapNoClock : snap
        progress: view.revealProgress
        centre: Qt.point(field.x + field.width / 2, field.y + field.height / 2)
    }
}
