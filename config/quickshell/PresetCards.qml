pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A row of visual option cards (the primary choice of a Settings section): one card per entry of `model`
// ({ id, name }), each with a small live preview (`preview`: a Component with a `preset` property, loaded once per
// card and given that entry's id) over its name: no captions, the preview explains. The card whose id equals `current` is
// outlined; when `current` matches none ("custom": the saved values are the user's own) a last "Custom" card shows
// selected instead, so nothing is lost until an option is picked. Cards share the width (minimum `minCardW`, wrapping
// into more rows on a narrow window). Keyboard: Tab focuses the row, Left / Right move, Space / Enter pick.
Item {
    id: pc
    property var model: []
    property var current: undefined
    property Component preview: null
    property real previewHeight: 64
    property real minCardW: 118          // four cards across at the 760 px window
    property string objectPrefix: "card"
    signal picked(string id)

    readonly property bool custom: !model.some(m => m.id === current)
    readonly property var entries: custom ? model.concat([{ id: "custom", name: "Custom", isCustom: true }]) : model
    // as many columns as fit; one fewer when that would leave a lone card on the last row (4 cards in 3 columns: 2 x 2
    // instead of 3 + 1, 5 in 4: 3 + 2 instead of 4 + 1)
    readonly property int fit: Math.max(1, Math.min(entries.length, Math.floor((width + gap) / (minCardW + gap))))
    readonly property int cols: fit > 2 && entries.length % fit === 1 && entries.length % (fit - 1) !== 1 ? fit - 1 : fit
    readonly property real gap: Theme.gapRow
    readonly property real cardW: (width - gap * (cols - 1)) / cols        // read by the page for a 16:9 preview height
    readonly property int rows: Math.ceil(entries.length / cols)
    readonly property real nameH: 20                                        // the name line under the preview
    readonly property real cardH: previewHeight + nameH + 2 * Theme.gapRow + Theme.controlGap   // preview, name, margins
    property int focusIdx: Math.max(0, entries.findIndex(e => e.id === current))

    implicitHeight: rows * cardH + (rows - 1) * gap
    activeFocusOnTab: true
    Keys.onLeftPressed: focusIdx = Math.max(0, focusIdx - 1)
    Keys.onRightPressed: focusIdx = Math.min(entries.length - 1, focusIdx + 1)
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            const en = entries[focusIdx]
            if (en && !en.isCustom) pc.picked(en.id)
            e.accepted = true
        }
    }

    Repeater {
        model: pc.entries
        Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property bool sel: modelData.isCustom ? pc.custom : modelData.id === pc.current
            readonly property bool focused: pc.activeFocus && pc.focusIdx === index
            objectName: pc.objectPrefix + "-" + modelData.id
            x: (index % pc.cols) * (pc.cardW + pc.gap)
            y: Math.floor(index / pc.cols) * (pc.cardH + pc.gap)
            width: Math.floor(pc.cardW)
            height: pc.cardH
            radius: Theme.radiusPage
            color: sel ? Theme.alpha(Theme.accent, 0.12) : cardArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)
            border.width: 1
            border.color: sel ? Theme.accentEdge : focused ? Theme.alpha(Theme.fg, 0.6) : Theme.edge
            Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checked: sel

            HoverGlow { area: cardArea; radius: card.radius }
            ColumnLayout {
                anchors { fill: parent; margins: Theme.gapRow }
                spacing: Theme.controlGap
                // the preview: a rounded box the component fills (its own content is clipped to the corners)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: pc.previewHeight
                    Loader {
                        id: pv
                        anchors.fill: parent
                        property string preset: card.modelData.id
                        active: pc.preview !== null
                        sourceComponent: pc.preview
                        onLoaded: if (item && item.preset !== undefined) item.preset = card.modelData.id   // qmllint disable missing-property
                    }
                    Rectangle { anchors.fill: parent; radius: Theme.inner(card.radius, Theme.gapRow); color: "transparent"; border.width: 1; border.color: Theme.edge }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.controlGap
                    Label { text: card.modelData.name; color: card.sel ? Theme.accent : Theme.fg; font.pixelSize: Theme.fontSmall; font.bold: card.sel; elide: Text.ElideRight; Layout.fillWidth: true }
                    Icon { visible: card.sel; text: Icons.check; font.pixelSize: Theme.iconSm; color: Theme.accent }   // tick on the picked card
                }
            }
            MouseArea {
                id: cardArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: card.modelData.isCustom ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: { pc.focusIdx = card.index; if (!card.modelData.isCustom) pc.picked(card.modelData.id) }
            }
            PressFeedback { area: cardArea; target: card }
        }
    }
}
