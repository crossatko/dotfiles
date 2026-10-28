import QtQuick
import QtQuick.Layouts

// Why a Settings section is dimmed: an eye-slash "Off" (e.g. no clock on the monitor picked in the MonitorSection).
// Goes into a SectionHead's trailing slot; bind `visible`.
RowLayout {
    spacing: Theme.gapTight
    Icon { text: Icons.eyeOff; font.pixelSize: Theme.iconSm; color: Theme.muted }
    Label { text: "Off"; font.pixelSize: Theme.fontCaption; color: Theme.muted }
}
