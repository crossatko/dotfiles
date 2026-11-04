import QtQuick
import QtQuick.Layouts

// Settings > Diacritics > Ignored windows: the window classes where the key does nothing (terminals: a key must never
// land in a shell). A WordListEditor over DiacriticsPrefs.ignoredClasses (matched case-insensitively) and Restore defaults
// (dim while the list is the default). Find a class with `hyprctl clients`.
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Ignored windows"
        detail: DiacriticsPrefs.overridden("ignored_classes") ? "edited" : ""
        InfoTip { text: "In a window of one of these classes the key does nothing and the pill says it is not supported. Case does not matter. The class of a window is the one `hyprctl clients` shows." }
    }
    AdvancedFold {
        objectName: "fold-diac-classes"
        label: DiacriticsPrefs.ignoredClasses.length + (DiacriticsPrefs.ignoredClasses.length === 1 ? " window class" : " window classes")
        count: DiacriticsPrefs.ignoredClasses.length
        WordListEditor {
            titleWidth: sec.titleWidth
            lang: "all"; ns: "diac-class"
            words: DiacriticsPrefs.ignoredClasses
            addFn: t => DiacriticsPrefs.addClass(t)
            removeFn: c => DiacriticsPrefs.removeClass(c)
            placeholder: "Add a window class"
            emptyText: "No ignored windows: the key works everywhere"
            maxLen: DiacriticsPrefs.maxClassLen
        }
    }
    SettingRow {
        titleWidth: sec.titleWidth
        Btn {
            objectName: "btn-diac-classes-restore"
            text: "Restore defaults"
            implicitHeight: 26
            outerRadius: Theme.radiusPage; inset: 9
            enabledLook: DiacriticsPrefs.overridden("ignored_classes")
            onClicked: if (DiacriticsPrefs.overridden("ignored_classes")) DiacriticsPrefs.restoreClasses()
        }
        Item { Layout.fillWidth: true }
    }
}
