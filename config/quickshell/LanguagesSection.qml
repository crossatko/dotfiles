pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "launcher/js/DictLangs.js" as D

// Settings > Voice > Languages: the languages you dictate in (PttPrefs.languages, ptt.json), as removable chips and a
// search field to add more (LanguagePicker over whisper's languages). Each language gets its own push-to-talk key
// (PttKeysSection) and filler word list; every language but English also a key that types it as English. Czech and
// English until changed (a long list folds, AdvancedFold). Adding keeps the languages and their keys as they are. Removing a language keeps its keys stored (no bind is made for it); adding it again brings them back.
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Languages"
        InfoTip { text: "The languages you dictate in. Each gets its own push-to-talk key, and a key that types it as English (whisper can only translate into English). The Auto key works with or without any: it detects the language when you start talking, among these when there are any." }
    }
    SettingRow {
        title: "My languages"
        titleWidth: sec.titleWidth
        titleTopAt: 15
        ColumnLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 100     // the width is the row's: many chips wrap, never widen the page
            spacing: Theme.gapRow
            AdvancedFold {
                objectName: "fold-languages"
                visible: PttPrefs.languages.length > 0
                label: PttPrefs.languages.length + (PttPrefs.languages.length === 1 ? " language" : " languages")
                count: PttPrefs.languages.length
                bodySpacing: Theme.gapRow
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.gapTight
                    Repeater {
                        model: PttPrefs.languages
                        WordChip {
                            id: wc
                            required property string modelData
                            text: D.name(wc.modelData)
                            onRemoved: PttPrefs.removeLanguage(wc.modelData)
                        }
                    }
                }
            }
            Label {
                visible: PttPrefs.languages.length === 0
                text: "None: only the Auto key is available"
                color: Theme.muted; font.pixelSize: Theme.fontCaption
            }
            LanguagePicker {
                added: PttPrefs.languages
                onPicked: code => PttPrefs.addLanguage(code)
            }
        }
    }
}
