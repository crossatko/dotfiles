.pragma library

// Font Awesome 7 Sharp (Regular) glyph for a standard freedesktop icon name (NotifIcon draws it with the shell's
// Icon). "" = not a standard name: app-specific names keep their own icon, unknown ones the symbolic Adwaita one.
// Codepoints were dumped from the installed font (fontTools cmap), not written from memory.

var EXACT = {
    "dialog-information": 0xf05a, "dialog-info": 0xf05a, "dialog-warning": 0xf071, "dialog-error": 0xf057,
    "dialog-question": 0xf059, "dialog-password": 0xf023,
    "folder": 0xf07b, "folder-open": 0xf07c, "folder-download": 0xe053, "folder-documents": 0xf07b,
    "download": 0xf019, "emblem-downloads": 0xf019,
    "x-office-calendar": 0xf133, "appointment": 0xf133, "appointment-new": 0xf133, "appointment-missed": 0xf133,
    "appointment-soon": 0xe0d2,
    "mail-read": 0xf2b6, "mail-send": 0xf1d8, "mail-send-receive": 0xf1d8,
    "network-offline": 0xf6ac, "network-error": 0xf6ac, "network-vpn": 0xf132, "network-wired": 0xf6ff,
    "audio-volume-muted": 0xf6a9, "audio-volume-low": 0xf027, "audio-volume-medium": 0xf028, "audio-volume-high": 0xf028,
    "audio-input-microphone": 0xf130, "audio-input-microphone-muted": 0xf131,
    "audio-headset": 0xf590, "audio-headphones": 0xf025, "audio-speakers": 0xf8df, "audio-card": 0xf8df,
    "bluetooth": 0xf293,
    "input-keyboard": 0xf11c, "input-mouse": 0xf8cc, "input-touchpad": 0xf8cc, "input-gaming": 0xf11b, "input-tablet": 0xf3fb,
    "phone": 0xf3ce, "computer": 0xf108, "tv": 0xf26c, "video-display": 0xf26c, "printer": 0xf02f,
    "camera-photo": 0xf030, "camera-video": 0xf03d, "camera-web": 0xf832,
    "multimedia-player": 0xf001,
    "media-playback-start": 0xf04b, "media-playback-pause": 0xf04c, "media-playback-stop": 0xf04d,
    "media-skip-forward": 0xf051, "media-seek-forward": 0xf04e, "media-seek-backward": 0xf04a, "media-eject": 0xf052,
    "software-update-available": 0xf0ed, "software-update-urgent": 0xf071,
    "security-high": 0xf2f7, "security-medium": 0xf132, "security-low": 0xf3ed,
    "system-run": 0xf013, "system-lock-screen": 0xf023, "system-shutdown": 0xf011, "system-reboot": 0xf2f1,
    "system-software-update": 0xf0ed, "system-users": 0xf007,
    "emblem-important": 0xf071, "emblem-warning": 0xf071, "emblem-default": 0xf058, "emblem-ok": 0xf058,
    "emblem-synchronized": 0xf058, "emblem-favorite": 0xf005, "emblem-unreadable": 0xf057, "emblem-error": 0xf057,
    "edit-copy": 0xf0c5, "edit-cut": 0xf0c4, "edit-delete": 0xf1f8, "edit-clear": 0xf1f8,
    "document-save": 0xf0c7, "document-print": 0xf02f, "document-send": 0xf1d8, "document-open": 0xf07c
};

// [prefix, codepoint]: the first match wins, after EXACT
var PREFIX = [
    ["network-wireless-offline", 0xf6ac], ["network-wireless-disabled", 0xf6ac], ["network-wireless", 0xf1eb],
    ["network-wired", 0xf6ff], ["network-", 0xf6ff],
    ["mail-", 0xf0e0],
    ["bluetooth", 0xf293],
    ["audio-volume-", 0xf028], ["audio-input-", 0xf130], ["audio-", 0xf001],
    ["input-", 0xf11c],
    ["phone-", 0xf3ce], ["camera-", 0xf030],
    ["media-", 0xf001],
    ["software-update-", 0xf0ed], ["security-", 0xf132], ["user-", 0xf007], ["system-", 0xf013],
    ["appointment-", 0xf133], ["edit-", 0xf044], ["document-", 0xf15c],
    ["folder-", 0xf07b]
];

// battery-level-NN[-charging], battery-full / good / low / caution / empty / missing, *-charging
function battery(name) {
    if (name.indexOf("battery") !== 0) return 0;
    if (/charging/.test(name)) return 0xf376;
    var m = /^battery-level-(\d+)/.exec(name);
    var lv = m ? parseInt(m[1], 10) : ({ "battery-full": 100, "battery-good": 70, "battery-low": 25, "battery-caution": 10,
                                         "battery-empty": 0, "battery-missing": 0 }[name]);
    if (lv === undefined) lv = 50;
    return lv >= 90 ? 0xf240 : lv >= 65 ? 0xf241 : lv >= 40 ? 0xf242 : lv >= 15 ? 0xf243 : 0xf244;
}

function glyph(name) {
    var n = String(name || "").replace(/-symbolic$/, "");
    if (n === "") return "";
    var cp = EXACT[n];
    if (cp === undefined) cp = battery(n);
    if (!cp) {
        for (var i = 0; i < PREFIX.length; i++)
            if (n.indexOf(PREFIX[i][0]) === 0) { cp = PREFIX[i][1]; break; }
    }
    return cp ? String.fromCharCode(cp) : "";
}
