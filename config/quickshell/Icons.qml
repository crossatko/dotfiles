pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's icon registry (DESIGN.md "Icons"): one name per meaning, so a glyph is chosen once and audited in one place.
// Rules: pick by meaning, not by look (a house for "home" or "dock", never a charging station for a vacuum dock); one glyph per
// meaning across bar, popups and Settings; a state has its own name (wifi / wifiOff, bellOn / bellOff); brands only for media
// services, browsers and OSes (Theme.brandFont). Adding one: check the code point in the installed Sharp Regular font
// (`fontTools`: the font files live outside this repo), add it here with the font's glyph name, then use `Icons.<name>`.
// `launcher/*.qml` cannot see root singletons and keep literal code points (Launcher.qml wires what they need).
// Also the index of Adwaita's symbolic icons (name -> svg path) for notification app icons: Qt's own lookup quietly falls
// back from "foo-symbolic" to a coloured "foo" from any theme, so it can't tell us whether a real symbolic icon exists;
// reading the files can.
Singleton {
    id: root
    // ---- named glyphs (DESIGN.md "Icons"): every glyph the shell draws, by meaning. Font Awesome 7 Sharp Regular unless noted;
    // generated from the font tables (fontTools): each code point exists in the installed font. Pick by meaning, never by look.
    readonly property string home: "\uf015"   // house
    readonly property string lightOn: "\uf672"   // lightbulb-on
    readonly property string lightbulb: "\uf0eb"   // lightbulb
    readonly property string ai: "\uf890"   // sparkles
    readonly property string cpu: "\uf2db"   // microchip
    readonly property string memory: "\uf538"   // memory
    readonly property string vm: "\uf108"   // desktop
    readonly property string monitor: "\uf390"   // desktop
    readonly property string caffeineOn: "\ue1f5"   // mug-tea-saucer
    readonly property string caffeineOff: "\uf0f4"   // mug-saucer
    readonly property string recording: "\uf03d"   // video
    readonly property string workspaces: "\uf00a"   // table-cells
    readonly property string controlCenter: "\uf1de"   // sliders
    readonly property string menu: "\uf0c9"   // bars
    readonly property string calendar: "\uf073"   // calendar-days
    readonly property string calendarPlain: "\uf133"   // calendar
    readonly property string clock: "\uf017"   // clock
    readonly property string bell: "\uf0f3"   // bell
    readonly property string bellOn: "\uf8fa"   // bell-on
    readonly property string bellOff: "\uf1f6"   // bell-slash
    readonly property string volumeHigh: "\uf028"   // volume-high
    readonly property string volumeLow: "\uf027"   // volume-low
    readonly property string volumeOff: "\uf026"   // volume-off
    readonly property string volumeMuted: "\uf6a9"   // volume-xmark
    readonly property string mic: "\uf130"   // microphone
    readonly property string micOff: "\uf131"   // microphone-slash
    readonly property string headphones: "\uf025"   // headphones
    readonly property string speaker: "\uf8df"   // speaker
    readonly property string earWaveform: "\ue75d"   // ear-waveform
    readonly property string music: "\uf001"   // music
    readonly property string wifi: "\uf1eb"   // wifi
    readonly property string wifiFair: "\uf6ab"   // wifi-fair
    readonly property string wifiWeak: "\uf6aa"   // wifi-weak
    readonly property string wifiOff: "\uf6ac"   // wifi-slash
    readonly property string ethernet: "\uf796"   // ethernet
    readonly property string bluetooth: "\uf293"   // bluetooth
    readonly property string shield: "\uf3ed"   // shield-halved
    readonly property string globe: "\uf0ac"   // globe
    readonly property string locationDot: "\uf3c5"   // location-dot
    readonly property string link: "\uf0c1"   // link
    readonly property string linkOff: "\uf127"   // link-slash
    readonly property string plug: "\uf1e6"   // plug
    readonly property string sitemap: "\uf0e8"   // sitemap
    readonly property string play: "\uf04b"   // play
    readonly property string pause: "\uf04c"   // pause
    readonly property string stop: "\uf04d"   // stop
    readonly property string prev: "\uf048"   // backward-step
    readonly property string next: "\uf051"   // forward-step
    readonly property string circlePlay: "\uf144"   // circle-play
    readonly property string shuffle: "\uf074"   // shuffle
    readonly property string repeat: "\uf363"   // repeat
    readonly property string film: "\uf008"   // film
    readonly property string tv: "\uf26c"   // tv
    readonly property string video: "\uf03d"   // video
    readonly property string fileVideo: "\uf1c8"   // file-video
    readonly property string image: "\uf03e"   // image
    readonly property string camera: "\uf030"   // camera
    readonly property string listUl: "\uf0ca"   // list-ul
    readonly property string check: "\uf00c"   // check
    readonly property string xmark: "\uf00d"   // xmark
    readonly property string plus: "\uf067"   // plus
    readonly property string minus: "\uf068"   // minus
    readonly property string ellipsis: "\uf141"   // ellipsis
    readonly property string circle: "\uf111"   // circle
    readonly property string circleDot: "\uf192"   // circle-dot
    readonly property string chevronDown: "\uf078"   // chevron-down
    readonly property string chevronUp: "\uf077"   // chevron-up
    readonly property string chevronLeft: "\uf053"   // chevron-left
    readonly property string chevronRight: "\uf054"   // chevron-right
    readonly property string arrowRight: "\uf061"   // arrow-right
    readonly property string externalLink: "\uf08e"   // arrow-up-right-from-square
    readonly property string grip: "\uf58e"   // grip-vertical
    readonly property string squareCheck: "\uf14a"   // square-check
    readonly property string square: "\uf0c8"   // square
    readonly property string eye: "\uf06e"   // eye
    readonly property string eyeOff: "\uf070"   // eye-slash
    readonly property string lock: "\uf023"   // lock
    readonly property string key: "\uf084"   // key
    readonly property string info: "\uf05a"   // circle-info
    readonly property string warning: "\uf071"   // triangle-exclamation
    readonly property string error: "\uf06a"   // circle-exclamation
    readonly property string spinner: "\uf110"   // spinner
    readonly property string hourglass: "\uf254"   // hourglass
    readonly property string copy: "\uf0c5"   // copy
    readonly property string search: "\uf002"   // magnifying-glass
    readonly property string gear: "\uf013"   // gear
    readonly property string refresh: "\uf2f1"   // rotate
    readonly property string retry: "\uf2f9"   // rotate-right
    readonly property string undo: "\uf2ea"   // rotate-left
    readonly property string arrowsRotate: "\uf021"   // arrows-rotate
    readonly property string arrowRotateRight: "\uf01e"   // arrow-rotate-right
    readonly property string user: "\uf007"   // user
    readonly property string sun: "\uf185"   // sun
    readonly property string moon: "\uf186"   // moon
    readonly property string palette: "\uf53f"   // palette
    readonly property string layerGroup: "\uf5fd"   // layer-group
    readonly property string tableColumns: "\uf0db"   // table-columns
    readonly property string download: "\uf019"   // download
    readonly property string trash: "\uf1f8"   // trash
    readonly property string folder: "\uf07b"   // folder
    readonly property string folderOpen: "\uf07c"   // folder-open
    readonly property string terminal: "\uf120"   // terminal
    readonly property string code: "\uf121"   // code
    readonly property string power: "\uf011"   // power-off
    readonly property string outlet: "\ue01c"   // outlet (a mains switch / smart plug)
    readonly property string logout: "\uf2f5"   // right-from-bracket
    readonly property string logoutAlt: "\uf08b"   // arrow-right-from-bracket
    readonly property string rocket: "\uf135"   // rocket
    readonly property string cube: "\uf1b2"   // cube
    readonly property string thumbtack: "\uf08d"   // thumbtack
    readonly property string keyboard: "\uf11c"   // keyboard
    readonly property string gamepad: "\uf11b"   // gamepad
    readonly property string mouse: "\uf8cc"   // computer-mouse
    readonly property string mobile: "\uf3cd"   // mobile-screen-button
    readonly property string laptop: "\uf109"   // laptop
    readonly property string printer: "\uf02f"   // print
    readonly property string calculator: "\uf1ec"   // calculator
    readonly property string clipboard: "\uf328"   // clipboard
    readonly property string faceSmile: "\uf118"   // face-smile
    readonly property string hardDrive: "\uf0a0"   // hard-drive
    readonly property string compactDisc: "\uf51f"   // compact-disc
    readonly property string penToSquare: "\uf044"   // pen-to-square
    readonly property string tag: "\uf02b"   // tag
    readonly property string windowMaximize: "\uf2d0"   // window-maximize
    readonly property string crop: "\uf125"   // crop
    readonly property string scroll: "\uf70e"   // scroll
    readonly property string wand: "\ue2ca"   // wand-magic-sparkles
    readonly property string batteryFull: "\uf240"   // battery-full
    readonly property string batteryThreeQuarters: "\uf241"   // battery-three-quarters
    readonly property string batteryHalf: "\uf242"   // battery-half
    readonly property string batteryQuarter: "\uf243"   // battery-quarter
    readonly property string batteryEmpty: "\uf244"   // battery-empty
    readonly property string batteryBolt: "\uf376"   // battery-bolt
    readonly property string bolt: "\uf0e7"   // bolt
    readonly property string dock: "\uf015"   // house
    readonly property string vacuum: "\ue04e"   // vacuum-robot
    readonly property string toggleOn: "\uf205"   // toggle-on
    readonly property string toggleOff: "\uf204"   // toggle-off
    readonly property string fire: "\uf06d"   // fire
    readonly property string snowflake: "\uf2dc"   // snowflake
    readonly property string airConditioner: "\uf8f4"   // air-conditioner
    readonly property string fan: "\uf863"   // fan
    readonly property string blinds: "\uf8fb"   // blinds
    readonly property string blindsOpen: "\uf8fc"   // blinds-open
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
