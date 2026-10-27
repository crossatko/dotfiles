import QtQuick

// One wallpaper image as the desktop shows it: hyprpaper's fit modes (cover = centred crop, contain = letterboxed,
// fill = stretched, tile = natural size repeated), decoded at the output's PHYSICAL pixel size = item size x `pixelScale`
// (the monitor's scale, Hyprland's: Qt does not apply the fractional device pixel ratio to sourceSize, so a 1.25
// monitor decoded at its logical size came out blurred; measured pixel-exact this way), so a 4K file on a 1440p
// monitor decodes at 1440p (cover: scaled to cover, the overflow is cropped when drawn); nothing before the size is
// known. An image SMALLER than that (`imageW` / `imageH` from theme.py's header read) decodes at its own size and the
// GPU scales it up: with PreserveAspectCrop Qt would otherwise decode it up to the screen (a 640x360 file cost a
// 1600x900 / 2276x1280 buffer, measured). Off the GUI thread, keeping the previous image on screen while a new one loads (retainWhileLoading).
// WallpaperView cross-fades two.
Image {
    id: img
    property string path: ""
    property string fit: "cover"
    property real pixelScale: 1            // physical px per item px
    readonly property real k: pixelScale > 0 ? pixelScale : 1
    property int imageW: 0                 // the file's own size, 0 = unknown
    property int imageH: 0
    readonly property real pw: width * k   // physical px
    readonly property real ph: height * k
    // decode scale the fit needs: cover = the larger ratio, contain = the smaller, fill = each axis (smaller one counts)
    readonly property real need: imageW <= 0 || imageH <= 0 ? 0
        : fit === "contain" ? Math.min(pw / imageW, ph / imageH) : fit === "fill" ? Math.min(pw / imageW, ph / imageH)
        : Math.max(pw / imageW, ph / imageH)
    readonly property bool atOwnSize: fit === "tile" || need >= 1
    readonly property bool sized: width > 0 && height > 0
    // per path segment, so "#", "?" or "%" in a file name stay part of the path
    source: path !== "" && sized ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""
    fillMode: fit === "contain" ? Image.PreserveAspectFit : fit === "fill" ? Image.Stretch : fit === "tile" ? Image.Tile : Image.PreserveAspectCrop
    sourceSize: atOwnSize || !sized ? undefined : Qt.size(Math.round(pw), Math.round(ph))
    asynchronous: true
    retainWhileLoading: true
    cache: true          // the same url + size + fill elsewhere in the shell = one decode
    smooth: true         // decoded at (about) the output's size: no mipmaps needed
    mipmap: false
}
