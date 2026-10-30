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
    readonly property string scripts: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/clawd"
    // Claude Code / Codex sessions from the hook socket (shell process only): "agent:session_id" -> {agent, dir, phase, last}.
    // phase: work | alert | idle. Kept while Clawd is OFF so he shows the right state when he comes back.
    property var sessions: ({})
    property var bubble: null      // {key, kind: permission | done | waiting, text}
    property int staleMs: 120000
    readonly property string activity: {
        const phases = Object.values(sessions).map(s => s.phase);
        return phases.indexOf("alert") >= 0 ? "alert" : phases.indexOf("work") >= 0 ? "work" : "";
    }
    signal command(string name, string arg)

    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }

    // One hook line. The socket is a trust boundary: parse defensively, whitelist, cap, never execute.
    function ingest(line) {
        let e;
        try { e = JSON.parse(line); } catch (error) { return; }
        if (!e || typeof e !== "object" || ["claude", "codex"].indexOf(e.agent) < 0 || typeof e.event !== "string") return;
        const key = e.agent + ":" + (typeof e.session_id === "string" && e.session_id ? e.session_id.slice(0, 80) : "default");
        const next = Object.assign({}, sessions);
        const was = next[key];
        const dir = typeof e.dir === "string" && e.dir ? e.dir.slice(0, 40) : was ? was.dir : "";
        const where = dir || e.agent;
        const set = phase => { next[key] = { agent: e.agent, dir, phase, last: Date.now() }; };
        let react = "";
        switch (e.event) {
        case "SessionStart": react = "spawn"; break;
        case "UserPromptSubmit": set("work"); react = "think"; dismiss(key); break;
        case "PreToolUse":
        case "PostToolUse":
        case "PostToolUseFailure":
            // Claude's async hooks may land after Stop: only a new prompt revives an idle session
            if (was && was.phase === "idle") { set("idle"); break; }
            set("work");
            dismiss(key, "permission");
            if (e.event === "PostToolUseFailure") react = "oops";
            break;
        case "Notification":
            if (e.notification_type === "permission_prompt") { set("alert"); say(key, "permission", "⚠ permission · " + where); }
            else if (["idle_prompt", "agent_needs_input"].indexOf(e.notification_type) >= 0) {
                if (was) set(was.phase);
                if (!bubble || bubble.kind !== "permission") say(key, "waiting", "… attend · " + where);
            } else return;
            break;
        case "Stop": set("idle"); react = "happy"; say(key, "done", "✓ terminé · " + where); break;
        case "Interrupt": set("idle"); dismiss(key); break;
        case "SessionEnd": delete next[key]; dismiss(key); break;
        default: return;
        }
        sessions = next;
        if (react) command("react", react);
    }
    function say(key, kind, text) { bubble = { key, kind, text }; }
    function dismiss(key, kind) {
        if (bubble && (key === undefined || bubble.key === key) && (kind === undefined || bubble.kind === kind)) bubble = null;
    }
    // A pending permission never times out: the agent really is waiting for the user.
    function purge() {
        const now = Date.now(), next = {};
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "alert" || now - s.last < staleMs) next[key] = s;
        if (Object.keys(next).length !== Object.keys(sessions).length) sessions = next;
    }
    readonly property QtObject purgeTimer: Timer {
        interval: Math.min(10000, clawd.staleMs / 4); repeat: true
        running: Object.keys(clawd.sessions).length > 0
        onTriggered: clawd.purge()
    }
    readonly property QtObject bubbleTimer: Timer { interval: 8000; onTriggered: clawd.bubble = null }
    onBubbleChanged: bubble && bubble.kind !== "permission" ? bubbleTimer.restart() : bubbleTimer.stop()

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
