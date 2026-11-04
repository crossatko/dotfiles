.pragma library

// The languages dictation can be set to (Settings > Voice > Languages): whisper's languages, code and English name. The same
// list as config/dictation/lib/dictation/languages.json (the service validates against that one; a dictation test keeps
// the two equal). Also the push-to-talk entries of a language selection: every language has a key to dictate in it
// ("ptt-<code>"), every language but English one that dictates it as English text ("ptt-<code>-en"; whisper only
// translates into English). Pure functions, no processes.

var LANGS = [
    ["en", "English"],
    ["zh", "Chinese"],
    ["de", "German"],
    ["es", "Spanish"],
    ["ru", "Russian"],
    ["ko", "Korean"],
    ["fr", "French"],
    ["ja", "Japanese"],
    ["pt", "Portuguese"],
    ["tr", "Turkish"],
    ["pl", "Polish"],
    ["ca", "Catalan"],
    ["nl", "Dutch"],
    ["ar", "Arabic"],
    ["sv", "Swedish"],
    ["it", "Italian"],
    ["id", "Indonesian"],
    ["hi", "Hindi"],
    ["fi", "Finnish"],
    ["vi", "Vietnamese"],
    ["he", "Hebrew"],
    ["uk", "Ukrainian"],
    ["el", "Greek"],
    ["ms", "Malay"],
    ["cs", "Czech"],
    ["ro", "Romanian"],
    ["da", "Danish"],
    ["hu", "Hungarian"],
    ["ta", "Tamil"],
    ["no", "Norwegian"],
    ["th", "Thai"],
    ["ur", "Urdu"],
    ["hr", "Croatian"],
    ["bg", "Bulgarian"],
    ["lt", "Lithuanian"],
    ["la", "Latin"],
    ["mi", "Maori"],
    ["ml", "Malayalam"],
    ["cy", "Welsh"],
    ["sk", "Slovak"],
    ["te", "Telugu"],
    ["fa", "Persian"],
    ["lv", "Latvian"],
    ["bn", "Bengali"],
    ["sr", "Serbian"],
    ["az", "Azerbaijani"],
    ["sl", "Slovenian"],
    ["kn", "Kannada"],
    ["et", "Estonian"],
    ["mk", "Macedonian"],
    ["br", "Breton"],
    ["eu", "Basque"],
    ["is", "Icelandic"],
    ["hy", "Armenian"],
    ["ne", "Nepali"],
    ["mn", "Mongolian"],
    ["bs", "Bosnian"],
    ["kk", "Kazakh"],
    ["sq", "Albanian"],
    ["sw", "Swahili"],
    ["gl", "Galician"],
    ["mr", "Marathi"],
    ["pa", "Punjabi"],
    ["si", "Sinhala"],
    ["km", "Khmer"],
    ["sn", "Shona"],
    ["yo", "Yoruba"],
    ["so", "Somali"],
    ["af", "Afrikaans"],
    ["oc", "Occitan"],
    ["ka", "Georgian"],
    ["be", "Belarusian"],
    ["tg", "Tajik"],
    ["sd", "Sindhi"],
    ["gu", "Gujarati"],
    ["am", "Amharic"],
    ["yi", "Yiddish"],
    ["lo", "Lao"],
    ["uz", "Uzbek"],
    ["fo", "Faroese"],
    ["ht", "Haitian Creole"],
    ["ps", "Pashto"],
    ["tk", "Turkmen"],
    ["nn", "Nynorsk"],
    ["mt", "Maltese"],
    ["sa", "Sanskrit"],
    ["lb", "Luxembourgish"],
    ["my", "Myanmar"],
    ["bo", "Tibetan"],
    ["tl", "Tagalog"],
    ["mg", "Malagasy"],
    ["as", "Assamese"],
    ["tt", "Tatar"],
    ["haw", "Hawaiian"],
    ["ln", "Lingala"],
    ["ha", "Hausa"],
    ["ba", "Bashkir"],
    ["jw", "Javanese"],
    ["su", "Sundanese"],
    ["yue", "Cantonese"]
];

// Czech and English: the keys and word lists the shell had before languages were selectable
var DEFAULTS = ["cs", "en"];

var NAMES = {};
LANGS.forEach(function (l) { NAMES[l[0]] = l[1]; });

function isCode(code) { return typeof code === "string" && NAMES.hasOwnProperty(code); }
function name(code) { return isCode(code) ? NAMES[code] : String(code).toUpperCase(); }

// a saved list -> valid, unique codes in order (anything else dropped)
function normalize(list) {
    var out = [];
    if (!Array.isArray(list)) return out;
    list.forEach(function (c) { if (isCode(c) && out.indexOf(c) < 0) out.push(c); });
    return out;
}

// the languages matching a typed search (code or name, case-insensitive; names starting with it first), without `skip`
function search(query, skip) {
    var q = String(query || "").trim().toLowerCase();
    var starts = [], inside = [];
    LANGS.forEach(function (l) {
        if (skip && skip.indexOf(l[0]) >= 0) return;
        var n = l[1].toLowerCase();
        if (q === "" || l[0] === q || n.indexOf(q) === 0) starts.push(l);
        else if (l[0].indexOf(q) === 0 || n.indexOf(q) >= 0) inside.push(l);
    });
    return starts.concat(inside).map(function (l) { return { code: l[0], name: l[1] }; });
}

// the key that is always there, whatever the selection: dictate in the language it detects (the dictation service's
// "auto" mode, among the selected languages when there are any)
var AUTO = { name: "ptt-auto", lang: "auto", translate: false, label: "Auto-detect", desc: "Push-to-talk: auto-detect language",
             service: "auto", pill: "auto" };

// the push-to-talk entries of a language selection, in order: the Auto key, then per language its own key and its
// "-> English" key.
// name = the global shortcut name (PttPrefs, hypr/hyprland/ptt.lua), service = the dictation service's mode,
// pill = the pill's mode ("cs", "cs-en")
function entriesFor(codes) {
    var out = [AUTO];
    normalize(codes).forEach(function (c) {
        var n = name(c);
        out.push({ name: "ptt-" + c, lang: c, translate: false, label: n, desc: "Push-to-talk: " + n,
                   service: c, pill: c });
        if (c !== "en")
            out.push({ name: "ptt-" + c + "-en", lang: c, translate: true, label: n + " \u2192 English",
                       desc: "Push-to-talk: " + n + " to English", service: "translate:" + c, pill: c + "-en" });
    });
    return out;
}

// "ptt-auto" / "ptt-ja" / "ptt-ja-en" -> { lang, translate } (null: not a push-to-talk name)
function parseName(s) {
    if (s === AUTO.name) return { lang: "auto", translate: false };
    var m = /^ptt-([a-z]{2,3})(-en)?$/.exec(String(s));
    if (!m || !isCode(m[1]) || (m[2] && m[1] === "en")) return null;
    return { lang: m[1], translate: !!m[2] };
}
