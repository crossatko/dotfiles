import QtQuick
import QtWebSockets

// A few Home Assistant entities kept live over HA's websocket API (/api/websocket: auth, then subscribe_entities with
// these ids; HA pushes the full states once, then only the changes). No polling. `entities` = { entity_id: { entity_id,
// state, attributes } } of what HA sent (an id HA does not know stays absent); emptied while not subscribed. Same URL /
// token as HomeAssistant (the token goes only into the auth message). Reconnects with a backoff (2 s doubling to 60 s);
// a new id list or URL / token resubscribes. Loaded by TvSession through a Loader (QtWebSockets missing = Loader error:
// TvSession then reads the states over REST).
Item {
    id: w
    visible: false
    property var ids: []
    readonly property string base: HomeAssistant.base || HomeAssistant.url
    readonly property string wsUrl: base.replace(/^http/i, "ws") + "/api/websocket"
    readonly property string want: HomeAssistant.configured && base !== "" && ids.length > 0 ? wsUrl + " " + ids.join(",") : ""
    property var entities: ({})
    property bool live: false              // authenticated + subscribed
    property int failures: 0
    property int nextId: 1
    property bool closing: false           // our own close: no retry from it

    function reopen() {
        closing = true; sock.active = false; closing = false
        if (want !== "") { sock.url = wsUrl; sock.active = true }
    }

    onWantChanged: Qt.callLater(restart)
    Component.onCompleted: restart()
    function restart() {
        retry.stop()
        live = false
        entities = ({})
        failures = 0
        reopen()
    }
    function send(o) { sock.sendTextMessage(JSON.stringify(o)) }
    // HA's compressed state: { s, a, c, lc, lu }; a change: { "+": { s?, a? (changed attributes) }, "-": { a: [removed] } }
    function handle(text) {
        let m
        try { m = JSON.parse(text) } catch (e) { return }
        if (!m) return
        if (m.type === "auth_required") send({ type: "auth", access_token: HomeAssistant.token })
        else if (m.type === "auth_ok") { failures = 0; send({ id: nextId++, type: "subscribe_entities", entity_ids: ids }) }
        else if (m.type === "auth_invalid") { console.log("homeassistant: websocket token rejected"); failures = 5; sock.active = false }
        else if (m.type === "result" && !m.success) { console.log("homeassistant: subscribe_entities failed"); sock.active = false }
        else if (m.type === "event" && m.event) {
            const e = m.event
            const s = Object.assign({}, entities)
            if (e.a) for (const id in e.a) { const x = e.a[id] || {}; s[id] = { entity_id: id, state: String(x.s), attributes: x.a || {} } }
            if (e.c) for (const id in e.c) {
                if (!s[id]) continue
                const d = e.c[id] || {}
                const n = { entity_id: id, state: s[id].state, attributes: Object.assign({}, s[id].attributes) }
                if (d["+"]) { if (d["+"].s !== undefined) n.state = String(d["+"].s); if (d["+"].a) Object.assign(n.attributes, d["+"].a) }
                if (d["-"] && Array.isArray(d["-"].a)) for (const k of d["-"].a) delete n.attributes[k]
                s[id] = n
            }
            if (Array.isArray(e.r)) for (const id of e.r) delete s[id]
            entities = s
            live = true
        }
    }

    WebSocket {
        id: sock
        active: false
        onTextMessageReceived: message => w.handle(message)
        onStatusChanged: {
            if (sock.status !== WebSocket.Error && sock.status !== WebSocket.Closed || w.closing) return
            w.live = false
            w.entities = ({})
            if (w.want !== "") retry.restart()
        }
    }
    Timer {
        id: retry
        interval: Math.min(60000, 2000 * Math.pow(2, Math.min(5, w.failures)))
        onTriggered: { w.failures++; w.reopen() }
    }
}
