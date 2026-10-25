.pragma library

// Pure helpers for the Bluetooth connect/disconnect notifications (BtNotifier.qml): which icon, title and body a
// device gets. No state, no processes. A "device" is anything with name, icon (BlueZ icon name), batteryAvailable
// and battery (0..1); `pods` is the AirPods singleton (or a plain object of the same shape) for the AirPods body.

// BlueZ `icon` -> Adwaita symbolic icon name (NotifIcon tints those with the accent)
var ICONS = {
    "audio-headset": "audio-headset",
    "audio-headphones": "audio-headphones",
    "audio-card": "audio-speakers",
    "audio-speakers": "audio-speakers",
    "input-keyboard": "input-keyboard",
    "input-mouse": "input-mouse",
    "input-gaming": "input-gaming",
    "input-tablet": "input-tablet",
    "input-touchpad": "input-touchpad",
    "phone": "phone",
    "computer": "computer",
    "camera-photo": "camera-photo",
    "camera-video": "camera-video",
    "camera-web": "camera-web",
    "printer": "printer",
    "multimedia-player": "multimedia-player",
    "video-display": "tv"
};
var FALLBACK_ICON = "bluetooth";

function isAirPods(dev, pods) {
    if (!dev) return false;
    if (/airpods/i.test(String(dev.name || ""))) return true;
    return !!pods && pods.connected === true && !!dev.name && dev.name === pods.name;
}

function iconName(dev) {
    return (dev && ICONS[String(dev.icon || "")]) || FALLBACK_ICON;
}

// the notification's icon: AirPods get the drawing from assets/, the rest a symbolic name
function icon(dev, pods, assetsDir) {
    return isAirPods(dev, pods) ? assetsDir + "/airpods-pro-buds.svg" : iconName(dev);
}

function title(dev, connected) {
    var n = dev && dev.name ? String(dev.name) : "Bluetooth device";
    return n + (connected ? " connected" : " disconnected");
}

function pct(level) { return Math.round(level) + "%"; }

// "L 79% · R 100% · Case 55%" (only the parts heard from); "" when nothing is known yet
function podsBody(pods) {
    if (!pods) return "";
    var out = [];
    if (pods.headset) {
        if (pods.max && pods.max.level >= 0) out.push(pct(pods.max.level));
    } else {
        if (pods.left && pods.left.level >= 0) out.push("L " + pct(pods.left.level));
        if (pods.right && pods.right.level >= 0) out.push("R " + pct(pods.right.level));
        if (pods.box && pods.box.level >= 0) out.push("Case " + pct(pods.box.level));
    }
    return out.join(" · ");
}

// whether the AirPods daemon has reported a battery for this connection yet (the connect notice waits for it)
function podsReady(pods) { return podsBody(pods) !== ""; }

function body(dev, pods, connected) {
    if (!connected) return "";
    if (isAirPods(dev, pods)) return podsBody(pods);
    return dev && dev.batteryAvailable ? "Battery " + pct(dev.battery * 100) : "";
}

// argv for notify-send (never a shell string): low urgency, short timeout, own app name
function argv(dev, pods, connected, assetsDir) {
    var a = ["notify-send", "-a", "Bluetooth", "-u", "low", "-t", connected ? "5000" : "4000",
             "-i", icon(dev, pods, assetsDir), "--", title(dev, connected)];
    var b = body(dev, pods, connected);
    if (b !== "") a.push(b);
    return a;
}
