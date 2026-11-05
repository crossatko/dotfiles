import QtQuick

// A hairline progress line (the reminder's elapsed time): a Meter a few px tall, the fill gliding over Motion.emphasisMs.
Meter {
    readonly property int hairPx: 3       // line height
    implicitHeight: hairPx
    animMs: Motion.emphasisMs
}
