import QtQuick
import QtQuick.Layouts

// Label for use inside bar chips. Every one fills the chip's full height with its text centered in that
// box, so text and icons of different fonts / sizes in different chips share one vertical center (with
// plain Labels each is only as tall as its own font, so a chip containing an 18px icon pushed its
// neighbours' text up or down).
Text {
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
    Layout.fillHeight: true
}
