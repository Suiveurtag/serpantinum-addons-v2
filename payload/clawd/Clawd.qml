pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"

// Exists separately in the shell and the Settings process; share state only through Config.
QtObject {
    id: clawd
    readonly property bool enabled: Config.getSetting("addonsV2Clawd", false) === true
    readonly property int scale: Math.max(2, Math.min(8, Math.round(Number(Config.getSetting("addonsV2ClawdScale", 4))) || 4))
    readonly property string speed: ["calm", "normal", "active"].indexOf(Config.getSetting("addonsV2ClawdSpeed", "normal")) >= 0 ? Config.getSetting("addonsV2ClawdSpeed", "normal") : "normal"
    readonly property int sleepMinutes: Math.max(1, Math.min(60, Math.round(Number(Config.getSetting("addonsV2ClawdSleep", 5))) || 5))
    readonly property bool lowMotion: Config.getSetting("general.performance", false) === true
    // Thought line above his head while an agent works: full (verb + actions + stats), verbs, off.
    readonly property string thoughts: ["full", "verbs", "off"].indexOf(Config.getSetting("addonsV2ClawdThoughts", "full")) >= 0 ? Config.getSetting("addonsV2ClawdThoughts", "full") : "full"
    // The windows around him (perching, peeking, exploring, window reactions); following the cursor to another screen.
    readonly property bool world: Config.getSetting("addonsV2ClawdWorld", true) !== false
    readonly property bool follow: Config.getSetting("addonsV2ClawdFollow", true) !== false
    property string screenName: ""
    property int instances: 0
    property var manifest: null
    readonly property string scripts: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/clawd"
    // Claude Code / Codex sessions from the hook socket (shell process only):
    // "agent:session_id" -> {agent, dir, phase, last, tool, target, pids, since, verb, verbAt, model, effort, ctx, cost, five_hour, seven_day};
    // tool/target = last tool used this turn and its short target, pids = the hook's ancestors, stats from the status line relay.
    // phase: work | alert | idle. Kept while Clawd is OFF so he shows the right state when he comes back.
    property var sessions: ({})
    // Quota windows: "agent:five_hour|seven_day" -> {used, resets, fired}; used % going from below 100 to 100 sets off the
    // limit scene (the singularity or the nuke, at random), once per window (fired = the resets_at it went off for).
    property var quotas: ({})
    property var bubble: null      // {key, kind: permission | done | waiting | error, text}
    property int staleMs: 120000
    property var verbs: ["Thinking"]   // Claude Code's spinner verbs (verbs.py), until loaded
    property real verbsAt: 0
    property var dice: null        // test hook: a fixed roll in [0, 1) instead of Math.random()
    readonly property string activity: {
        const phases = Object.values(sessions).map(s => s.phase);
        return phases.indexOf("alert") >= 0 ? "alert" : phases.indexOf("work") >= 0 ? "work" : "";
    }
    // The lead: the working session that moved last; he plays its tool and thinks its thoughts.
    readonly property var lead: {
        let best = null;
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "work" && (!best || s.last >= best.last)) best = Object.assign({ key }, s);
        return best;
    }
    readonly property string workAnim: toolAnim(lead ? lead.tool : "")
    readonly property bool strained: !!lead && (lead.ctx >= 80 || lead.five_hour >= 90)
    readonly property real effortSpeed: lead ? effortRate(lead.effort) : 1
    readonly property bool thinking: thoughts !== "off" && activity === "work" && !!lead
    readonly property int busyCount: Object.values(sessions).filter(s => s.phase !== "idle").length

    // Claude Code and Codex tool names -> his working loop; anything else (MCP...) types.
    function toolAnim(tool) {
        const t = String(tool || "");
        if (["Read", "NotebookRead", "view_image"].indexOf(t) >= 0) return "read";
        if (["Bash", "BashOutput", "KillShell", "exec_command", "write_stdin", "shell", "local_shell"].indexOf(t) >= 0) return "bash";
        if (["Grep", "Glob", "LS", "ToolSearch"].indexOf(t) >= 0) return "search";
        if (["WebFetch", "WebSearch", "web_search"].indexOf(t) >= 0) return "web";
        if (["Task", "Agent", "spawn_agent"].indexOf(t) >= 0) return "task";
        if (["TodoWrite", "update_plan"].indexOf(t) >= 0) return "todo";
        if (["Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch"].indexOf(t) >= 0) return "edit";
        return "work";
    }
    function effortRate(effort) {
        const v = ({ low: 0.75, medium: 1, high: 1.25, xhigh: 1.5, max: 1.5 })[effort];
        return typeof v === "number" ? v : 1;
    }
    function roll() { return typeof dice === "number" ? dice : Math.random(); }
    function pick(list) { return list[Math.min(list.length - 1, Math.floor(roll() * list.length))]; }
    // name or its "_2" variant when the manifest has one, at random.
    function variant(name) { return manifest && manifest.animations[name + "_2"] && roll() < 0.5 ? name + "_2" : name; }

    // Thought line pieces, pure so they can be checked without waiting.
    function clip(text, n) { text = String(text); return text.length > n ? text.slice(0, Math.max(0, n - 1)) + "…" : text; }
    function elapsed(ms) {
        const s = Math.max(0, Math.floor(ms / 1000)), pad = n => (n < 10 ? "0" : "") + n;
        return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m " + pad(s % 60) + "s" : Math.floor(s / 3600) + "h " + pad(Math.floor(s / 60) % 60) + "m";
    }
    function actionText(s) { return s && s.tool ? clip(s.target ? s.tool + " " + s.target : s.tool, 40) : ""; }
    // What the info cycle can show for a session, strained values flagged.
    function infos(s) {
        if (!s) return [];
        const out = [], pct = v => Math.round(v) + "%";
        if (s.model) out.push({ text: s.model + (s.effort ? " · " + s.effort : ""), warn: false });
        if (Number.isFinite(s.ctx)) out.push({ text: "ctx " + pct(s.ctx), warn: s.ctx >= 80 });
        if (Number.isFinite(s.cost)) out.push({ text: "$" + s.cost.toFixed(2), warn: false });
        if (Number.isFinite(s.five_hour)) out.push({ text: "5h " + pct(s.five_hour) + (Number.isFinite(s.seven_day) ? " · 7d " + pct(s.seven_day) : ""), warn: s.five_hour >= 90 });
        return out;
    }
    // The i-th info to show; warnings win over everything else.
    function nextInfo(s, i) {
        const all = infos(s), warn = all.filter(x => x.warn), pool = warn.length ? warn : all;
        return pool.length ? pool[i % pool.length] : null;
    }
    // {text, warn, suffix} for mode, lead session s, clock now and a flash/info override; null = nothing to show.
    function thought(mode, s, now, extra) {
        if (!s || mode === "off") return null;
        if (extra && mode === "full") return { text: clip(extra.text, 40), warn: !!extra.warn, suffix: "" };
        const suffix = " " + elapsed(now - s.since);
        return { text: clip((s.verb || verbs[0] || "Thinking") + "…", 40 - suffix.length), warn: false, suffix };
    }
    signal command(string name, string arg)
    signal sessionStarted()   // a new agent session (not a compaction restart): revives a dead Clawd

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
        // control characters and bidi overrides out of everything shown
        const str = (v, n) => typeof v === "string" ? v.replace(/[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "").slice(0, n) : "";
        const dir = str(e.dir, 40) || (was ? was.dir : "");
        const where = dir || e.agent;
        const pids = Array.isArray(e.pids) ? e.pids.filter(p => Number.isInteger(p) && p > 1).slice(0, 16) : [];
        const now = Date.now();
        const model = str(e.model, 40);
        // stats, verb and target carry over; extra overrides
        const set = (phase, tool, fresh, extra) => {
            next[key] = Object.assign({ target: "" }, was, { agent: e.agent, dir, phase, last: now, tool: tool !== undefined ? tool : was ? was.tool : "",
                pids: pids.length ? pids : was ? was.pids : [], since: !fresh && was ? was.since : now }, model ? { model } : {}, extra || {});
        };
        let react = "", fresh = false;
        switch (e.event) {
        case "SessionStart":
            // Claude starts the session again after each compaction (source "compact"): no greeting then
            react = was && was.compacting ? "" : "wave";
            fresh = react === "wave";
            if (was && (model || was.compacting)) set(was.phase, undefined, false, { compacting: false });
            loadVerbs();
            break;
        case "UserPromptSubmit": set("work", "", true, { target: "", verb: pick(verbs), verbAt: now }); react = variant("think"); dismiss(key); break;
        case "PreCompact": set(was ? was.phase : "work", undefined, false, { compacting: true }); react = "compact"; break;
        case "PreToolUse":
        case "PostToolUse":
        case "PostToolUseFailure":
            // Claude's async hooks may land after Stop: only a new prompt revives an idle session
            if (was && was.phase === "idle") { set("idle"); break; }
            set("work", typeof e.tool_name === "string" ? e.tool_name.slice(0, 40) : undefined, false, e.event === "PreToolUse" ? { target: str(e.target, 24) } : null);
            dismiss(key, "permission");
            if (e.event === "PostToolUseFailure") react = "oops";
            break;
        case "Notification":
            if (e.notification_type === "permission_prompt") { set("alert"); say(key, "permission", "⚠ permission · " + where); }
            else if (["idle_prompt", "agent_needs_input"].indexOf(e.notification_type) >= 0) {
                if (was) set(was.phase);
                if (!bubble || bubble.kind !== "permission") say(key, "waiting", "… waiting · " + where);
            } else return;
            break;
        case "Stop":
            react = was && was.phase !== "idle" && now - was.since >= 180000 ? "celebrate" : variant("happy");  // long turns get confetti
            set("idle"); say(key, "done", "✓ done · " + where);
            break;
        case "StopFailure": set("idle"); react = "sad"; say(key, "error", "✗ error · " + where); break;
        case "Status": {
            // the status line relay: stats only, never a phase change (an unknown session starts idle)
            const s = Object.assign({ agent: e.agent, phase: "idle", last: now, tool: "", target: "", pids, since: now }, was, { dir });
            if (pids.length) s.pids = pids;
            if (model) s.model = model;
            if (str(e.effort, 16)) s.effort = str(e.effort, 16);
            for (const k of ["ctx", "cost", "five_hour", "seven_day", "five_hour_resets", "seven_day_resets"]) if (typeof e[k] === "number" && Number.isFinite(e[k])) s[k] = e[k];
            if (was && Number.isFinite(was.cost) && Number.isFinite(s.cost) && Math.floor(s.cost / 5) > Math.floor(was.cost / 5)) react = "coin";
            if (exhausted(e.agent, e)) react = "limit";
            // status refreshes are frequent: no churn when nothing moved
            if (!react && was && Object.keys(s).length === Object.keys(was).length && Object.keys(s).every(k => JSON.stringify(s[k]) === JSON.stringify(was[k]))) return;
            next[key] = s;
            break;
        }
        case "Interrupt": set("idle"); dismiss(key); break;
        case "SessionEnd": delete next[key]; dismiss(key); break;
        default: return;
        }
        sessions = next;
        if (react) command("react", react);
        if (fresh) sessionStarted();
    }
    // A status snapshot's used % per window (five_hour, seven_day are per account, whatever the session): true when one
    // just reached 100 from below. A value first seen at 100 (shell restart) only primes it; a new window rearms it.
    function exhausted(agent, e) {
        let hit = false;
        const next = Object.assign({}, quotas);
        for (const w of ["five_hour", "seven_day"]) {
            const used = e[w], resets = Number.isFinite(e[w + "_resets"]) ? e[w + "_resets"] : 0;
            if (!Number.isFinite(used)) continue;
            const key = agent + ":" + w, was = next[key];
            const fired = was && was.resets === resets ? was.fired : false;
            const crossed = !!was && was.used < 100 && used >= 100 && !fired;
            next[key] = { used, resets, fired: fired || crossed };
            hit = hit || crossed;
        }
        if (JSON.stringify(next) !== JSON.stringify(quotas)) quotas = next;
        return hit;
    }
    readonly property QtObject codexTimer: Timer {
        interval: 30000; repeat: true; running: clawd.enabled
        triggeredOnStart: true; onTriggered: if (!codexProc.running) codexProc.running = true
    }
    readonly property QtObject codexProc: Process {
        command: ["python3", clawd.scripts + "/codex_limits.py"]
        stdout: StdioCollector { onStreamFinished: if (text) clawd.ingest(text) }
    }
    // Raise the terminal window running that session: the first of its hook's ancestors that owns a Hyprland window.
    function focus(key) {
        const s = sessions[key];
        if (!s || !s.pids || !s.pids.length || focusProc.running) return;
        focusProc.pids = s.pids;
        focusProc.running = true;
    }
    readonly property QtObject focusProc: Process {
        property var pids: []
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = [];
                try { clients = JSON.parse(text); } catch (error) { return; }
                const owners = new Set(clients.map(c => c.pid));
                const pid = clawd.focusProc.pids.find(p => owners.has(p));
                if (pid) Hyprland.dispatch("focuswindow pid:" + pid);
            }
        }
    }
    // A new verb every ~30 s for each working session.
    function reroll() {
        const now = Date.now();
        let next = null;
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "work" && now - (s.verbAt || 0) >= 30000) {
            next = next || Object.assign({}, sessions);
            next[key] = Object.assign({}, s, { verb: pick(verbs), verbAt: now });
        }
        if (next) sessions = next;
    }
    readonly property QtObject verbTimer: Timer { interval: 5000; repeat: true; running: clawd.enabled && clawd.thinking; onTriggered: clawd.reroll() }
    // Spinner verbs from the installed Claude Code (cached by verbs.py); again on session starts, at most every 30 s.
    function loadVerbs() {
        if (verbsProc.busy || Date.now() - verbsAt < 30000) return;
        verbsAt = Date.now();
        verbsProc.busy = true;
        verbsProc.running = true;
    }
    function takeVerbs(text) {
        let r = null;
        try { r = JSON.parse(text); } catch (error) { return; }
        const list = r && r.ok && r.data && Array.isArray(r.data.verbs) ? r.data.verbs.filter(v => typeof v === "string" && v && v.length <= 40) : [];
        if (list.length) verbs = list;
    }
    readonly property QtObject verbsProc: Process {
        property bool busy: false  // Process.running only flips once the process has started
        command: ["python3", clawd.scripts + "/verbs.py"]
        stdout: StdioCollector { onStreamFinished: { clawd.verbsProc.busy = false; clawd.takeVerbs(text); } }
        onExited: busy = false
    }
    Component.onCompleted: loadVerbs()
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
        // the limit scenes (limit = either at random) and the revival are scenes, not strips
        if (!manifest || ["limit", "nuke", "revive"].indexOf(name) < 0 && !Object.prototype.hasOwnProperty.call(manifest.animations, name)) return "unknown";
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
