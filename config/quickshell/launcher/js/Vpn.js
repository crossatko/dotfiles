.pragma library

// Parsing shared by the network popup (TailscaleSection / MullvadSection) and the launcher (VpnSource): plain
// functions on the CLIs' output, no state, no processes.

// ---- Tailscale ------------------------------------------------------------------------------------------------
// `tailscale status --json` -> one flat object per machine, self first, then online first by name. Name = first
// label of DNSName (the MagicDNS machine name); host = the OS hostname the machine reports (HostName).
function tsPeers(d) {
    var users = d.User || {};
    var selfUser = d.Self ? d.Self.UserID : null;
    function one(p, isSelf) {
        var fqdn = String(p.DNSName || "").replace(/\.$/, "");
        var host = String(p.HostName || "");
        var ips = Array.isArray(p.TailscaleIPs) ? p.TailscaleIPs : [];
        var u = users[String(p.UserID)];
        var seen = String(p.LastSeen || "");
        return {
            id: String(p.ID || p.PublicKey || fqdn || host),
            name: fqdn ? fqdn.split(".")[0] : host,
            fqdn: fqdn,
            host: host,
            os: String(p.OS || ""),
            online: isSelf ? true : p.Online === true,
            lastSeen: seen.indexOf("0001-") === 0 ? "" : seen,
            ipv4: ips.find(function (a) { return a.indexOf(":") < 0; }) || "",
            ipv6: ips.find(function (a) { return a.indexOf(":") >= 0; }) || "",
            exitNode: p.ExitNode === true,
            exitOption: p.ExitNodeOption === true,
            tags: Array.isArray(p.Tags) ? p.Tags.map(String) : [],
            owner: !isSelf && selfUser !== null && p.UserID !== selfUser && u ? String(u.DisplayName || u.LoginName || "") : "",
            self: isSelf
        };
    }
    var others = Object.values(d.Peer || {}).map(function (p) { return one(p, false); })
        .sort(function (a, b) { return (b.online - a.online) || a.name.localeCompare(b.name); });
    return (d.Self ? [one(d.Self, true)] : []).concat(others);
}

function ago(iso) {
    var t = Date.parse(iso);
    if (isNaN(t)) return "";
    var m = Math.floor((Date.now() - t) / 60000);
    if (m < 1) return "just now";
    if (m < 60) return m + " min ago";
    if (m < 1440) return Math.floor(m / 60) + " h ago";
    if (m < 43200) return Math.floor(m / 1440) + " d ago";
    return iso.slice(0, 10);
}

// ---- Mullvad --------------------------------------------------------------------------------------------------
// error cause: a string, or {reason, details} (details may nest one more level)
function mvDescribe(c) {
    function human(s) { return String(s).replace(/_/g, " "); }
    if (!c) return "Unknown error";
    if (typeof c === "string") return human(c);
    var r = c.reason !== undefined ? c.reason : Object.keys(c)[0];
    var d = c.reason !== undefined ? c.details : c[r];
    var known = { auth_failed: "Account problem (logged out or out of time?)", is_offline: "Offline",
                  no_relays_matching_constraints: "No relay matches the selected location" };
    var dt = d && typeof d === "object" ? (d.reason || Object.keys(d)[0] || "") : d || "";
    if (known[dt]) return known[dt];
    if (known[r]) return known[r];
    return human(r) + (dt ? ": " + human(dt) : "");
}

// TunnelState as `mullvad status -j` serialises it: {"state": "...", "details": {location, locked_down | cause, block_failure}}
// -> {tunnel, loc: {country, city, hostname, entry, ipv4, ipv6} | null, lockedDown, cause, blocked}
function mvState(d) {
    var det = d.details && typeof d.details === "object" ? d.details : {};
    var tunnel = String(d.state || "");
    var l = det.location;
    var loc = l && (tunnel === "connected" || tunnel === "connecting") ? {
        country: String(l.country || ""), city: String(l.city || ""), hostname: String(l.hostname || ""),
        entry: String(l.entry_hostname || ""), ipv4: l.mullvad_exit_ip === false ? "" : String(l.ipv4 || ""),
        ipv6: l.mullvad_exit_ip === false ? "" : String(l.ipv6 || "")
    } : null;
    return {
        tunnel: tunnel,
        loc: loc,
        lockedDown: tunnel === "disconnected" && det.locked_down === true,
        cause: tunnel === "error" ? mvDescribe(det.cause) : "",
        blocked: tunnel === "error" && !det.block_failure
    };
}

// `mullvad relay list`: "Sweden (se)" / "\tGothenburg (got) @ ..." / "\t\tse-got-wg-001 (...)" (relays are not listed)
function mvRelays(text) {
    var out = [];
    var c = null;
    String(text).split("\n").forEach(function (line) {
        var m = /^(\S.*?)\s*\(([a-z]{2})\)\s*$/.exec(line);
        if (m) { c = { name: m[1], code: m[2], cities: [] }; out.push(c); return; }
        m = /^\t(\S.*?)\s*\(([a-z]{3})\)/.exec(line);
        if (m && c) c.cities.push({ name: m[1], code: m[2] });
    });
    return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
}

// `mullvad relay get` output -> the Location value ("country se", "city got, se"), "" when absent
function mvRelayLoc(text) {
    var m = /Location:\s*(.+)/.exec(String(text));
    return m ? m[1].trim() : "";
}

// the selected location as codes, matched against the relay list: {cc, city}
function mvChosen(relayLoc, countries) {
    var toks = relayLoc.toLowerCase().match(/\b[a-z]{2,3}\b/g) || [];
    var c = countries.find(function (x) { return toks.indexOf(x.code) >= 0; });
    if (!c) return { cc: "", city: "" };
    var ci = c.cities.find(function (x) { return toks.indexOf(x.code) >= 0; });
    return { cc: c.code, city: ci ? ci.code : "" };
}

// first meaningful line of a CLI error, links masked
function mvFirstLine(t) {
    var l = String(t).split("\n").map(function (s) { return s.trim(); }).filter(function (s) { return s !== "" && !/^Caused by:?$/i.test(s); })[0] || "";
    return l.replace(/^Error:\s*/, "").replace(/https?:\/\/\S+/g, "<link>").slice(0, 160);
}
