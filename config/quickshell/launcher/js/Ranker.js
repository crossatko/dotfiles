.pragma library
.import "Frecency.js" as Frecency

// Item ranking. See README.md for the scoring table.

var S_ALIAS = 1000, S_NAME_EXACT = 950, S_PREFIX = 800, S_ALIAS_PREFIX = 750,
    S_WORD = 600, S_ACRONYM = 550, S_SUBSTR = 450, S_FUZZY_BASE = 150,
    S_KEYWORD = 250, S_SUBTITLE = 150, LEARNED_BOOST = 900, FREC_CAP = 80;

function words(s) {
    return s.replace(/([a-z0-9])([A-Z])/g, "$1 $2").split(/[^A-Za-z0-9]+/).filter(function (w) { return w.length > 0; });
}

function isAlnum(c) { return /[A-Za-z0-9]/.test(c); }

function isBoundary(s, i) {
    if (i === 0) return true;
    var p = s.charAt(i - 1), c = s.charAt(i);
    if (!isAlnum(p)) return true;
    return /[a-z0-9]/.test(p) && /[A-Z]/.test(c);
}

// Ordered subsequence match of tok (lowercase) in text; returns score or -1.
function fuzzy(text, tok) {
    var low = text.toLowerCase();
    var best = -1;
    for (var start = low.indexOf(tok.charAt(0)); start !== -1 && start < low.length; start = low.indexOf(tok.charAt(0), start + 1)) {
        var pos = start, prev = -2, sum = 0, ok = true;
        for (var i = 0; i < tok.length; i++) {
            var ch = tok.charAt(i);
            var at = -1;
            if (i === 0) at = start;
            else {
                // prefer a boundary hit within reach, else next occurrence
                var nxt = low.indexOf(ch, pos);
                var j = nxt;
                while (j !== -1 && !isBoundary(text, j) && j - nxt < 6) j = low.indexOf(ch, j + 1);
                at = (j !== -1 && isBoundary(text, j) && j - nxt < 6) ? j : nxt;
            }
            if (at === -1) { ok = false; break; }
            sum += 10;
            if (at === prev + 1) sum += 15;
            if (isBoundary(text, at)) sum += 12;
            if (prev >= 0 && at > prev + 1) sum -= Math.min(at - prev - 1, 6) * 2;
            prev = at;
            pos = at + 1;
        }
        if (ok && sum > best) best = sum;
    }
    if (best < 0) return -1;
    return S_FUZZY_BASE + Math.max(-100, Math.min(250, best - tok.length * 10));
}

function matchToken(item, tok) {
    var name = item.name || "";
    var low = name.toLowerCase();
    var best = 0, i;
    var aliases = item.aliases || [];
    for (i = 0; i < aliases.length; i++) {
        var a = String(aliases[i]).toLowerCase();
        if (a === tok) return S_ALIAS;
        if (a.indexOf(tok) === 0) best = Math.max(best, S_ALIAS_PREFIX);
    }
    if (low === tok) return Math.max(best, S_NAME_EXACT);
    if (low.indexOf(tok) === 0) return Math.max(best, S_PREFIX - Math.min(low.length - tok.length, 40));
    var ws = words(name);
    for (i = 0; i < ws.length; i++)
        if (ws[i].toLowerCase().indexOf(tok) === 0) { best = Math.max(best, S_WORD - i * 10); break; }
    if (tok.length >= 2) {
        var init = ws.map(function (w) { return w.charAt(0); }).join("").toLowerCase();
        if (init.indexOf(tok) === 0) best = Math.max(best, S_ACRONYM - Math.min(init.length - tok.length, 5) * 5);
    }
    if (best >= S_ACRONYM) return best;
    var sub = low.indexOf(tok);
    if (sub > 0) best = Math.max(best, S_SUBSTR - Math.min(sub, 40));
    if (best === 0) {
        var f = fuzzy(name, tok);
        if (f >= 0) best = f;
    }
    var kws = item.keywords || [];
    for (i = 0; i < kws.length; i++) {
        var k = String(kws[i]).toLowerCase();
        if (k.indexOf(tok) === 0) best = Math.max(best, S_KEYWORD);
        else if (k.indexOf(tok) > 0) best = Math.max(best, S_KEYWORD - 40);
    }
    if (item.subtitle && String(item.subtitle).toLowerCase().indexOf(tok) !== -1)
        best = Math.max(best, S_SUBTITLE);
    return best;
}

// Text score for the whole query (average of token scores), 0 = no match.
function matchScore(item, tokens) {
    var total = 0;
    for (var i = 0; i < tokens.length; i++) {
        var s = matchToken(item, tokens[i]);
        if (s <= 0) return 0;
        total += s;
    }
    return total / tokens.length;
}

function byName(a, b) {
    var x = (a.name || "").toLowerCase(), y = (b.name || "").toLowerCase();
    return x < y ? -1 : (x > y ? 1 : 0);
}

function rank(items, query, usage, now, opts) {
    opts = opts || {};
    usage = usage || {};
    var limit = opts.limit > 0 ? opts.limit : 50;
    var q = String(query || "").toLowerCase().replace(/^\s+|\s+$/g, "").replace(/\s+/g, " ");
    var tokens = q === "" ? [] : q.split(" ");
    var rows = [];
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        var u = usage[it.id];
        if (u && u.hidden && !opts.includeHidden) continue;
        var frec = Frecency.frecency(u, now);
        var score;
        if (tokens.length === 0) {
            score = (u && u.pinned) ? 10000 + frec : (frec > 0 ? 1000 + frec : 0);
        } else {
            var m = matchScore(it, tokens);
            var learned = u && u.terms && u.terms[q] ? 1 : 0;
            if (m <= 0 && !learned) continue;
            score = m + (learned ? LEARNED_BOOST : 0) + Math.min(FREC_CAP, frec / 5);
        }
        rows.push({ item: it, score: score });
    }
    rows.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        return byName(a.item, b.item);
    });
    return rows.slice(0, limit);
}
