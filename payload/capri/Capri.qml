pragma Singleton
import QtQuick
import Quickshell
import "../"

// Exists separately in the shell and the Settings process; share state only through Config.
QtObject {
    id: capri
    readonly property bool enabled: Config.getSetting("addonsV2Capri", false)
    readonly property bool animationEnabled: enabled && !Config.getSetting("general.performance", false)
    readonly property string scripts: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/capri"
    readonly property var hookEvents: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "PreCompact", "SessionEnd", "Interrupt", "CapriShowcase"]
    property string screenName: ""
    property int instances: 0
    property int events: 0
    property var lastEvent: null
    signal hookEvent(var evt)

    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }

    // Trust boundary: anything on 127.0.0.1 or the IPC socket can reach this.
    function accept(evt) {
        if (!evt || typeof evt !== "object" || Array.isArray(evt) || hookEvents.indexOf(evt.hook_event_name) < 0) return false;
        events++;
        lastEvent = evt;
        hookEvent(evt);
        return true;
    }

    // One JSON line from the sidecar: {"t":"event","evt":{...}}.
    function ingest(line) {
        let message;
        try { message = JSON.parse(line); } catch (error) { console.warn("Capri: bad sidecar line", line.slice(0, 120)); return; }
        if (message && message.t === "event") accept(message.evt);
    }
}
