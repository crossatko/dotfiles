pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// The desktop wallpaper (theme.toml wallpaper_backend = "quickshell", the default; Wallpaper.drawn): one window per
// monitor on the BACKGROUND layer (namespace qs-wallpaper), under everything else: a video wallpaper's mpvpaper and the
// desktop clock are on the bottom layer above it, so the still shown here is what is under the video. Full screen,
// no input, no keyboard, no exclusive zone, an empty blur region (the qs-.* blur rule must not blur behind an opaque
// wallpaper: a blur pass every frame a video plays above it), black where the image does not cover (contain).
// The window maps with its first decoded image (WallpaperView.ready): at shell start the compositor's background
// colour shows until then, never a black or half-drawn surface. Monitors come and go with Quickshell.screens.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
Scope {
    Variants {
        model: Wallpaper.drawn ? Quickshell.screens : []
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: view.ready
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qs-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            mask: Region {}
            BackgroundEffect.blurRegion: Region {}

            WallpaperView {
                id: view
                // the screen's size, not the window's: the window maps only once the image is loaded (and has no size before)
                width: win.modelData ? win.modelData.width : 0
                height: win.modelData ? win.modelData.height : 0
                screen: win.modelData
            }
        }
    }
}
