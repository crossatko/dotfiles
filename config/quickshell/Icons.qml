pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's icon registry (DESIGN.md "Icons"): one name per meaning, so a glyph is chosen once and audited in one place.
// Rules: pick by meaning, not by look (a house for "home" or "dock", never a charging station for a vacuum dock); one glyph per
// meaning across bar, popups and Settings; a state has its own name (wifi / wifiOff, bellOn / bellOff); brands only for media
// services, browsers and OSes (Theme.brandFont). Adding one: check the code point in the installed Vadivam font
// (`fontTools`: the font files live outside this repo), add it here with the font's glyph name, then use `Icons.<name>`.
// `launcher/*.qml` cannot see root singletons and keep literal code points (Launcher.qml wires what they need).
// Also the index of Adwaita's symbolic icons (name -> svg path) for notification app icons: Qt's own lookup quietly falls
// back from "foo-symbolic" to a coloured "foo" from any theme, so it can't tell us whether a real symbolic icon exists;
// reading the files can.
Singleton {
    id: root
    // ---- named glyphs (DESIGN.md "Icons"): every glyph the shell draws, by meaning. Vadivam Icons (Theme.iconFont) unless noted;
    // generated from the font tables (fontTools): each code point exists in the installed font. Pick by meaning, never by look.
    readonly property string home: "\ue1b2"   // house
    readonly property string homeAssistant: "\ue49b"   // house-wifi
    readonly property string lightOn: "\ue0f5"   // lightbulb
    readonly property string lightbulb: "\ue2d5"   // lightbulb-off
    readonly property string ai: "\ue0e4"   // sparkles
    readonly property string cpu: "\ue0b5"   // cpu
    readonly property string memory: "\ue50f"   // memory-stick
    readonly property string vm: "\ue0d3"   // monitor
    readonly property string monitor: "\ue0d3"   // monitor
    readonly property string desktop: "\ue0d3"   // monitor (the desktop clock; the lock clock is Icons.lock)
    readonly property string caffeineOn: "\ue172"   // coffee
    readonly property string caffeineOff: "\ue172"   // coffee
    readonly property string recording: "\ue128"   // video
    readonly property string workspaces: "\ue0f4"   // layout-grid
    readonly property string controlCenter: "\ue113"   // sliders-horizontal
    readonly property string menu: "\ue0d0"   // menu
    readonly property string calendar: "\ue130"   // calendar-days
    readonly property string calendarPlain: "\ue0aa"   // calendar
    readonly property string clock: "\ue16a"   // clock
    readonly property string bell: "\ue09b"   // bell
    readonly property string bellOn: "\ue0a2"   // bell-ring
    readonly property string bellOff: "\ue0a0"   // bell-off
    readonly property string volumeHigh: "\ue12b"   // volume-2
    readonly property string volumeLow: "\ue12a"   // volume-1
    readonly property string volumeOff: "\ue129"   // volume
    readonly property string volumeMuted: "\ue1d0"   // volume-x
    readonly property string mic: "\ue10f"   // mic
    readonly property string micOff: "\ue52b"   // mic-off
    readonly property string headphones: "\ue48a"   // headphones
    readonly property string speaker: "\ue64e"   // speaker
    readonly property string earWaveform: "\ue3e3"   // ear
    readonly property string music: "\ue229"   // eighth-notes
    readonly property string wifi: "\ue117"   // wifi
    readonly property string wifiFair: "\ue757"   // wifi-high
    readonly property string wifiWeak: "\ue759"   // wifi-low
    readonly property string wifiOff: "\ue146"   // wifi-off
    readonly property string ethernet: "\ue3f2"   // ethernet-port
    readonly property string bluetooth: "\ue148"   // bluetooth
    readonly property string shield: "\ue623"   // shield-half
    readonly property string globe: "\ue0c2"   // globe
    readonly property string locationDot: "\ue10e"   // map-pin
    readonly property string link: "\ue0cb"   // link
    readonly property string linkOff: "\ue71e"   // unlink
    readonly property string plug: "\ue13f"   // plug
    readonly property string sitemap: "\ue111"   // network
    readonly property string play: "\ue0d7"   // play
    readonly property string pause: "\ue0fb"   // pause
    readonly property string stop: "\ue0e5"   // square
    readonly property string prev: "\ue640"   // skip-back
    readonly property string next: "\ue1ad"   // skip-forward
    readonly property string seekBack: "\ue5e0"   // rewind
    readonly property string seekForward: "\ue3fb"   // fast-forward
    readonly property string circlePlay: "\ue22f"   // circle-play
    readonly property string shuffle: "\ue1d7"   // shuffle
    readonly property string repeat: "\ue1ab"   // repeat
    readonly property string film: "\ue1e7"   // film
    readonly property string tv: "\ue1cb"   // tv
    readonly property string video: "\ue128"   // video
    readonly property string fileVideo: "\ue41d"   // file-video-camera
    readonly property string image: "\ue0c8"   // image
    readonly property string camera: "\ue105"   // camera
    readonly property string listUl: "\ue0cc"   // list
    readonly property string check: "\ue0ab"   // check
    readonly property string xmark: "\ue0ee"   // x
    readonly property string plus: "\ue0d8"   // plus
    readonly property string minus: "\ue0d2"   // minus
    readonly property string ellipsis: "\ue135"   // ellipsis
    readonly property string circle: "\ue0b1"   // circle
    readonly property string circleDot: "\ue19f"   // circle-dot
    readonly property string chevronDown: "\ue0ac"   // chevron-down
    readonly property string chevronUp: "\ue0af"   // chevron-up
    readonly property string chevronLeft: "\ue0ad"   // chevron-left
    readonly property string chevronRight: "\ue0ae"   // chevron-right
    readonly property string arrowRight: "\ue04e"   // arrow-right
    readonly property string externalLink: "\ue0b8"   // external-link
    readonly property string grip: "\ue0c4"   // grip-vertical
    readonly property string squareCheck: "\ue221"   // square-check
    readonly property string square: "\ue0e5"   // square
    readonly property string eye: "\ue0b9"   // eye
    readonly property string eyeOff: "\ue0ba"   // eye-off
    readonly property string lock: "\ue0cd"   // lock
    readonly property string key: "\ue0f1"   // key
    readonly property string info: "\ue0c9"   // info
    readonly property string warning: "\ue101"   // triangle-alert
    readonly property string error: "\ue106"   // circle-alert
    readonly property string spinner: "\ue0f6"   // loader-circle
    readonly property string hourglass: "\ue20e"   // hourglass
    readonly property string copy: "\ue0b4"   // copy
    readonly property string search: "\ue0de"   // search
    readonly property string gear: "\ue0e1"   // settings
    readonly property string refresh: "\ue0da"   // refresh-cw
    readonly property string retry: "\ue0dc"   // rotate-cw
    readonly property string undo: "\ue0db"   // rotate-ccw
    readonly property string arrowsRotate: "\ue0da"   // refresh-cw
    readonly property string arrowRotateRight: "\ue0dc"   // rotate-cw
    readonly property string user: "\ue0ec"   // user
    readonly property string sun: "\ue0e7"   // sun
    readonly property string moon: "\ue0d4"   // moon
    readonly property string palette: "\ue0d5"   // palette
    readonly property string layerGroup: "\ue0ca"   // layers
    readonly property string tableColumns: "\ue173"   // columns-2
    readonly property string download: "\ue0b7"   // download
    readonly property string trash: "\ue100"   // trash
    readonly property string folder: "\ue0bd"   // folder
    readonly property string folderOpen: "\ue0be"   // folder-open
    readonly property string terminal: "\ue0e8"   // terminal
    readonly property string code: "\ue0b3"   // code
    readonly property string power: "\ue126"   // power
    readonly property string outlet: "\ue5ac"   // plug-2 (a mains switch / smart plug)
    readonly property string logout: "\ue0ce"   // log-out
    readonly property string logoutAlt: "\ue0ce"   // log-out
    readonly property string rocket: "\ue0fc"   // rocket
    readonly property string cube: "\ue104"   // box
    readonly property string thumbtack: "\ue125"   // pin
    readonly property string keyboard: "\ue120"   // keyboard
    readonly property string gamepad: "\ue265"   // gamepad-2
    readonly property string mouse: "\ue54a"   // mouse
    readonly property string mobile: "\ue114"   // smartphone
    readonly property string laptop: "\ue1ed"   // laptop
    readonly property string printer: "\ue245"   // printer
    readonly property string calculator: "\ue14b"   // calculator
    readonly property string clipboard: "\ue131"   // clipboard
    readonly property string faceSmile: "\ue1fd"   // face-slightly-smiling
    readonly property string hardDrive: "\ue0c5"   // hard-drive
    readonly property string compactDisc: "\ue3ce"   // disc-3
    readonly property string penToSquare: "\ue142"   // square-pen
    readonly property string tag: "\ue0ff"   // tag
    readonly property string windowMaximize: "\ue02e"   // app-window
    readonly property string crop: "\ue3ac"   // crop
    readonly property string scroll: "\ue140"   // scroll
    readonly property string wand: "\ue252"   // wand-sparkles
    readonly property string batteryFull: "\ue08c"   // battery-full
    readonly property string batteryThreeQuarters: "\ue08e"   // battery-medium
    readonly property string batteryHalf: "\ue08e"   // battery-medium
    readonly property string batteryQuarter: "\ue08d"   // battery-low
    readonly property string batteryEmpty: "\ue08a"   // battery
    readonly property string batteryBolt: "\ue08b"   // battery-charging
    readonly property string bolt: "\ue22b"   // bolt
    readonly property string dock: "\ue1b2"   // house
    readonly property string vacuum: "\ue5e4"   // robot-vacuum
    readonly property string toggleOn: "\ue6ef"   // toggle-right
    readonly property string toggleOff: "\ue6ee"   // toggle-left
    readonly property string fire: "\ue137"   // flame
    readonly property string snowflake: "\ue2b8"   // snowflake
    readonly property string airConditioner: "\ue005"   // air-vent
    readonly property string fan: "\ue3fa"   // fan
    readonly property string blinds: "\ue2d4"   // blinds
    readonly property string blindsOpen: "\ue2d4"   // blinds
    // brand marks (Theme.brandFont, Font Awesome 7 Brands): media services, browsers, OSes
    readonly property string spotify: "\uf1bc"   // spotify
    readonly property string youtube: "\uf167"   // youtube
    readonly property string twitch: "\uf1e8"   // twitch
    readonly property string soundcloud: "\uf1be"   // soundcloud
    readonly property string deezer: "\ue077"   // deezer
    readonly property string tidal: "\ue7dc"   // tidal
    readonly property string apple: "\uf179"   // apple
    readonly property string bandcamp: "\uf2d5"   // bandcamp
    readonly property string vimeo: "\uf40a"   // vimeo
    readonly property string mixcloud: "\uf289"   // mixcloud
    readonly property string lastfm: "\uf202"   // lastfm
    readonly property string pandora: "\ue7da"   // pandora
    readonly property string tiktok: "\ue07b"   // tiktok
    readonly property string reddit: "\uf1a1"   // reddit
    readonly property string brave: "\ue63c"   // brave
    readonly property string firefox: "\uf269"   // firefox
    readonly property string chrome: "\uf268"   // chrome
    readonly property string edge: "\uf282"   // edge
    readonly property string linux: "\uf17c"   // linux
    readonly property string android: "\uf17b"   // android
    readonly property string windows: "\uf17a"   // windows
    readonly property string bluetoothB: "\uf294"   // bluetooth-b


    // state glyphs
    // speaker for a volume level: xmark when muted, then off / low / high
    function volumeGlyph(muted, v) { return muted ? volumeMuted : v < 0.01 ? volumeOff : v < 0.5 ? volumeLow : volumeHigh }
    // Wi-Fi signal strength 0..1 -> three bars / two / one
    function wifiGlyph(s) { return s > 0.66 ? wifi : s > 0.33 ? wifiFair : wifiWeak }
    // battery level 0..100 (charging = bolt)
    function batteryGlyph(p, charging) {
        return charging ? batteryBolt : p >= 88 ? batteryFull : p >= 63 ? batteryThreeQuarters : p >= 38 ? batteryHalf : p >= 13 ? batteryQuarter : batteryEmpty
    }

    property var symbolic: ({})
    Process {
        running: true
        command: ["sh", "-c", "find /usr/share/icons/Adwaita/symbolic -name '*-symbolic.svg' -printf '%f\\t%p\\n' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const l of text.split("\n")) {
                    const [f, p] = l.split("\t")
                    if (f && p) m[f.replace(/-symbolic\.svg$/, "")] = p
                }
                root.symbolic = m
            }
        }
    }
}
