pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One chip of MonitorSection (the monitor strip): a split chip. The BODY (wallpaper still in the monitor's real aspect,
// MonitorThumb; its model over the connector, the connector alone when it has no model; the PrimaryTag dot; an optional
// accent badge glyph `mark`, e.g. the palette source) picks the monitor (`clicked()`); on a page with a per-monitor
// on / off (`switchable`) the STATE CELL at its end (MonitorStateCell: eye = on here, eye-slash = off, behind a hairline)
// toggles it (`switched(want)`, never flipped here). Off = the body dims (still selectable, so its settings can be
// prepared). An L1 item: fill only; the selected look is the section's gliding marker (fill = selection, never on / off);
// `grouped` (linked to the selected one) = accent outline, no fill; `linkBadge` = a chain glyph after the name (linked to a
// chip on another row). `selectable: false` = the whole chip is the switch (same look, the body dims while off).
// The section sets `width` (equal chips); `naturalWidth` / `compactWidth` are what the chip would like / can live with.
Rectangle {
    id: chip
    property var screen: null
    property bool selected: false
    property bool selectable: true
    property bool grouped: false
    property bool linkBadge: false
    property bool focused: false            // keyboard cursor of a strip without selection (focus outline)
    property string mark: ""
    property string markTip: ""
    property string thumb: ""
    property bool showPrimary: true
    property bool switchable: false
    property bool on: true
    property bool switchEnabled: true
    property string switchTip: ""
    property string glyphOn: Icons.eye
    property string glyphOff: Icons.eyeOff
    signal clicked()
    signal switched(bool want)

    function flip() { if (switchable && switchEnabled) switched(!on) }

    readonly property int thumbH: 26                         // the still's height; width follows the monitor's aspect
    readonly property bool primary: showPrimary && screen !== null && Monitors.isPrimary(screen)
    readonly property bool off: switchable && !on
    readonly property string title: screen ? Monitors.title(screen) : ""
    readonly property string sub: screen && title !== screen.name ? screen.name : ""
    readonly property real cellW: Theme.padSm + (switchable ? cell.implicitWidth : 0)   // the body's right pad (+ the cell)
    readonly property real fixedW: Theme.padSm + thumbBox.implicitWidth + body.spacing + (primary ? body.spacing + tag.implicitWidth : 0)
        + (mark !== "" ? body.spacing + markIcon.implicitWidth : 0) + (linkBadge ? body.spacing + linkIcon.implicitWidth : 0) + cellW
    // what the chip would like (name and connector unelided) and the least it can live with (a few letters of the name)
    readonly property real naturalWidth: Math.ceil(fixedW + Math.max(titleText.implicitWidth, subText.implicitWidth) + slack)
    readonly property real compactWidth: Math.ceil(fixedW + minName)
    readonly property int minName: 28                        // least width of the name column before the strip overflows
    readonly property int slack: 2                           // text rounding: the labels never elide at the natural width

    objectName: "monitor-chip-" + (screen ? screen.name : "")
    implicitWidth: naturalWidth
    implicitHeight: Theme.rowH
    radius: Theme.radiusPage
    color: selected ? Theme.alpha(Theme.accent, 0) : glow.hovered ? Theme.itemHover : Theme.itemFill
    border.width: grouped || focused ? 1 : 0
    border.color: focused ? Theme.alpha(Theme.fg, 0.6) : Theme.alpha(Theme.accent, 0.5)
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Accessible.role: selectable ? Accessible.PageTab : Accessible.CheckBox
    Accessible.name: title
    Accessible.description: [markTip, switchTip].filter(t => t !== "").join(", ")
    Accessible.checked: selectable ? selected : on

    HoverGlow { id: glow; area: bodyArea; radius: chip.radius }
    PressFeedback { area: bodyArea }
    // unelided widths of the two lines (hidden copies of the labels below)
    Label { id: titleText; visible: false; text: chip.title; font.pixelSize: Theme.fontSmall }
    Label { id: subText; visible: false; text: chip.sub; font.pixelSize: Theme.fontCaption }
    // the body's click: select (or, as a switch, toggle); the cell has its own area
    MouseArea {
        id: bodyArea
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: cell.visible ? cell.left : parent.right }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.selectable ? chip.clicked() : chip.flip()
    }
    // hover: a cut name in full (as FitLabel) and the primary's word (its dot alone says nothing)
    TipBubble {
        anchors.fill: bodyArea; alignRight: false
        text: [titleLabel.truncated ? chip.title : "", chip.primary ? "Primary" : ""].filter(t => t !== "").join(" · ")
        shown: bodyArea.containsMouse
    }

    RowLayout {
        id: body
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: cell.visible ? cell.left : parent.right; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
        spacing: Theme.gapRow
        // the still, the name and the markers dim together while the monitor is off
        opacity: chip.off ? Theme.disabledOpacity : 1
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        MonitorThumb { id: thumbBox; screen: chip.screen; source: chip.thumb; h: chip.thumbH }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                id: titleLabel
                Layout.fillWidth: true
                text: chip.title
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSmall
                color: chip.selected ? Theme.fg : Theme.fgDim
                Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            }
            Label {
                visible: text !== ""
                Layout.fillWidth: true
                text: chip.sub
                elide: Text.ElideRight
                font.pixelSize: Theme.fontCaption
                color: Theme.muted
            }
        }
        PrimaryTag { id: tag; Layout.fillWidth: false; visible: chip.primary; compact: true }
        Icon { id: markIcon; visible: chip.mark !== ""; text: chip.mark; font.pixelSize: Theme.iconSm; color: Theme.accent }
        Icon { id: linkIcon; visible: chip.linkBadge; text: Icons.link; font.pixelSize: Theme.iconSm; color: Theme.accent }
    }
    MonitorStateCell {
        id: cell
        objectName: chip.objectName + "-switch"
        visible: chip.switchable
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        on: chip.on
        enabledLook: chip.switchEnabled
        tip: chip.switchTip
        glyphOn: chip.glyphOn
        glyphOff: chip.glyphOff
        radius: chip.radius
        divider: true
        onClicked: chip.flip()
    }
}
