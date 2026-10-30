import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"

// Clawd himself, in global logical pixels: x/y is his top-left corner, every ClawdOverlay draws him from here.
// mode: spawn, idle, walk, turn, sit, sleep, drag, fall, land, play.
Item {
    id: pet
    readonly property bool hypr: Hyprland.requestSocketPath !== ""
    readonly property var displays: {
        const monitors = hypr ? Hyprland.monitors.values : [];
        return Quickshell.screens.map(s => {
            const m = monitors.find(m => m.name === s.name) || null;
            const ipc = m && m.lastIpcObject || {};
            const y = m ? m.y : s.y;
            return { id: s.name, x: m ? m.x : s.x, y, w: s.width, h: s.height,
                floor: y + s.height - Math.max(0, (ipc.reserved || [0, 0, 0, 0])[3] || 0) };
        });
    }
    readonly property var here: display(Clawd.screenName)
    readonly property int summon: Config.getSetting("addonsV2ClawdSummon", 0)
    readonly property alias frame: clock.frame
    property string mode: "spawn"
    property string animation: "spawn"
    property bool mirrored: false
    property bool reverse: false
    property bool menuOpen: false
    property int sleepAfter: Clawd.sleepMinutes * 60000
    property var target: null      // walk destination x
    property var grab: null        // left press: {x, y, dx, dy, moved}
    property var pointer: null     // global cursor, polled from Hyprland
    property real vy: 0
    property real last: 0
    property bool tired: false
    property string cursorBuffer: ""
    width: Clawd.manifest ? Clawd.manifest.frame.w * Clawd.scale : 0
    height: Clawd.manifest ? Clawd.manifest.frame.h * Clawd.scale : 0

    function display(name) { return displays.find(d => d.id === name) || null; }
    function displayAt(gx, gy) {
        let best = null, gap = Infinity;
        for (const d of displays) {
            const dx = Math.max(d.x - gx, 0, gx - d.x - d.w), dy = Math.max(d.y - gy, 0, gy - d.y - d.h);
            if (dx + dy < gap) { gap = dx + dy; best = d; }
        }
        return best;
    }
    function refresh() { if (hypr) Hyprland.refreshMonitors(); }
    function clampX(d, v) { return Math.max(d.x, Math.min(d.x + d.w - width, v)); }

    function enter(m, anim, flip, back) {
        mode = m;
        mirrored = !!flip;
        reverse = !!back;
        animation = anim;
        clock.restart();
        last = Date.now();
        const clip = Clawd.manifest && Clawd.manifest.animations[anim];
        brain.stop();
        if (m === "idle" && anim === "idle") brain.interval = pause();
        else if (m === "sit") brain.interval = 5000 + Math.random() * 7000;
        else if (m === "play" && clip && clip.loop) brain.interval = 3000;
        else return;
        brain.start();
    }
    function pause() {
        if (Clawd.lowMotion) return 20000 + Math.random() * 20000;
        const base = ({ calm: 5000, normal: 3000, active: 2000 })[Clawd.speed];
        return base + Math.random() * base * 1.2;
    }
    function next() {
        if (mode === "turn" && target !== null) enter("walk", "walk", mirrored);
        else if (["sleep", "drag", "fall", "walk"].indexOf(mode) < 0) idle();
    }
    function idle() {
        target = null;
        if (here && y < here.floor - height - 0.5) { vy = 0; enter("fall", "fall"); }
        else if (tired) sleep();
        else enter("idle", "idle");
    }
    function think() {
        refresh();
        const chance = Clawd.lowMotion ? 0.1 : ({ calm: 0.25, normal: 0.4, active: 0.6 })[Clawd.speed];
        const r = Math.random(), rest = (r - chance) / (1 - chance);
        if (menuOpen) enter("idle", "idle");
        else if (r < chance) walk();
        else if (rest < 0.35) enter("idle", "blink");
        else if (rest < 0.7 && !Clawd.lowMotion) enter("idle", look());
        else if (rest < 0.85) enter("sit", "sit");
        else enter("idle", "idle");
    }
    function look() {
        if (!pointer) return ["look_left", "look_right", "look_up"][Math.floor(Math.random() * 3)];
        const dx = pointer.x - (x + width / 2), dy = pointer.y - y;
        return dy < 0 && -dy > Math.abs(dx) ? "look_up" : dx < 0 ? "look_left" : "look_right";
    }
    function walk() {
        const d = here;
        if (!d || d.w <= width) return enter("idle", "idle");
        const distance = 80 + Math.random() * Math.min(400, d.w - width);
        let to = x + (Math.random() < 0.5 ? -distance : distance);
        if (clampX(d, to) !== to) to = 2 * x - to;
        target = clampX(d, to);
        if (Math.abs(target - x) < 8) idle();
        else enter("turn", "turn", target < x);
    }
    function step() {
        const now = Date.now(), dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        if (mode === "walk") {
            const v = ({ calm: 30, normal: 60, active: 100 })[Clawd.speed] * dt, left = target - x;
            if (Math.abs(left) > v) { x += left > 0 ? v : -v; return; }
            x = target;
            target = null;
            enter("turn", "turn", mirrored, true);
        } else if (mode === "fall" && here) {
            vy = Math.min(2400, vy + 2600 * dt);
            y = Math.min(here.floor - height, y + vy * dt);
            if (y >= here.floor - height) { vy = 0; enter("land", "land"); }
        }
    }
    function ground() {
        if (!here || ["drag", "fall"].indexOf(mode) >= 0) return;
        x = clampX(here, x);
        y = here.floor - height;
    }

    function spawn() {
        refresh();
        const f = hypr && Hyprland.focusedMonitor ? display(Hyprland.focusedMonitor.name) : null;
        const d = f || displays[0];
        if (!d) return;
        grab = null;
        menuOpen = false;
        Clawd.screenName = d.id;
        x = Math.round(d.x + (d.w - width) / 2);
        y = d.floor - height;
        touch();
        target = null;
        enter("spawn", "spawn");
    }
    function touch() {
        tired = false;
        drowsy.restart();
    }
    function sleep() {
        target = null;
        tired = false;
        drowsy.stop();
        if (here && y < here.floor - height - 0.5) return idle();
        enter("sleep", "sleep");
    }
    function wake() {
        touch();
        if (mode === "sleep") enter("idle", "blink");
    }
    function perform(name) {
        if (!Clawd.manifest || !Clawd.manifest.animations[name] || grab && grab.moved) return;
        touch();
        target = null;
        enter("play", name);
    }

    // Input from the overlay where the press started, already in global coordinates.
    function press(button, gx, gy) {
        touch();
        if (button === Qt.RightButton) { openMenu(); return; }
        grab = { x: gx, y: gy, dx: gx - x, dy: gy - y, moved: false };
    }
    function move(gx, gy) {
        if (!grab) return;
        if (!grab.moved && Math.abs(gx - grab.x) + Math.abs(gy - grab.y) < 4) return;
        if (!grab.moved) {
            grab.moved = true;
            menuOpen = false;
            target = null;
            enter("drag", "drag");
        }
        x = gx - grab.dx;
        y = gy - grab.dy;
    }
    function release(gx, gy) {
        const g = grab;
        grab = null;
        if (!g) return;
        touch();
        if (!g.moved) {
            if (mode === "sleep") wake();
            else enter("land", Math.random() < 0.5 ? "land" : "blink");
            return;
        }
        refresh();
        const d = displayAt(gx === undefined ? x + width / 2 : gx, gy === undefined ? y + height / 2 : gy);
        if (!d) return;
        Clawd.screenName = d.id;
        x = clampX(d, x);
        y = Math.max(y, d.y);
        vy = 0;
        enter("fall", "fall");
    }
    function openMenu() {
        if (mode === "walk" || mode === "turn") idle();
        menuOpen = true;
    }

    onHeightChanged: ground()
    onHereChanged: if (here) ground(); else if (displays.length) Qt.callLater(spawn)  // spawn() rewrites screenName, which here depends on
    onSummonChanged: spawn()
    Component.onCompleted: spawn()

    Connections {
        target: Clawd
        function onCommand(name, arg) { if (name === "play") pet.perform(arg); }
    }

    // The single clock for his frames; every overlay sprite shows clock.frame.
    ClawdSprite {
        id: clock
        animation: pet.animation
        reverse: pet.reverse
        onFinished: pet.next()
    }
    Timer { id: brain; onTriggered: pet.mode === "idle" ? pet.think() : pet.next() }
    Timer { id: drowsy; interval: pet.sleepAfter; onTriggered: { pet.tired = true; if (pet.mode === "sit" || pet.mode === "idle" && pet.animation === "idle") pet.sleep(); } }
    Timer { interval: 16; repeat: true; running: pet.mode === "walk" || pet.mode === "fall"; onTriggered: pet.step() }

    function readCursor() {
        try {
            const p = JSON.parse(cursorBuffer);
            if (Number.isFinite(p.x) && Number.isFinite(p.y)) pointer = { x: p.x, y: p.y };
            cursorBuffer = "";
            cursorSocket.connected = false;
        } catch (error) { if (cursorBuffer.length > 4096) cursorBuffer = ""; } // The JSON may be split across reads.
    }
    Socket {
        id: cursorSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { pet.cursorBuffer += data; pet.readCursor(); } }
        onConnectedChanged: {
            if (connected) { pet.cursorBuffer = ""; write("j/cursorpos"); flush(); }
            else if (pet.cursorBuffer) pet.readCursor();
        }
    }
    Timer {
        interval: 200; repeat: true
        running: pet.hypr && !Clawd.lowMotion && pet.mode !== "sleep"
        onTriggered: if (!cursorSocket.connected) cursorSocket.connected = true
    }
}
