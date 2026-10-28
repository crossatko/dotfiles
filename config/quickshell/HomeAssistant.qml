pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Home Assistant over its REST API (GET /api/states, POST /api/services/<domain>/<service>).
// Credentials: config/hypr/.secrets (git-ignored, shared KEY=VALUE file; see .secrets.example). Only HA_* keys are read:
//   HA_URL=http://homeassistant.local:8123   HA_TOKEN=<long-lived access token>   [HA_URL_FALLBACK=http://<ip>:8123]
// Nothing host-specific lives here: without HA_URL + HA_TOKEN the popup shows its setup notice.
// QS_HA_SECRETS / QS_HA_STATE_DIR override both paths (tests point them at a mock server's files).
// Which entities are hidden in the popup: ~/.local/state/quickshell/homeassistant.json {"hidden": [...], "hiddenSections": ["light", ...]} (section keys: light, climate, vacuum, fan, cover, switch).
// Switches from container-manager integrations (Portainer, Docker, ...: one switch per container / stack) are
// left out by integration (config entry domain); extend with {"excludePlatforms": [...]} in that file.
// Optimistic UI: a service call applies its expected result at once (`pend` records merged over the polled states
// into `byId`; `serverById` stays the last polled truth), see "optimistic layer" below.
// Polls every 4 s while the popup is open (15 s while failing), once a minute for the bar chip, not at all otherwise.
// The token goes only into the Authorization header of in-process XHRs (never argv, never the log). When a
// request fails without an HTTP status, a token-less `curl` probe of <base>/api/ classifies why (DNS, refused,
// timeout, TLS, redirect); the probe's argv carries the URL only.
Singleton {
    id: ha

    readonly property string home: Quickshell.env("HOME")
    readonly property string secretsPath: Quickshell.env("QS_HA_SECRETS") || (home + "/.config/hypr/.secrets")
    readonly property string stateDir: Quickshell.env("QS_HA_STATE_DIR") || (home + "/.local/state/quickshell")

    // domains shown in the popup, in section order
    readonly property var domains: ["light", "climate", "vacuum", "fan", "cover", "switch", "input_boolean"]
    readonly property var defaultExcluded: ["portainer", "docker", "monitor_docker", "dockermon", "dockge", "komodo"]
    property var excludePlatforms: defaultExcluded

    property string url: ""
    property string fallbackUrl: ""
    property string token: ""
    property bool secretsRead: false
    readonly property bool configured: token !== "" && url !== ""
    property string base: ""                 // the URL currently in use (url, or fallbackUrl after a network failure)

    // "idle" | "loading" | "ok" | "unreachable" | "unauthorized" | "error"
    property string status: "idle"
    property string errorText: ""            // short headline, e.g. "Home Assistant unreachable: connection timed out"
    property string errorHint: ""            // what to do about it
    readonly property bool failed: ["unreachable", "unauthorized", "error"].indexOf(status) >= 0
    readonly property string host: { const m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(base || url); return m ? m[1] : (base || url) }
    property string actionError: ""
    property double lastUpdate: 0

    property var byId: ({})                  // entity_id -> state object shown by the UI: serverById + pending predictions
    property var serverById: ({})            // entity_id -> last polled state object (the truth)
    property var sections: ({})              // domain -> [entity_id] (sorted by area, name); only reassigned when the set changes
    property var areas: ({})                 // entity_id -> area name
    property var devices: ({})               // entity_id -> device id
    property var dropped: ({})               // entity_id -> true: hidden in HA, a sub-entity of a shown device, or a container switch
    property var platforms: ({})             // entity_id -> integration domain (config entry), when HA can tell
    property bool metaDone: false            // first area / device / platform lookup finished (or failed)
    property var rawGroups: ({})             // domain -> [entity_id], before `dropped`
    property var busy: ({})                  // entity_id -> true when the server has not confirmed a change after 1.2 s (subtle "syncing")
    property var acked: ({})                 // scene / script / button id -> true for a moment after it was run
    property var hidden: []
    property var hiddenSections: []          // whole popup sections switched off in edit mode (key = first domain of the section)
    property var services: ({})              // "domain.service" -> true (GET /api/services, once per connection)
    property bool servicesAsked: false
    property var helpers: ({})               // number / select / sensor entities that may belong to a vacuum (repeat, battery, status)
    property var vacRooms: ({})              // vacuum id -> [{id, name}] fetched with roborock.get_maps
    property var vacAsked: ({})

    readonly property bool panelOpen: Popups.name === "ha"
    readonly property int lightsOn: {
        const ids = isSectionHidden("light") ? [] : (sections.light || [])
        return ids.filter(id => !isHidden(id) && byId[id] && byId[id].state === "on").length
    }

    signal updated()

    function isHidden(id) { return hidden.indexOf(id) >= 0 }
    // unavailable / unknown entities are left out of the popup until they come back (scenes and scripts
    // are "unknown" until first used, so they always count as available)
    function isAvailable(id) {
        const e = byId[id]
        if (!e) return false
        const d = id.split(".")[0]
        return e.state !== "unavailable" && (e.state !== "unknown" || d === "scene" || d === "script")
    }
    // input_boolean shares the "switch" section
    function sectionOf(domain) { return domain === "input_boolean" ? "switch" : domain }
    function isSectionHidden(key) { return hiddenSections.indexOf(key) >= 0 }
    function setSectionHidden(key, hide) {
        const h = hiddenSections.filter(x => x !== key)
        if (hide) h.push(key)
        hiddenSections = h.sort()
        saver.restart()
        if (!hide && key === "vacuum") { if (!servicesAsked && configured) fetchServices(); else for (const v of (sections.vacuum || [])) fetchRooms(v) }
    }
    function setHidden(id, hide) {
        const h = hidden.filter(x => x !== id)
        if (hide) h.push(id)
        hidden = h.sort()
        saver.restart()
    }
    function name(id) {
        const e = byId[id]
        return e && e.attributes && e.attributes.friendly_name ? e.attributes.friendly_name : id
    }

    // ---- secrets ------------------------------------------------------------------
    function parseSecrets(text) {
        const kv = {}
        for (let line of (text || "").split("\n")) {
            line = line.trim()
            if (line === "" || line[0] === "#") continue
            if (line.indexOf("export ") === 0) line = line.slice(7).trim()
            const i = line.indexOf("=")
            if (i <= 0) continue
            let v = line.slice(i + 1).trim()
            if (v.length >= 2 && (v[0] === '"' || v[0] === "'") && v[v.length - 1] === v[0]) v = v.slice(1, -1)
            kv[line.slice(0, i).trim()] = v
        }
        const strip = u => (u || "").replace(/\/+$/, "")
        const same = url === strip(kv.HA_URL) && token === (kv.HA_TOKEN || "")
        url = strip(kv.HA_URL)
        fallbackUrl = strip(kv.HA_URL_FALLBACK)
        token = kv.HA_TOKEN || ""
        if (!same) { pend = ({}); pendCount = 0; serverById = ({}); busy = ({}); base = url; status = "idle"; errorText = ""; errorHint = ""; metaDone = false; rawGroups = ({}); servicesAsked = false; services = ({}); vacAsked = ({}); vacRooms = ({}) }
        secretsRead = true
        if (configured) refresh(true)
        else { status = "idle"; byId = ({}); sections = ({}) }
    }

    FileView {
        id: secrets
        path: ha.secretsPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: ha.parseSecrets(text())
        onLoadFailed: ha.parseSecrets("")
    }

    // ---- hidden entities (UI state, not secret) -------------------------------------
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", ha.stateDir])
    Timer { id: saver; interval: 400; onTriggered: {
        const o = { hidden: ha.hidden, hiddenSections: ha.hiddenSections }
        const extra = ha.excludePlatforms.filter(x => ha.defaultExcluded.indexOf(x) < 0)
        if (extra.length) o.excludePlatforms = extra
        prefs.setText(JSON.stringify(o, null, 2))
    } }
    FileView {
        id: prefs
        path: ha.stateDir + "/homeassistant.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const p = JSON.parse(text())
                ha.hidden = p && Array.isArray(p.hidden) ? p.hidden.filter(x => typeof x === "string") : []
                ha.hiddenSections = p && Array.isArray(p.hiddenSections) ? p.hiddenSections.filter(x => typeof x === "string").sort() : []
                ha.excludePlatforms = ha.defaultExcluded.concat(p && Array.isArray(p.excludePlatforms) ? p.excludePlatforms.filter(x => typeof x === "string") : [])
            } catch (e) { ha.hidden = []; ha.hiddenSections = [] }
        }
        onLoadFailed: { ha.hidden = []; ha.hiddenSections = []; ha.excludePlatforms = ha.defaultExcluded }
    }

    // ---- transport ----------------------------------------------------------------------
    property var inflight: []                // [{x, t, done, cb}]

    // cb(status, text, timedOut, startedAt); limit: abort after this many ms (default 8 s)
    function request(method, path, body, cb, limit) {
        const r = { x: new XMLHttpRequest(), t: Date.now(), done: false, cb: cb, limit: limit || 8000 }
        const finish = (st, txt) => {
            if (r.done) return
            r.done = true
            inflight = inflight.filter(q => q !== r)
            cb(st, txt, r.timedOut === true, r.t)
        }
        r.finish = finish
        r.x.onreadystatechange = function() {
            if (r.x.readyState === XMLHttpRequest.DONE) finish(r.x.status, r.x.responseText)
        }
        r.x.open(method, base + path)
        r.x.setRequestHeader("Authorization", "Bearer " + token)
        r.x.setRequestHeader("Content-Type", "application/json")
        inflight = inflight.concat([r])
        if (body !== null && body !== undefined) r.x.send(typeof body === "string" ? body : JSON.stringify(body))
        else r.x.send()
    }
    // XHR has no timeout here: a watchdog aborts anything older than its limit (8 s; service calls 6 s)
    Timer {
        interval: 1000; repeat: true
        running: ha.inflight.length > 0
        onTriggered: {
            const now = Date.now()
            for (const r of ha.inflight.slice())
                if (now - r.t > r.limit) { r.timedOut = true; try { r.x.abort() } catch (e) {} r.finish(0, "") }
        }
    }

    property bool refreshing: false
    property bool again: false               // a refresh was asked for while one was in flight
    // force: the user asked (Retry / refresh button / popup opened); polls never queue behind a request
    function refresh(force) {
        if (!configured) return
        if (refreshing) { if (force) again = true; return }
        refreshing = true
        if (status === "idle") status = "loading"     // a failure stays on screen while retrying
        if (force && failed) retrying = true
        request("GET", "/api/states", null, (st, txt, timedOut, startedAt) => {
            refreshing = false
            if (again) { again = false; Qt.callLater(refresh, true) }
            if (st === 200) {
                let arr = null
                try { arr = JSON.parse(txt) } catch (e) { arr = null }
                if (!Array.isArray(arr)) { fail("error", "Not a Home Assistant API reply", "Check that HA_URL points at Home Assistant itself (scheme, host, port)."); return }
                apply(arr, startedAt)
                if (status !== "ok") console.log("homeassistant: connected")
                status = "ok"; errorText = ""; errorHint = ""; retrying = false
            } else if (st === 401 || st === 403) {
                fail("unauthorized", "Token rejected (HTTP " + st + ")", "Check HA_TOKEN in ~/.config/hypr/.secrets (a long-lived access token).")
            } else if (st === 0 || (st >= 300 && st < 400)) {
                if (base !== fallbackUrl && fallbackUrl !== "") { base = fallbackUrl; refresh(true); return }
                if (timedOut) fail("unreachable", "Home Assistant unreachable: no reply within 8 s", "Is the host up and the port right? Off the LAN?")
                else if (st >= 300) fail("unreachable", "Home Assistant unreachable: redirected (HTTP " + st + ")", "Use the final URL as HA_URL (often https://, or another host behind a reverse proxy).")
                else fail("unreachable", "Home Assistant unreachable", "")
                probe()
            } else if (st === 404) {
                fail("error", "No Home Assistant API here (HTTP 404)", "HA_URL should be the base URL, e.g. http://host:8123 (no path).")
            } else {
                fail("error", "Home Assistant error (HTTP " + st + ")", "")
            }
        })
    }
    property bool retrying: false
    function fail(s, text, hint) {
        status = s; errorText = text; errorHint = hint; retrying = false
        console.log("homeassistant: " + text)
        if (s !== "unreachable") base = url              // next attempt starts with the main URL again
    }

    // Why did the XHR fail? A token-less curl to <base>/api/ (HA answers 401 without a token, so any HTTP
    // status means the host is reachable). Exit codes: 6 DNS, 7 refused, 28 timeout, 35/51/53/58/59/60/77/83/90/91 TLS.
    Process {
        id: prober
        property string target: ""
        property int code: -1                // exit code, once exited
        property bool streamDone: false
        stdout: StdioCollector { id: probeOut; onStreamFinished: { prober.streamDone = true; if (prober.code >= 0) prober.done() } }
        onExited: c => { prober.code = c; if (prober.streamDone) prober.done() }
        function done() {
            const code = prober.code
            if (ha.status !== "unreachable" || prober.target !== ha.base) { ha.base = ha.url; return }
            const out = (probeOut.text || "").trim().split(" ")
            const http = parseInt(out[0]) || 0
            const loc = out[1] || ""
            const tls = [35, 51, 53, 58, 59, 60, 77, 83, 90, 91]
            let why = "", hint = ""
            if (code === 6) { why = "host name not found"; hint = "DNS can't resolve " + ha.host + "." }
            else if (code === 7) { why = "connection refused"; hint = "Nothing listens on " + ha.host + " (wrong port?)." }
            else if (code === 28) { why = "connection timed out"; hint = "No answer from " + ha.host + " (port closed, firewalled or off the LAN)." }
            else if (tls.indexOf(code) >= 0) { why = "TLS certificate not trusted"; hint = "Add the server's CA to the system trust store, or use the plain http:// URL." }
            else if (code === 0 && http >= 300 && http < 400) {
                const m = /^([a-z]+:\/\/[^\/?#]+)/i.exec(loc)
                why = "redirected to " + (m ? m[1] : "another URL"); hint = "Set HA_URL to the final URL" + (m ? " (" + m[1] + ")" : "") + "."
            }
            else if (code === 0 && http > 0) { why = "reachable, but the request failed"; hint = "curl gets HTTP " + http + " from " + ha.host + "; the shell's request did not (proxy / TLS?)." }
            else { why = "network error (curl " + code + ")"; hint = "" }
            ha.status = "unreachable"
            ha.errorText = "Home Assistant unreachable: " + why
            ha.errorHint = hint
            console.log("homeassistant: " + ha.errorText)
            ha.base = ha.url
        }
    }
    function probe() {
        if (prober.running) return
        prober.code = -1; prober.streamDone = false
        prober.target = base
        prober.command = ["curl", "-sS", "-o", "/dev/null", "--max-time", "6", "--connect-timeout", "5",
                          "-w", "%{http_code} %{redirect_url}", base + "/api/"]
        prober.running = true
    }

    function apply(arr, startedAt) {
        const map = {}
        const groups = {}
        const help = {}
        for (const d of domains) groups[d] = []
        for (const s of arr) {
            if (!s || typeof s.entity_id !== "string") continue
            const d = s.entity_id.split(".")[0]
            if (((d === "number" || d === "select") && repeatRe.test(s.entity_id))
                || (d === "sensor" && s.attributes && (s.attributes.device_class === "battery" || /_status$/.test(s.entity_id))))
                help[s.entity_id] = s
            if (!groups[d]) continue
            s.attributes = s.attributes || {}
            map[s.entity_id] = s
            groups[d].push(s.entity_id)
        }
        serverById = map
        helpers = help
        for (const id in map) noteBri(map[id])
        if (pendCount > 0) for (const id of Object.keys(pend)) reconcile(id, map[id] || help[id] || null, startedAt || 0, true)
        rebuild()
        lastUpdate = Date.now()
        const changed = JSON.stringify(groups) !== JSON.stringify(rawGroups)
        rawGroups = groups
        regroup()
        if (changed) fetchMeta(Object.keys(map).concat(Object.keys(help)))
        if (!isSectionHidden("vacuum")) {       // vacuum-only extras (services, rooms) are skipped while the section is off
            if (!servicesAsked) fetchServices()
            else for (const v of groups.vacuum) fetchRooms(v)
        }
        updated()
    }
    // sections = raw groups minus dropped entities, sorted; reassigned only when something changed
    function regroup() {
        const g = {}
        for (const d of domains) g[d] = d === "switch" && !metaDone ? []       // no flash of container switches before their platform is known
            : sorted((rawGroups[d] || []).filter(id => !dropped[id] && !(d === "switch" && excludePlatforms.indexOf(platforms[id] || "") >= 0)))
        if (JSON.stringify(g) !== JSON.stringify(sections)) sections = g
    }

    // available before unavailable, then by area (entities without one last), then by name
    function sorted(ids) {
        const gone = id => { const e = byId[id]; return !e || e.state === "unavailable" ? 1 : 0 }
        const area = id => areas[id] || ""
        return ids.slice().sort((a, b) => (gone(a) - gone(b))
            || ((area(a) === "") - (area(b) === "")) || area(a).localeCompare(area(b))
            || name(a).toLowerCase().localeCompare(name(b).toLowerCase()))
    }

    // Area, device and "hidden in HA" per entity via the template endpoint (a read-only render: /api/states
    // carries none of them). Dropped from the popup: entities hidden in HA, and switches / input_booleans /
    // fans that belong to the device of a shown light, climate or vacuum (child lock, display LED, DND, ...:
    // the device's own card covers it). Optional: on failure everything just shows, without areas.
    // metaLevel 2: + integration (config entry domain); 1: + hidden in HA; 0: area / device only (older HA)
    property int metaLevel: 2
    function fetchMeta(ids) {
        if (ids.length === 0) { metaDone = true; regroup(); return }
        const plat = "{% set ce = config_entry_id(id) %}{{ config_entry_attr(ce, 'domain') if ce else '' }}"
        const tpl = "{% for id in " + JSON.stringify(ids) + " %}{{ id }}\t{{ area_name(id) or '' }}\t{{ device_id(id) or '' }}\t"
            + (metaLevel >= 1 ? "{{ is_hidden_entity(id) }}" : "False") + "\t" + (metaLevel >= 2 ? plat : "") + "\n{% endfor %}"
        request("POST", "/api/template", { template: tpl }, (st, txt) => {
            if (st !== 200) {
                if (metaLevel > 0 && st === 400) { metaLevel--; fetchMeta(ids); return }
                metaDone = true; regroup(); return
            }
            const ar = {}, dev = {}, hid = {}, pl = {}
            for (const line of txt.split("\n")) {
                const p = line.split("\t")
                if (p.length !== 5) continue
                const id = p[0].trim()
                if (p[1].trim() !== "") ar[id] = p[1].trim()
                if (p[2].trim() !== "") dev[id] = p[2].trim()
                if (p[3].trim() === "True") hid[id] = true
                if (p[4].trim() !== "") pl[id] = p[4].trim()
            }
            areas = ar
            devices = dev
            platforms = pl
            const owners = {}                 // device id -> true when it has a primary entity we show
            for (const d of ["light", "climate", "vacuum"]) for (const id of (rawGroups[d] || [])) if (dev[id]) owners[dev[id]] = true
            const drop = Object.assign({}, hid)
            for (const d of ["switch", "input_boolean", "fan"]) for (const id of (rawGroups[d] || [])) if (dev[id] && owners[dev[id]]) drop[id] = true
            dropped = drop
            metaDone = true
            regroup()
        })
    }

    // ---- vacuum rooms / passes / fan speed --------------------------------------------
    // Rooms come from (1) the vacuum's own attributes (Dreame: `rooms` {map: [{id, name}]}, others
    // `segments` / `room_list`), else (2) roborock.get_maps (Roborock core integration, read-only service with
    // a response). Cleaning selected rooms: dreame_vacuum.vacuum_clean_segment {segments, repeats} when that
    // service exists, else vacuum.send_command app_segment_clean [{segments, repeat}] (Roborock / Xiaomi miio).
    // A full clean's passes go through a "repeat" / "cleaning times" number / select entity of the same
    // device when there is one (set before vacuum.start).
    readonly property var repeatRe: /(repeat|cleaning_times|clean_times|cleaning_count|cleaning_cycles|cleaning_passes|clean_count)/

    // helpers of the same device as vacuum `id` (or named after it when HA can't tell devices)
    function siblings(id, pred) {
        const obj = id.split(".")[1]
        return Object.keys(helpers).filter(h => pred(h, helpers[h]) && (devices[id] ? devices[h] === devices[id] : h.split(".")[1].indexOf(obj) === 0))
    }
    // battery level: the vacuum's attribute (older integrations) or a battery sensor of the same device
    function batteryOf(id) {
        const a = byId[id] ? byId[id].attributes : {}
        if (typeof a.battery_level === "number") return a.battery_level
        const s = siblings(id, (h, e) => h.indexOf("sensor.") === 0 && e.attributes && e.attributes.device_class === "battery")[0]
        const v = s ? parseFloat(helpers[s].state) : NaN
        return isNaN(v) ? -1 : Math.round(v)
    }
    // detailed status: the vacuum's `status` attribute or a <device>_status sensor ("charging", "segment_cleaning", ...)
    function statusOf(id) {
        const e = byId[id]
        if (!e) return ""
        if (pend[id] && pend[id].state) return pend[id].state            // expected, until the server confirms
        if (e.attributes && typeof e.attributes.status === "string") return e.attributes.status
        const s = siblings(id, h => /^sensor\..*_status$/.test(h))[0]
        const v = s ? helpers[s].state : ""
        return v && v !== "unknown" && v !== "unavailable" ? v : e.state
    }

    function fetchServices() {
        servicesAsked = true
        request("GET", "/api/services", null, (st, txt) => {
            if (st !== 200) { servicesAsked = false; return }
            const m = {}
            try { for (const d of JSON.parse(txt)) for (const sv in (d.services || {})) m[d.domain + "." + sv] = true } catch (e) {}
            services = m
            if (!isSectionHidden("vacuum")) for (const v of (sections.vacuum || [])) fetchRooms(v)
        })
    }
    function has(svc) { return services[svc] === true }

    function roomList(v, prefer) {
        if (Array.isArray(v)) return v.filter(r => r && typeof r === "object" && r.id !== undefined)
            .map(r => ({ id: r.id, name: String(r.name || r.room_name || ("Room " + r.id)) }))
        if (v && typeof v === "object") {
            const keys = Object.keys(v)
            if (keys.length && keys.every(k => typeof v[k] === "string"))
                return keys.map(k => ({ id: isNaN(Number(k)) ? k : Number(k), name: v[k] }))
            if (prefer && v[prefer]) { const l = roomList(v[prefer]); if (l.length) return l }
            for (const k of keys) { const l = roomList(v[k]); if (l.length) return l }
        }
        return []
    }
    function attrRooms(id) {
        const a = byId[id] ? byId[id].attributes : {}
        for (const k of ["rooms", "segments", "room_list", "room_mapping"]) {
            const l = roomList(a[k], a.selected_map || a.current_map)
            if (l.length) return l
        }
        return []
    }
    function roomsOf(id) {
        const l = attrRooms(id)
        return l.length ? l : (vacRooms[id] || [])
    }
    function fetchRooms(id) {
        // vacAsked[id]: true = rooms fetched; a number = time of the last failed/empty try (retried after 30 s,
        // never while the vacuum is unavailable, so there is no call spam)
        const ent = byId[id], last = vacAsked[id]
        if (isSectionHidden("vacuum") || last === true || attrRooms(id).length || !has("roborock.get_maps")) return
        if (!ent || ent.state === "unavailable" || ent.state === "unknown") return
        if (typeof last === "number" && Date.now() - last < 30000) return
        const asked = Object.assign({}, vacAsked); asked[id] = Date.now(); vacAsked = asked
        request("POST", "/api/services/roborock/get_maps?return_response", { entity_id: id }, (st, txt) => {
            if (st !== 200) return
            let maps = []
            try {
                const r = JSON.parse(txt)
                const sr = r.service_response || r
                maps = (sr[id] || sr).maps || []
            } catch (e) { maps = [] }
            const pick = maps.find(m => m.rooms && Object.keys(m.rooms).length) || null
            const l = pick ? roomList(pick.rooms) : []
            const vr = Object.assign({}, vacRooms); vr[id] = l; vacRooms = vr
            if (l.length) { const a = Object.assign({}, vacAsked); a[id] = true; vacAsked = a }
        })
    }
    function repeatEntityOf(id) {
        const obj = id.split(".")[1]
        const hs = Object.keys(helpers).filter(h => (h.indexOf("number.") === 0 || h.indexOf("select.") === 0) && repeatRe.test(h))
        return hs.find(h => devices[id] && devices[h] === devices[id])            // same device
            || hs.find(h => h.split(".")[1].indexOf(obj) === 0) || ""               // or named after the vacuum
    }
    function cleanRooms(id, segIds, passes) {
        // rooms from the vacuum's attributes + the Dreame service present -> Dreame; rooms from get_maps -> Roborock
        if (attrRooms(id).length > 0 && has("dreame_vacuum.vacuum_clean_segment"))
            call("dreame_vacuum", "vacuum_clean_segment", id, { segments: segIds, repeats: passes })
        else
            call("vacuum", "send_command", id, { command: "app_segment_clean", params: [{ segments: segIds, repeat: passes }] })
    }
    function cleanAll(id, passes) {
        const rep = repeatEntityOf(id)
        const all = roomsOf(id)
        if (rep !== "" && passes >= 1) expect("vacuum", "start", id)          // the passes are set first: show "cleaning" now
        if (rep === "" && passes > 1 && all.length > 0) { cleanRooms(id, all.map(r => r.id), passes); return }
        if (rep === "" || passes < 1) { call("vacuum", "start", id); return }
        const h = helpers[rep]
        if (rep.indexOf("number.") === 0) call("number", "set_value", rep, { value: passes }, () => call("vacuum", "start", id), () => rollback(id))
        else {
            const opt = (h.attributes.options || []).find(o => parseInt(o) === passes)
            if (opt === undefined) call("vacuum", "start", id)
            else call("select", "select_option", rep, { option: opt }, () => call("vacuum", "start", id), () => rollback(id))
        }
    }

    // ---- optimistic layer ---------------------------------------------------------------
    // A service call applies its expected result at once: `pend[id]` = {state, attrs, accept, ...} is merged over
    // `serverById[id]` into `byId` (every consumer reads byId, so cards, bar chip and summaries change in the same
    // frame). Reconciliation (reconcile): the prediction stays while the call is in flight and for `hold` ms after it
    // succeeded; a polled state whose request started BEFORE the call finished is stale and ignored; the first
    // fresh state ends it (it matches: confirmed; or the hold is over: the server wins). A newer call on the same
    // entity supersedes the record (last intent wins). Error / timeout: rollback to the polled state + actionError.
    // After the reply a single-entity GET (/api/states/<id>) checks instead of the full list; the full list still
    // comes from the normal timer. Unavailable / unknown entities get no prediction.
    property var pend: ({})                  // entity_id -> record
    property int pendCount: 0
    property var lastBri: ({})               // light id -> last brightness seen while on (turn_on without one)
    property int seqCounter: 0
    property double interactUntil: 0
    function touch() { interactUntil = Date.now() + 1500 }      // the user is acting: the poll timer skips its refresh

    function noteBri(s) { if (s && s.state === "on" && s.attributes && typeof s.attributes.brightness === "number") lastBri[s.entity_id] = s.attributes.brightness }
    function hsToRgb(h, s) {                 // h 0..360, s 0..100
        const c = s / 100, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = 1 - c
        const k = Math.floor(((h % 360) + 360) % 360 / 60)
        const v = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][k]
        return v.map(q => Math.round((q + m) * 255))
    }
    function merged(id) {
        const s = serverById[id], p = pend[id]
        if (!s || !p || (p.state === null && Object.keys(p.attrs).length === 0)) return s
        return { entity_id: id, state: p.state !== null ? p.state : s.state, attributes: Object.assign({}, s.attributes, p.attrs) }
    }
    function rebuild() { const m = {}; for (const id in serverById) m[id] = merged(id); byId = m }
    function setMerged(id) { if (!serverById[id]) return; const m = Object.assign({}, byId); m[id] = merged(id); byId = m }
    function setBusy(id, on) {
        if ((busy[id] === true) === on) return
        const b = Object.assign({}, busy); if (on) b[id] = true; else delete b[id]; busy = b
    }

    // expected result of domain.service on entity `cur`: {state, attrs, accept (server states that confirm), hold ms} or null
    function predict(domain, service, id, data, cur) {
        const on = cur.state === "on"
        const r = (state, attrs, accept, hold) => ({ state: state, attrs: attrs || {}, accept: accept || [state], hold: hold || 2000 })
        switch (domain) {
        case "light": {
            if (service === "turn_off") return r("off")
            if (service !== "turn_on" && service !== "toggle") return null
            if (service === "toggle" && on) return r("off")
            const at = {}
            let bri = data.brightness
            if (typeof data.brightness_pct === "number") bri = Math.round(data.brightness_pct * 2.55)
            if (typeof bri === "number") at.brightness = Math.max(1, Math.min(255, bri))
            else if (!on && lastBri[id] !== undefined) at.brightness = lastBri[id]
            if (Array.isArray(data.hs_color)) { at.hs_color = data.hs_color; at.rgb_color = hsToRgb(data.hs_color[0], data.hs_color[1]); at.color_mode = "hs" }
            else if (Array.isArray(data.rgb_color)) { at.rgb_color = data.rgb_color; at.color_mode = "rgb" }
            else if (typeof data.color_temp_kelvin === "number") { at.color_temp_kelvin = data.color_temp_kelvin; at.color_mode = "color_temp" }
            return r("on", at)
        }
        case "switch": case "input_boolean":
            if (service === "turn_on") return r("on")
            if (service === "turn_off") return r("off")
            if (service === "toggle") return r(on ? "off" : "on")
            return null
        case "fan": {
            if (service === "turn_off") return r("off")
            if (service === "toggle" && on) return r("off")
            if (service === "set_percentage") return typeof data.percentage === "number" ? r(data.percentage > 0 ? "on" : "off", { percentage: data.percentage }) : null
            if (service === "turn_on" || service === "toggle") return r("on", typeof data.percentage === "number" ? { percentage: data.percentage } : {})
            return null
        }
        case "cover":
            if (service === "open_cover") return cur.state === "open" || cur.state === "opening" ? null : r("opening", {}, ["opening", "open"], 4000)
            if (service === "close_cover") return cur.state === "closed" || cur.state === "closing" ? null : r("closing", {}, ["closing", "closed"], 4000)
            return null
        case "climate":
            if (service === "turn_off") return r("off")
            if (service === "set_hvac_mode" && typeof data.hvac_mode === "string") return r(data.hvac_mode)
            if (service === "set_temperature" && typeof data.temperature === "number") return { state: null, attrs: { temperature: data.temperature }, accept: [], hold: 2000 }
            return null
        case "vacuum":                       // robots report slowly (cloud): longer hold
            if (service === "start") return r("cleaning", {}, ["cleaning"], 5000)
            if (service === "pause") return r("paused", {}, ["paused"], 5000)
            if (service === "return_to_base") return r("returning", {}, ["returning", "docked"], 5000)
            if (service === "stop") return r("idle", {}, ["idle", "paused", "docked"], 5000)
            if (service === "send_command" && data.command === "app_segment_clean") return r("cleaning", {}, ["cleaning"], 5000)
            return null
        case "dreame_vacuum": return service === "vacuum_clean_segment" ? r("cleaning", {}, ["cleaning"], 5000) : null
        }
        return null
    }
    function expectable(cur) { return cur && cur.state !== "unavailable" && cur.state !== "unknown" }

    // starts (or supersedes) the record for one entity and applies the prediction; returns it
    function begin(domain, service, id, data, seq) {
        const cur = byId[id]
        const pr = expectable(cur) ? predict(domain, service, id, data || {}, cur) : null
        const old = pend[id]
        const rec = { seq: seq, state: null, attrs: {}, accept: [], sentAt: Date.now(), doneAt: 0, holdUntil: 0, nextCheck: 0, hold: 2000, checking: false }
        if (old) { rec.state = old.state; rec.attrs = old.attrs; rec.accept = old.accept; rec.hold = old.hold }
        if (pr) {
            rec.attrs = old && pr.state !== "off" ? Object.assign({}, old.attrs, pr.attrs) : pr.attrs
            rec.state = pr.state; rec.accept = pr.accept; rec.hold = pr.hold
        }
        if (!old) pendCount++
        pend[id] = rec
        setBusy(id, false)
        setMerged(id)
        sweep.restart()
        return rec
    }
    // shows the expected result of a later call now (cleanAll sets the passes first)
    function expect(domain, service, id) { begin(domain, service, id, {}, ++seqCounter) }
    function drop(id, noRebuild) {
        if (!pend[id]) return
        delete pend[id]
        pendCount--
        setBusy(id, false)
        if (!noRebuild) setMerged(id)
    }
    function rollback(id, seq) { if (pend[id] && (seq === undefined || pend[id].seq === seq)) { drop(id); refreshOne(id) } }

    function matches(p, s) {
        if (p.state !== null && p.accept.indexOf(s.state) < 0) return false
        const a = s.attributes || {}, near = (k, tol) => typeof p.attrs[k] !== "number" || typeof a[k] !== "number" || Math.abs(p.attrs[k] - a[k]) <= tol
        return near("brightness", 8) && near("percentage", 5) && near("color_temp_kelvin", 200) && near("temperature", 0.2)
    }
    // a state of entity `id` arrived from a request that started at `startedAt`
    function reconcile(id, s, startedAt, batch) {
        const p = pend[id]
        if (!p || p.doneAt === 0 || startedAt < p.doneAt) return          // call still running, or a stale answer: keep predicting
        if (!s || matches(p, s) || Date.now() >= p.holdUntil) drop(id, batch)
        else p.nextCheck = Math.min(p.nextCheck, Date.now() + 500)
    }
    function refreshOne(id) {
        const p = pend[id]
        if (p) { if (p.checking) return; p.checking = true }
        request("GET", "/api/states/" + id, null, (st, txt, timedOut, startedAt) => {
            const q = pend[id]
            if (q) { q.checking = false; q.nextCheck = Date.now() + 600 }
            if (st !== 200) return
            let s = null
            try { s = JSON.parse(txt) } catch (e) { s = null }
            if (!s || s.entity_id !== id) return
            s.attributes = s.attributes || {}
            if (serverById[id]) {
                const was = serverById[id].state
                serverById[id] = s
                noteBri(s)
                reconcile(id, s, startedAt)
                setMerged(id)
                if ((was === "unavailable") !== (s.state === "unavailable")) regroup()
            } else if (helpers[id]) {
                helpers[id] = s
                reconcile(id, s, startedAt)
            }
            updated()
        })
    }
    // 100 ms while records exist: "syncing" mark after 1.2 s, single-entity checks after a reply, hard cap
    Timer {
        id: sweep
        interval: 100; repeat: true
        running: ha.pendCount > 0
        onTriggered: {
            const now = Date.now()
            for (const id of Object.keys(ha.pend)) {
                const p = ha.pend[id]
                ha.setBusy(id, now - p.sentAt > 1200)
                if (p.doneAt > 0 && now >= p.nextCheck && !p.checking) ha.refreshOne(id)
                if (p.doneAt > 0 && now > p.holdUntil + 4000) ha.drop(id)          // nothing answered: the server state wins
            }
        }
    }

    // POST /api/services/<domain>/<service> {entity_id, ...data}. The expected result shows at once (see the optimistic
    // layer); done() runs on success, fail() on error (chained calls).
    function call(domain, service, entityId, data, done, fail) {
        if (!configured) return
        const body = Object.assign({ entity_id: entityId }, data || {})
        const seq = ++seqCounter
        touch()
        begin(domain, service, entityId, data, seq)
        if (service === "turn_on" && ["scene", "script", "button"].indexOf(domain) >= 0) {
            const k = Object.assign({}, acked); k[entityId] = true; acked = k
            ackClear.restart()
        }
        request("POST", "/api/services/" + domain + "/" + service, body, (st, txt) => {
            if (st < 200 || st >= 300) {
                actionError = (st === 0 ? "No reply" : "HTTP " + st) + " for " + domain + "." + service
                errClear.restart()
                rollback(entityId, seq)
                if (fail) fail()
                return
            }
            const p = pend[entityId]
            if (p && p.seq === seq) { p.doneAt = Date.now(); p.holdUntil = p.doneAt + p.hold; p.nextCheck = p.doneAt + 250 }
            if (done) done()
        }, 6000)
    }
    Timer { id: ackClear; interval: 1000; onTriggered: ha.acked = ({}) }
    Timer { id: errClear; interval: 6000; onTriggered: ha.actionError = "" }

    // the popup re-reads the secrets file on open (a token added since then is picked up)
    onPanelOpenChanged: if (panelOpen) { secrets.reload(); refresh(true) }

    Timer {
        interval: ha.failed ? (ha.panelOpen ? 15000 : 120000) : ha.panelOpen ? 4000 : 60000
        repeat: true
        running: ha.configured && (ha.panelOpen || BarWidgets.shown("homeassistant"))
        onTriggered: if (Date.now() >= ha.interactUntil && ha.pendCount === 0) ha.refresh()      // not mid-interaction
    }
}
