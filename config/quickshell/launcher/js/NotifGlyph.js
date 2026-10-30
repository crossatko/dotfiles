.pragma library

// Vadivam glyph for a standard freedesktop icon name (NotifIcon draws it with the shell's
// Icon). "" = not a standard name: app-specific names keep their own icon, unknown ones the symbolic Adwaita one.
// Codepoints come from the installed font's cmap (fontTools), not from memory.

var EXACT = {
    "dialog-information": 0xe0c9, "dialog-info": 0xe0c9, "dialog-warning": 0xe101, "dialog-error": 0xe11b,
    "dialog-question": 0xe15f, "dialog-password": 0xe0cd,
    "folder": 0xe0bd, "folder-open": 0xe0be, "folder-download": 0xe439, "folder-documents": 0xe0bd,
    "download": 0xe0b7, "emblem-downloads": 0xe0b7,
    "x-office-calendar": 0xe0aa, "appointment": 0xe0aa, "appointment-new": 0xe0aa, "appointment-missed": 0xe0aa,
    "appointment-soon": 0xe19e,
    "mail-read": 0xe4f5, "mail-send": 0xe0df, "mail-send-receive": 0xe0df,
    "network-offline": 0xe146, "network-error": 0xe146, "network-vpn": 0xe0e2, "network-wired": 0xe3f2,
    "audio-volume-muted": 0xe1d0, "audio-volume-low": 0xe12a, "audio-volume-medium": 0xe12b, "audio-volume-high": 0xe12b,
    "audio-input-microphone": 0xe10f, "audio-input-microphone-muted": 0xe52b,
    "audio-headset": 0xe20c, "audio-headphones": 0xe48a, "audio-speakers": 0xe64e, "audio-card": 0xe64e,
    "bluetooth": 0xe148,
    "input-keyboard": 0xe120, "input-mouse": 0xe54a, "input-touchpad": 0xe54a, "input-gaming": 0xe265, "input-tablet": 0xe1c6,
    "phone": 0xe114, "computer": 0xe0d3, "tv": 0xe1cb, "video-display": 0xe1cb, "printer": 0xe245,
    "camera-photo": 0xe105, "camera-video": 0xe128, "camera-web": 0xe105,
    "multimedia-player": 0xe229,
    "media-playback-start": 0xe0d7, "media-playback-pause": 0xe0fb, "media-playback-stop": 0xe0e5,
    "media-skip-forward": 0xe1ad, "media-seek-forward": 0xe3fb, "media-seek-backward": 0xe5e0, "media-eject": 0xe3eb,
    "software-update-available": 0xe28f, "software-update-urgent": 0xe101,
    "security-high": 0xe0e3, "security-medium": 0xe0e2, "security-low": 0xe623,
    "system-run": 0xe0e1, "system-lock-screen": 0xe0cd, "system-shutdown": 0xe126, "system-reboot": 0xe0da,
    "system-software-update": 0xe28f, "system-users": 0xe0ec,
    "emblem-important": 0xe101, "emblem-warning": 0xe101, "emblem-default": 0xe107, "emblem-ok": 0xe107,
    "emblem-synchronized": 0xe107, "emblem-favorite": 0xe0e6, "emblem-unreadable": 0xe11b, "emblem-error": 0xe11b,
    "edit-copy": 0xe0b4, "edit-cut": 0xe1d5, "edit-delete": 0xe100, "edit-clear": 0xe100,
    "document-save": 0xe0dd, "document-print": 0xe245, "document-send": 0xe0df, "document-open": 0xe0be
};

// [prefix, codepoint]: the first match wins, after EXACT
var PREFIX = [
    ["network-wireless-offline", 0xe146], ["network-wireless-disabled", 0xe146], ["network-wireless", 0xe117],
    ["network-wired", 0xe3f2], ["network-", 0xe3f2],
    ["mail-", 0xe0cf],
    ["bluetooth", 0xe148],
    ["audio-volume-", 0xe12b], ["audio-input-", 0xe10f], ["audio-", 0xe229],
    ["input-", 0xe120],
    ["phone-", 0xe114], ["camera-", 0xe105],
    ["media-", 0xe229],
    ["software-update-", 0xe28f], ["security-", 0xe0e2], ["user-", 0xe0ec], ["system-", 0xe0e1],
    ["appointment-", 0xe0aa], ["edit-", 0xe142], ["document-", 0xe0bc],
    ["folder-", 0xe0bd]
];

// battery-level-NN[-charging], battery-full / good / low / caution / empty / missing, *-charging
function battery(name) {
    if (name.indexOf("battery") !== 0) return 0;
    if (/charging/.test(name)) return 0xe08b;
    var m = /^battery-level-(\d+)/.exec(name);
    var lv = m ? parseInt(m[1], 10) : ({ "battery-full": 100, "battery-good": 70, "battery-low": 25, "battery-caution": 10,
                                         "battery-empty": 0, "battery-missing": 0 }[name]);
    if (lv === undefined) lv = 50;
    return lv >= 90 ? 0xe08c : lv >= 65 ? 0xe08e : lv >= 40 ? 0xe08e : lv >= 15 ? 0xe08d : 0xe08a;
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
