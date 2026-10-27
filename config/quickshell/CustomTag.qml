import QtQuick

// The small "Custom" tag next to a preset choice whose saved values match no preset (ChoiceRow, PresetCards): the
// user's own values are in force and stay until a preset is picked; the details are under Customise…
Pill {
    text: "Custom"
    tint: Theme.accent2
    radius: Math.min(Theme.inner(Theme.radiusPage, 9), 6)
}
