pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Exists separately in the shell and the Settings process; share state only through Config.
QtObject {
    id: clawd
    readonly property bool enabled: Config.getSetting("addonsV2Clawd", false) === true
    readonly property int scale: Math.max(2, Math.min(8, Math.round(Number(Config.getSetting("addonsV2ClawdScale", 4))) || 4))
    readonly property string speed: ["calm", "normal", "active"].indexOf(Config.getSetting("addonsV2ClawdSpeed", "normal")) >= 0 ? Config.getSetting("addonsV2ClawdSpeed", "normal") : "normal"
    readonly property int sleepMinutes: Math.max(1, Math.min(60, Math.round(Number(Config.getSetting("addonsV2ClawdSleep", 5))) || 5))
    readonly property bool lowMotion: Config.getSetting("general.performance", false) === true
    property string screenName: ""
    property int instances: 0
    property var manifest: null
    signal command(string name, string arg)

    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }

    function play(name) {
        if (!enabled) return "off";
        if (!manifest || !Object.prototype.hasOwnProperty.call(manifest.animations, name)) return "unknown";
        command("play", name);
        return "ok";
    }

    function load(text) {
        try {
            const m = JSON.parse(text);
            if (m && m.frame && m.frame.w > 0 && m.frame.h > 0 && m.animations && typeof m.animations === "object") manifest = m;
            else console.warn("Clawd: invalid sprites/clawd.json");
        } catch (error) { console.warn("Clawd: bad sprites/clawd.json", error); }
    }

    readonly property QtObject manifestFile: FileView {
        path: decodeURIComponent(Qt.resolvedUrl("sprites/clawd.json").toString().replace("file://", ""))
        onLoaded: clawd.load(text())
        onLoadFailed: error => console.warn("Clawd: sprites/clawd.json not loaded", error)
    }
}
