import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../"
import "js/world.mjs" as World
import "js/mind.mjs" as Mind

// Clawd himself, in global logical pixels: x/y is his top-left corner, every ClawdOverlay draws him from here.
// mode: spawn, idle, walk, turn, sit, sleep, drag, fall, land, play, work (an agent session is busy: Clawd.activity,
// playing Clawd.workAnim, the loop of the last tool used, or its "_2" variant; "sweat" now and then when strained),
// perch (resting on a window top), hop (a parabolic jump), react (a one-shot that returns to his resting pose),
// teeter (at the end of a window top), peek (2/3 hidden behind a window: cover), explode (frozen inside a limit scene),
// corpse (his corpse falling back after it), dead (lying there, grey and smoking: nothing moves him), revive (ClawdRevive).
// support = what he stands on: null (the floor of `here`) | {kind: "win", id, dx} (dx = contact x - window x;
// 5b+: widget, bar, side). He is placed through the animation's grip (clawd.json; default bottom centre).
Item {
    id: pet
    property var world: null       // ClawdWorld: displays, windows, ledges, cursor
    readonly property bool hypr: Hyprland.requestSocketPath !== ""
    readonly property var displays: world ? world.displays : World.monitors(Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height })),
        hypr ? Hyprland.monitors.values.map(m => ({ name: m.name, x: m.x, y: m.y, lastIpcObject: m.lastIpcObject })) : [])
    readonly property var here: display(Clawd.screenName)
    readonly property int summon: Config.getSetting("addonsV2ClawdSummon", 0)
    readonly property alias frame: clock.frame
    readonly property var pointer: world ? world.pointer : null   // global cursor
    property string mode: "spawn"
    property string animation: "spawn"
    property bool mirrored: false
    property bool reverse: false
    property bool menuOpen: false
    property bool journalOpen: false
    property int sleepAfter: Clawd.sleepMinutes * 60000
    property var target: null      // walk destination x
    property var intent: null      // why he walks there: {kind: edge | peek | out | cross | leave, ...}
    property var grab: null        // left press: {x, y, dx, dy, moved}
    property var support: null
    property var cover: null       // the window rect he peeks from behind: the overlays clip him there
    property string coverId: ""
    property var peeking: null     // {id, side, ex} while peeking
    property var hop: null         // the ledge a hop lands on
    property var resume: null      // the pose a reaction returns to
    // The singularity (ClawdSingularity): {screen, x, y, animation, frame, mirrored, scale, clock}; clock = ms when its
    // timeline was at 0, set once his screen is captured. blasting: frozen inside it, nothing else moves him.
    property var blast: null       // + kind: singularity | nuke
    property var quotaQueue: []
    property bool blasting: false
    property bool blastHidden: false
    // Dead after a limit scene until revived (menu, a new agent session, or a shell start 3 h later). Kept in Config
    // (addonsV2ClawdDead = when he died, ms) so a reload finds his corpse; reviveAt = ms when the revival started.
    property bool dead: false
    property real weeklyAt: 0      // ms when the weekly reset scene started (mode weekly)
    property real surgeAt: 0       // ms when the superpowered weekly scene started (mode surge)
    property var surgeHome: null   // the workspace id his screen showed before he dashed to an empty one
    property real rechargeAt: 0    // ms when the 5 h reset scene started (mode recharge)
    property real deadAt: 0
    property real reviveAt: 0
    readonly property int reviveAfter: 3 * 3600000
    property var fallTarget: null
    property real fallAt: 0
    property bool lost: false      // his support vanished under him: oops on landing
    property var mind: Mind.memory()
    property int awayChecks: 0
    property string awayScreen: ""
    property real vx: 0
    property real vy: 0
    property real last: 0
    property bool tired: false
    readonly property bool riding: !!support && support.kind === "win"
    // what `cover` hides of him, px from each side; the overlays clip it
    readonly property var cut: {
        const c = cover;
        if (!c || width <= 0) return { l: 0, r: 0 };
        const a = Math.max(x, c.x), b = Math.min(x + width, c.x + c.w);
        if (b <= a || Math.min(y + height, c.y + c.h) - Math.max(y, c.y) < height / 2) return { l: 0, r: 0 };
        if (c.x <= x && c.x + c.w >= x + width) return { l: width, r: 0 };
        return c.x <= x ? { l: b - x, r: 0 } : { l: 0, r: x + width - a };
    }
    width: Clawd.manifest ? Clawd.manifest.frame.w * Clawd.scale : 0
    height: Clawd.manifest ? Clawd.manifest.frame.h * Clawd.scale : 0

    // Working loops that have a variant, and how fast his hands go (the lead session's effort).
    readonly property var families: ["work", "edit", "read", "bash", "search", "web", "task", "todo"]
    readonly property real speed: mode === "work" && families.indexOf(animation.replace(/_2$/, "")) >= 0 ? Clawd.effortSpeed : 1

    function display(name) { return displays.find(d => d.id === name) || null; }
    function displayAt(gx, gy) { return World.displayAt(displays, gx, gy); }
    function refresh() { if (hypr) Hyprland.refreshMonitors(); }
    function clampX(d, v) { return Math.max(d.x, Math.min(d.x + d.w - width, v)); }

    // An animation the manifest lacks (sprites not regenerated yet) falls back to a close one.
    function clipName(name) {
        const m = Clawd.manifest, alt = { perch: "sit", perch_look: "sit", hop: "land", stumble: "oops", teeter: "idle", peek: "look_right" };
        return !m || m.animations[name] || !Object.prototype.hasOwnProperty.call(alt, name) ? name : alt[name];
    }
    function ownGrip(anim) {
        const clip = Clawd.manifest && Clawd.manifest.animations[anim];
        return !!clip && Array.isArray(clip.grip) && clip.grip.length === 2 && clip.grip.every(Number.isFinite);
    }
    // His contact point with the support inside the frame, scaled px from his top-left (mirrored: from the right).
    function grip(anim, flip) {
        const m = Clawd.manifest;
        if (!m) return { x: 0, y: 0 };
        const W = m.frame.w, H = m.frame.h, g = ownGrip(anim) ? m.animations[anim].grip : [W / 2, H];
        const gx = Math.max(0, Math.min(W, g[0])), gy = Math.max(0, Math.min(H, g[1]));
        return { x: (flip ? W - gx : gx) * Clawd.scale, y: gy * Clawd.scale };
    }
    function contact() { const g = grip(animation, mirrored); return { x: x + g.x, y: y + g.y }; }
    function placeAt(cx, cy) { const g = grip(animation, mirrored); x = cx - g.x; y = cy - g.y; }
    function ledgeOf(s) { return s && world ? world.ledge(s.id) : null; }

    function enter(m, anim, flip, back) {
        if (blasting || dead && ["corpse", "dead", "revive", "carried"].indexOf(m) < 0) return;
        const name = clipName(anim), was = grip(animation, mirrored);
        mode = m;
        mirrored = !!flip;
        reverse = !!back;
        animation = name;
        // the contact point stays put: grips differ (perch sits on the seat line, legs below the ledge)
        if (m !== "drag" && m !== "carried") { const g = grip(name, mirrored); x += was.x - g.x; y += was.y - g.y; }
        clock.restart();
        last = Date.now();
        const clip = Clawd.manifest && Clawd.manifest.animations[name];
        brain.stop();
        if (m === "idle" && name === "idle") brain.interval = pause();
        else if (m === "sit" || m === "perch" && clip && clip.loop) brain.interval = 5000 + Math.random() * 7000;
        else if (m === "teeter") brain.interval = 1200 + Math.random() * 800;
        else if (m === "peek") brain.interval = 3000 + Math.random() * 3000;
        else if ((m === "play" || m === "react") && clip && clip.loop) brain.interval = 3000;
        else return;
        brain.start();
    }
    function pause() {
        if (Clawd.lowMotion) return 20000 + Math.random() * 20000;
        const base = ({ calm: 5000, normal: 3000, active: 2000 })[Clawd.speed];
        return base + Math.random() * base * 1.2;
    }
    function next() {
        if (dead) { if (mode === "dead" && animation !== "dead") enter("dead", "dead"); return; }
        if (mode === "turn" && target !== null) enter("walk", "walk", mirrored);
        else if (mode === "fall") { if (animation !== "fall") enter("fall", "fall"); }  // a startle mid-air is over
        else if (mode === "teeter") edge();
        else if (mode === "peek") unpeek();
        else if (mode === "react" && resume && grounded()) { const r = resume; resume = null; enter(r.mode, r.animation, r.mirrored); }
        else if (["sleep", "drag", "walk", "hop", "recharge", "weekly", "surge"].indexOf(mode) < 0) idle();
    }
    // Back to his resting pose on whatever holds him: perch on a window, idle on the floor; no valid support: fall.
    function idle() {
        if (dead) return;
        target = null;
        intent = null;
        resume = null;
        peeking = null;
        cover = null;
        coverId = "";
        if (!grounded()) { support = null; vy = 0; enter("fall", "fall"); return; }
        if (!support && here) x = clampX(here, x);
        if (Clawd.activity) { touch(); enter("work", Clawd.activity === "alert" ? "alert" : Clawd.variant(Clawd.workAnim)); }
        else if (tired) sleep();
        else if (support) enter("perch", "perch");
        else enter("idle", "idle");
    }
    function grounded() {
        if (support) { const l = ledgeOf(support); return !!l && !!World.span(world.wins, l, l.x + support.dx); }
        return !here || contact().y >= here.floor - 0.5;
    }
    function think() {
        refresh();
        const chance = Clawd.lowMotion ? 0.1 : ({ calm: 0.25, normal: 0.4, active: 0.6 })[Clawd.speed];
        const r = Math.random(), rest = (r - chance) / (1 - chance);
        if (menuOpen) enter(support ? "perch" : "idle", support ? "perch" : "idle");
        else if (r < chance) { if (!(r < chance / 4 && explore())) walk(); }  // a quarter of his walks explore
        else if (support) {
            if (rest < 0.3) enter("perch", "perch_look", Math.random() < 0.5);
            else if (rest < 0.45) { if (!hopDown(0)) enter("perch", "perch"); }
            else enter("perch", "perch");
        }
        else if (rest < 0.35) enter("idle", "blink");
        else if (rest < 0.7 && !Clawd.lowMotion) enter("idle", look());
        else if (rest < 0.85) enter("sit", "sit");
        else enter("idle", "idle");
    }
    function lookAt(gx, gy) {
        const dx = gx - (x + width / 2), dy = gy - (y + height / 2);
        return dy < 0 && -dy > Math.abs(dx) ? "look_up" : dx < 0 ? "look_left" : "look_right";
    }
    function look() {
        if (!pointer) return ["look_left", "look_right", "look_up"][Math.floor(Math.random() * 3)];
        return lookAt(pointer.x, pointer.y + height / 2);  // above his head counts as up
    }
    // Sprite x range he can walk on: the floor of his screen, or the uncovered part of his window top.
    function stand() {
        if (!support) return here ? { x0: here.x, x1: here.x + here.w - width } : null;
        const l = ledgeOf(support), s = l && World.span(world.wins, l, l.x + support.dx);
        return s ? { x0: s.x0, x1: s.x1 - width } : null;
    }
    function walk() {
        const s = stand();
        if (!s || s.x1 - s.x0 < 8) return idle();
        const distance = 80 + Math.random() * Math.min(400, s.x1 - s.x0);
        const fit = v => Math.max(s.x0, Math.min(s.x1, v));
        let to = x + (Math.random() < 0.5 ? -distance : distance);
        // the floor turns him back at the screen edge; a window top may take him to its end, where he teeters
        if (fit(to) !== to && (!support || Math.random() < 0.5)) to = 2 * x - to;
        to = fit(to);
        if (!walkTo(to, support && (to <= s.x0 + 0.5 || to >= s.x1 - 0.5) ? { kind: "edge" } : null)) idle();
    }
    function walkTo(to, why) {
        if (Math.abs(to - x) < 8) {
            if (!why || why.kind !== "peek") return false;
            intent = why;
            arrive();
            return true;
        }
        target = to;
        intent = why || null;
        enter("turn", "turn", to < x);
        return true;
    }
    function step() {
        const now = Date.now(), dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        if (mode === "walk") {
            const hurry = intent && (intent.kind === "cross" || intent.kind === "leave") ? 3 : 1;
            const v = ({ calm: 30, normal: 60, active: 100 })[Clawd.speed] * hurry * dt, left = target - x;
            if (Math.abs(left) > v) { x += left > 0 ? v : -v; walked(); return; }
            x = target;
            target = null;
            walked();
            arrive();
        } else if (mode === "fall") {
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), ny = c.y + vy * dt;
            if (!fallTarget || now - fallAt >= 250) { fallTarget = landingAt(c.x, c.y); fallAt = now; }
            if (fallTarget && ny >= fallTarget.y) {
                fallTarget = landingAt(c.x, c.y);  // touchdown: is it still there?
                fallAt = now;
                if (fallTarget && ny >= fallTarget.y) return settle(fallTarget, c.x);
            }
            placeAt(c.x, ny);
        } else if (mode === "corpse") {
            // his corpse drops straight onto the floor of his screen, whatever is in between
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), ny = c.y + vy * dt;
            if (here && ny >= here.floor) { vy = 0; placeAt(c.x, here.floor); enter("dead", "dead_land"); }
            else placeAt(c.x, ny);
        } else if (mode === "hop" && hop) {
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), nx = c.x + vx * dt, ny = c.y + vy * dt;
            const l = hop.kind === "floor" ? hop : ledgeOf(hop);
            if (!l) { hop = null; vx = 0; enter("fall", "fall"); return; }  // its window went away mid-air
            if (vy > 0 && ny >= l.y) return settle(l, nx);
            placeAt(nx, ny);
        }
    }
    function walked() {
        if (support) { const l = ledgeOf(support); if (l) support.dx = contact().x - l.x; }
        if (intent && intent.kind === "cross") track();
    }
    function arrive() {
        const i = intent;
        intent = null;
        if (i && i.kind === "edge" && support) return enter("teeter", "teeter", mirrored);
        if (i && i.kind === "peek") {
            // the window on his right (came to its left edge): peek out leftwards, mirrored
            const flip = i.side < 0;
            peeking = i;
            enter("peek", "peek", flip);
            x = ownGrip(animation) ? i.ex - grip(animation, flip).x : flip ? i.ex - width / 3 : i.ex - width * 2 / 3;
            return;
        }
        if (i && i.kind === "out") { cover = null; coverId = ""; }
        if (i && i.kind === "leave") return reenter(i.to);
        enter("turn", "turn", mirrored, true);
    }
    // At the end of a window top: hop down (40 %), (5b: hang from the edge, 30 %), else turn back.
    function edge() {
        if (!support) return idle();
        if (Math.random() < 0.4 && hopDown(mirrored ? -1 : 1)) return;
        const s = stand();
        if (!s || !walkTo(Math.max(s.x0, Math.min(s.x1, x + (mirrored ? 1 : -1) * (60 + Math.random() * 140))))) idle();
    }
    // Off his window top, on that side (0: the nearest one with room), down to whatever is below.
    function hopDown(side) {
        const l = ledgeOf(support);
        if (!l) return false;
        const c = contact(), d = display(l.display) || here;
        const off = s => { const tx = s < 0 ? l.x - width * 0.6 : l.x + l.w + width * 0.6; return d && tx - width / 2 >= d.x && tx + width / 2 <= d.x + d.w ? tx : null; };
        const near = c.x - l.x < l.x + l.w - c.x ? -1 : 1;
        const tx = side ? off(side) : off(near) !== null ? off(near) : off(-near);
        return tx !== null && hopTo(tx, landingAt(tx, c.y + 1));
    }
    // A parabolic jump: his contact point flies to (tx, ledge top).
    function hopTo(tx, l) {
        if (!l) return false;
        const c = contact(), g = 2600, top = Math.min(c.y, l.y) - Math.max(height * 0.6, Math.abs(tx - c.x) * 0.2);
        const up = Math.sqrt(2 * g * (c.y - top)), t = up / g + Math.sqrt(2 * (l.y - top) / g);
        vy = -up;
        vx = (tx - c.x) / t;
        hop = l;
        support = null; target = null; intent = null; cover = null; coverId = ""; peeking = null;
        touch();
        enter("hop", "hop", tx < c.x);
        return true;
    }
    // Touchdown on ledge l, his contact at cx.
    function settle(l, cx) {
        const win = l.kind !== "floor";
        if (win) cx = Math.max(l.x + Math.min(width / 2, l.w / 2), Math.min(l.x + l.w - Math.min(width / 2, l.w / 2), cx));
        support = win ? { kind: l.kind, id: l.id, dx: cx - l.x } : null;
        vy = 0; vx = 0; fallTarget = null;
        const hopping = mode === "hop" && !clock.done && animation === clipName("hop");
        hop = null;
        if (hopping) mode = "land";  // the hop strip ends with its own landing squash
        else enter("land", lost ? "oops" : "land");
        lost = false;
        placeAt(cx, l.y);
        const d = display(l.display);
        if (!win && d) x = clampX(d, x);
        if (d && d.id !== Clawd.screenName) Clawd.screenName = d.id;
    }
    function landingAt(cx, feetY) {
        const t = world ? World.landing(world.ledges, world.wins, cx, feetY, displays) : null;
        if (t) return t;
        const d = displayAt(cx, feetY);
        return d ? { id: "floor:" + d.id, kind: "floor", x: d.x, y: d.floor, w: d.w, display: d.id } : null;
    }
    function placeOnSupport() {
        if (!here || ["drag", "fall", "hop", "corpse", "revive", "carried", "recharge", "weekly", "surge"].indexOf(mode) >= 0) return;
        if (support) return revalidate();
        placeAt(contact().x, here.floor);
        if (!intent || ["cross", "leave"].indexOf(intent.kind) < 0) x = clampX(here, x);
    }
    // After every world snapshot: follow his window, or lose it (gone, covered, maximized, another workspace).
    function revalidate() {
        if (coverId) {
            const w = world ? world.win(coverId) : null;
            if (!w || !cover || w.x !== cover.x || w.y !== cover.y || w.w !== cover.w || w.h !== cover.h) {
                cover = null;
                coverId = "";
                if (mode === "peek") unpeek();
                else if (intent && intent.kind === "peek") idle();
            }
        }
        if (!support || ["drag", "fall", "hop", "recharge", "weekly", "surge"].indexOf(mode) >= 0) return;
        const l = ledgeOf(support), c = contact(), cx = l ? l.x + support.dx : 0;
        if (!l || !World.span(world.wins, l, cx)) return lose(false);
        if (Math.abs(cx - c.x) + Math.abs(l.y - c.y) > 200) return lose(true);  // yanked away: startled mid-air
        if (Math.abs(cx - c.x) + Math.abs(l.y - c.y) < 0.01) return;
        if (target !== null) target += cx - c.x;
        placeAt(cx, l.y);
        track();
    }
    function lose(startle) {
        support = null; hop = null; target = null; intent = null; fallTarget = null;
        vy = 0;
        if (mode === "drag" || mode === "recharge" || mode === "weekly" || mode === "surge") return;
        lost = true;
        touch();
        enter("fall", startle ? "startled" : "fall");
    }
    // His centre went over to another screen.
    function track() {
        const d = displayAt(x + width / 2, y + height / 2);
        if (d && d.id !== Clawd.screenName) Qt.callLater(moveTo, d.id);
    }
    function moveTo(name) { if (display(name) && Clawd.screenName !== name) Clawd.screenName = name; }

    // Windows, peeking and the cursor's screen; false when there is nothing to explore.
    function explore() {
        if (!world || !Clawd.world || Clawd.lowMotion || !here) return false;
        const c = contact(), ops = [];
        let hopOn = null;
        for (const l of world.ledges) {
            if (l.kind === "floor" || l.display !== here.id || support && l.id === support.id) continue;
            const up = c.y - l.y, tx = Math.max(l.x + width * 0.6, Math.min(l.x + l.w - width * 0.6, c.x));
            if (up < 8 || up > height * 1.5 || Math.abs(tx - c.x) > width * 4 || !World.span(world.wins, l, tx)) continue;
            if (!hopOn || Math.abs(tx - c.x) < Math.abs(hopOn.tx - c.x)) hopOn = { tx, l };
        }
        if (hopOn) ops.push(() => hopTo(hopOn.tx, hopOn.l));
        const spot = support ? null : peekSpot();
        if (spot) ops.push(() => peek(spot));
        const cur = World.cursor(displays, here, pointer);
        if (cur && cur.display && !cur.inside && Clawd.follow) ops.push(() => cross(cur.display));
        else if (cur && cur.inside) ops.push(() => { const s = stand(); return !!s && walkTo(Math.max(s.x0, Math.min(s.x1, cur.x - width / 2))); });
        return ops.length > 0 && !!ops[Math.floor(Math.random() * ops.length)]();
    }
    // The nearest window edge on his screen he can hide behind from the floor (the window covers his height).
    function peekSpot() {
        const c = contact(), d = here;
        let best = null;
        for (const w of world.wins) {
            if (w.display !== d.id || w.max || w.y > y + height * 0.3 || w.y + w.h < y + height * 0.7) continue;
            for (const side of [-1, 1]) {  // -1: its left edge, he comes from the left
                const ex = side < 0 ? w.x : w.x + w.w, px = side < 0 ? ex - width / 3 : ex - width * 2 / 3;
                if ((side < 0 ? c.x > ex : c.x < ex) || px < d.x || px + width > d.x + d.w) continue;
                if (World.covered(world.wins, w.id, ex - 1, ex + 1, y + height / 2)) continue;
                const far = Math.abs(px - x);
                if (far <= 500 && (!best || far < best.far)) best = { id: w.id, rect: { x: w.x, y: w.y, w: w.w, h: w.h }, side, ex, x: px, far };
            }
        }
        return best;
    }
    function peek(spot) {
        coverId = spot.id;
        cover = spot.rect;
        if (walkTo(spot.x, { kind: "peek", id: spot.id, side: spot.side, ex: spot.ex })) return true;
        cover = null;
        coverId = "";
        return false;
    }
    // Out from behind the window, the way he came.
    function unpeek() {
        const p = peeking;
        peeking = null;
        if (!p || !here) return idle();
        const out = clampX(here, p.side < 0 ? p.ex - width - 20 - Math.random() * 60 : p.ex + 20 + Math.random() * 60);
        if (!walkTo(out, { kind: "out" })) idle();
    }

    // Every 2 s: the cursor on another screen twice in a row and he is free -> he goes there.
    function follow() {
        const c = World.cursor(displays, here, pointer);
        const elsewhere = Clawd.follow && !Clawd.lowMotion && !!c && !c.inside && !!c.display;
        awayChecks = elsewhere ? (awayScreen === c.display ? awayChecks + 1 : 1) : 0;
        awayScreen = elsewhere ? c.display : "";
        if (awayChecks < 2 || ["idle", "sit", "perch"].indexOf(mode) < 0 || Clawd.activity || menuOpen || journalOpen || grab) return;
        awayChecks = 0;
        cross(c.display);
    }
    // Next screen with a floor at about the same height: walk over. Otherwise walk off his edge and drop in from its top.
    function cross(name) {
        const d = display(name), h = here;
        if (!d || !h || d.id === h.id) return false;
        const side = d.x + d.w / 2 >= h.x + h.w / 2 ? 1 : -1;
        if (support) return hopDown(side) || hopDown(0);  // down first; the next check walks on
        touch();
        const n = World.beyond(displays, h, side, h.floor - height / 2);
        if (n && Math.abs(n.floor - h.floor) <= height)
            return walkTo(side > 0 ? n.x + 40 + Math.random() * 160 : n.x + n.w - width - 40 - Math.random() * 160, { kind: "cross", to: n.id });
        return walkTo(side > 0 ? h.x + h.w + 2 : h.x - width - 2, { kind: "leave", to: d.id });
    }
    function reenter(name) {
        const d = display(name);
        if (!d) return idle();
        support = null; vy = 0; fallTarget = null; lost = false;
        enter("fall", "fall");
        Clawd.screenName = d.id;
        const near = pointer && pointer.x >= d.x && pointer.x < d.x + d.w ? pointer.x - width / 2 : d.x + width + Math.random() * Math.max(0, d.w - 3 * width);
        x = Math.round(clampX(d, near));
        y = d.y - height;
    }

    // A world event through Mind; a look toward (gx, gy) or the event's own one-shot.
    function feel(kind, gx, gy) {
        if (!Clawd.world || ["idle", "sit", "perch", "walk", "turn", "react", "sleep", "work"].indexOf(mode) < 0) return false;
        const now = Date.now();
        const d = Mind.decide(Object.assign({}, mind, { drag: !!grab && grab.moved, menu: menuOpen, petpet: animation.startsWith("petpet"), hook: Clawd.activity,
            asleep: mode === "sleep", reactions: "all", dnd: false, lowMotion: Clawd.lowMotion, mode }), kind, now);
        if (d.act !== "react" && d.act !== "glance") return false;
        let anim = d.anim, flip = false;
        if (anim === "look" && mode === "perch") { anim = "perch_look"; flip = gx < x + width / 2; }
        else if (anim === "look") anim = lookAt(gx, gy);
        react(anim, flip);
        mind = Mind.commit(mind, kind, now);
        return true;
    }
    function react(anim, flip) {
        touch();
        if (mode !== "react") resume = ["idle", "sit", "perch"].indexOf(mode) >= 0 ? { mode, animation, mirrored } : null;
        target = null;
        intent = null;
        enter("react", anim, flip);
    }
    function closed(id, rect) {
        if (support && support.id === id) return;  // his own window: he falls, oops on landing
        const cx = x + width / 2, cy = y + height / 2;
        const dx = Math.max(rect.x - cx, 0, cx - rect.x - rect.w), dy = Math.max(rect.y - cy, 0, cy - rect.y - rect.h);
        if (Math.hypot(dx, dy) <= 300) feel("window_close_near", cx, cy);
    }

    function spawn() {
        refresh();
        const f = hypr && Hyprland.focusedMonitor ? display(Hyprland.focusedMonitor.name) : null;
        const d = f || displays[0];
        if (!d) return;
        grab = null;
        menuOpen = false;
        support = null; hop = null; cover = null; coverId = ""; peeking = null; resume = null; lost = false;
        target = null;
        intent = null;
        Clawd.screenName = d.id;
        if (dead) {  // his corpse, where it lies; no greeting
            if (mode !== "revive") enter("dead", "dead");
            x = Math.round(d.x + (d.w - width) / 2);
            y = d.floor - height;
            return;
        }
        enter("spawn", "spawn");
        x = Math.round(d.x + (d.w - width) / 2);
        y = d.floor - height;
        touch();
    }
    function touch() {
        tired = false;
        drowsy.restart();
    }
    function sleep() {
        target = null;
        tired = false;
        drowsy.stop();
        if (!grounded()) return idle();
        enter("sleep", "sleep");
    }
    function wake() {
        touch();
        if (mode === "sleep") enter("idle", "blink");
    }
    function enqueueQuota(name) {
        quotaQueue = quotaQueue.concat([name]);
        runQuota();
    }
    function runQuota() {
        if (!quotaQueue.length || blast || mode === "revive" || mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (dead) { revive(); return; }
        if (!here || !grounded() || grab && grab.moved || ["fall", "hop", "drag"].indexOf(mode) >= 0) return;
        const name = quotaQueue[0];
        quotaQueue = quotaQueue.slice(1);
        perform(name);
    }
    Timer { interval: 1000; repeat: true; running: pet.quotaQueue.length > 0; onTriggered: pet.runQuota() }

    function perform(name) {
        if (name === "limit") return explode(Math.random() < 0.5 ? "singularity" : "nuke");  // the quota ran out: either end
        if (name === "explode") return explode("singularity");
        if (name === "nuke") return explode("nuke");
        if (name === "revive") return revive();
        if (name === "recharge") return recharge();
        if (name === "weekly") return weekly();
        if (name === "surge") return surge();
        if (name === "limit7") return Clawd.roll() < 0.5 ? explode("singularity") : surge();  // the weekly quota ran out
        if (mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (dead || !Clawd.manifest || !Clawd.manifest.animations[name] || grab && grab.moved) return;
        touch();
        target = null;
        intent = null;
        enter("play", name);
    }

    // His quota ran out: he freezes mid-pose (the clock stops) and the limit windows take over (kind: singularity | nuke);
    // they hide him, then reappear(gx) drops his corpse at global x gx and blastDone() ends it.
    function explode(kind) {
        if (blast || !here || dead) return;
        grab = null; menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; hop = null;
        brain.stop();
        blast = { kind: kind === "nuke" ? "nuke" : "singularity", screen: Clawd.screenName, x, y, animation, frame: clock.frame, mirrored, scale: Clawd.scale, clock: 0 };
        mode = "explode";
        blasting = true;
    }
    function blastClock(ms) { if (blast) blast = Object.assign({}, blast, { clock: ms }); }
    function reappear(gx) {
        if (!blasting) return;
        blasting = false;
        blastHidden = false;
        die(gx);
    }
    function blastDone() { reappear(); blast = null; }
    // Dead: his corpse falls from the top of the screen at global x gx (default: the middle of his screen) and lies there.
    function die(gx) {
        const d = (gx !== undefined ? displayAt(gx, here ? here.y + here.h / 2 : 0) : null) || here || displays[0];
        if (!d) return;
        grab = null; menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; hop = null;
        support = null; cover = null; coverId = ""; peeking = null; lost = false; fallTarget = null;
        dead = true;
        deadAt = Date.now();
        Config.setSetting("addonsV2ClawdDead", deadAt);
        Clawd.screenName = d.id;
        vy = 0;
        enter("corpse", "dead");
        x = Math.round(clampX(d, (gx !== undefined ? gx : d.x + d.w / 2) - width / 2));
        y = d.y - height;
    }
    // Back to life: ClawdRevive plays on his screen's overlay, which calls revived() at its end.
    function revive() {
        if (!dead || mode === "revive" || blast) return;
        if (mode === "corpse" && here) placeAt(contact().x, here.floor);  // still falling: down at once
        grab = null;
        menuOpen = false;
        reviveAt = Date.now();
        enter("revive", "dead");
    }
    function revived() {
        if (mode !== "revive") return;
        dead = false;
        deadAt = 0;
        Config.setSetting("addonsV2ClawdDead", 0);
        touch();
        idle();
    }
    // The 5 h limit is back: ClawdRecharge plays on his screen's overlay (he stays where he stands), whose end calls
    // recharged(). A dead Clawd simply comes back to life instead.
    function recharge() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; hop = null;
        rechargeAt = Date.now();
        enter("recharge", "idle");
    }
    // The weekly limit is back: the symphony (ClawdSymphony on his screen's overlay; the curtains hide his move to the
    // stage), whose end calls weeklied(). Dead: he comes back to life instead.
    function weekly() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; hop = null;
        weeklyAt = Date.now();
        enter("weekly", "idle");
    }
    function weeklied() {
        if (mode !== "weekly") return;
        touch();
        idle();
        busy();
    }
    // The weekly limit ran out, the superpowered way: ClawdSurge on his screen's overlay (an orb hits him, he absorbs it,
    // dashes to an empty workspace, summons six helpers and recharges the week); he ends in the middle of his screen,
    // back on the workspace he left: surged(gx). Dead: he comes back to life instead.
    function surge() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; hop = null;
        surgeAt = Date.now();
        surgeHome = null;
        enter("surge", "idle");
    }
    // During his dash: an empty workspace on his screen (away), then the one he left (back).
    function surgeWorkspace(away) {
        if (!hypr || mode !== "surge") return;
        const name = Clawd.screenName, m = Hyprland.monitors.values.find(v => v.name === name);
        if (away) surgeHome = m && m.activeWorkspace ? m.activeWorkspace.id : null;
        else if (surgeHome === null) return;
        // Lua dispatchers (the shell's Hyprland takes hl.dsp.*, like the bar's workspace buttons)
        if (!Hyprland.focusedMonitor || Hyprland.focusedMonitor.name !== name) Hyprland.dispatch("hl.dsp.focus({ monitor = \"" + name + "\" })");
        Hyprland.dispatch(away ? "hl.dsp.focus({ workspace = \"emptynm\" })" : "hl.dsp.focus({ workspace = " + surgeHome + " })");
        if (!away) surgeHome = null;
    }
    function surged(gx) {
        if (mode !== "surge") return;
        if (surgeHome !== null) surgeWorkspace(false);
        support = null; cover = null; coverId = ""; peeking = null;
        if (here && gx !== undefined) { x = Math.round(clampX(here, gx - width / 2)); placeAt(contact().x, here.floor); }
        touch();
        idle();
        busy();
    }
    function recharged() {
        if (mode !== "recharge") return;
        touch();
        idle();
        busy();
    }
    function clockRunning() { return clock.running; }  // test hook

    // Middle click pets him; petting him again while he is being petted gets hearts.
    // At work he only startles, then goes back to it.
    function petpet() {
        if (Clawd.activity === "work") perform("startled");
        else perform(animation.startsWith("petpet") ? "petpetheart" : "petpet");
    }

    // Input from the overlay where the press started, already in global coordinates.
    function press(button, gx, gy) {
        touch();
        if (button === Qt.RightButton) { openMenu(); return; }
        if (mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (dead) {  // he does not react any more, but his corpse can be carried (only where it lies)
            if (button === Qt.LeftButton && ["dead", "carried"].indexOf(mode) >= 0) grab = { x: gx, y: gy, dx: gx - x, dy: gy - y, moved: false };
            return;
        }
        if (button === Qt.MiddleButton) { petpet(); return; }
        grab = { x: gx, y: gy, dx: gx - x, dy: gy - y, moved: false };
    }
    function move(gx, gy) {
        if (!grab) return;
        if (!grab.moved && Math.abs(gx - grab.x) + Math.abs(gy - grab.y) < 4) return;
        if (!grab.moved) {
            grab.moved = true;
            menuOpen = false;
            if (dead) {
                if (mode !== "dead") { grab = null; return; }
                enter("carried", "dead");
            } else {
                target = null;
                intent = null; support = null; hop = null; cover = null; coverId = ""; peeking = null; resume = null;
                enter("drag", "drag");
            }
        }
        x = gx - grab.dx;
        y = gy - grab.dy;
    }
    // Dropped: he falls onto whatever is below, a window top included.
    function release(gx, gy) {
        const g = grab;
        grab = null;
        if (!g) return;
        touch();
        if (dead) {  // dropped corpse: it falls to the floor of the screen it was dropped on
            if (!g.moved || mode !== "carried") return;
            refresh();
            const d = displayAt(gx === undefined ? x + width / 2 : gx, gy === undefined ? y + height / 2 : gy);
            if (d) { Clawd.screenName = d.id; x = clampX(d, x); y = Math.max(y, d.y); }
            vy = 0;
            enter("corpse", "dead");
            return;
        }
        if (!g.moved) {
            journalOpen = !journalOpen;
            if (mode === "sleep") wake();
            else if (["work", "fall", "hop"].indexOf(mode) < 0) enter("land", Math.random() < 0.5 ? "land" : "blink");
            return;
        }
        refresh();
        const d = displayAt(gx === undefined ? x + width / 2 : gx, gy === undefined ? y + height / 2 : gy);
        if (!d) return;
        Clawd.screenName = d.id;
        x = clampX(d, x);
        y = Math.max(y, d.y);
        vy = 0;
        support = null;
        lost = false;
        fallTarget = null;
        enter("fall", "fall");
    }
    // A session got busy, needs the user or went quiet: stop wandering (and wake) or go back to normal life.
    function busy() {
        if ((Clawd.activity || mode === "work") && ["idle", "sit", "sleep", "walk", "turn", "work", "perch", "teeter", "peek"].indexOf(mode) >= 0) idle();
    }
    // Every 8-12 s at work: the other variant of the loop, or a sweat break when the lead session is strained.
    function shuffle() {
        if (mode !== "work" || Clawd.activity !== "work" || !Clawd.manifest) return;
        const fam = Clawd.workAnim, two = fam + "_2";
        if (Clawd.strained && animation !== "sweat" && Clawd.roll() < 1 / 3 && Clawd.manifest.animations.sweat) enter("work", "sweat");
        else if (Clawd.manifest.animations[two]) enter("work", animation === fam ? two : animation === two ? fam : Clawd.variant(fam));
        else if (animation !== fam) enter("work", fam);
    }
    function openMenu() {
        if (["revive", "corpse", "carried", "recharge", "weekly", "surge"].indexOf(mode) >= 0) return;
        if (mode === "walk" || mode === "turn") idle();
        journalOpen = false;
        menuOpen = true;
    }

    onHeightChanged: placeOnSupport()
    onHereChanged: if (here) placeOnSupport(); else if (displays.length) Qt.callLater(spawn)  // spawn() rewrites screenName, which here depends on
    onSummonChanged: spawn()
    Component.onCompleted: {
        deadAt = Number(Config.getSetting("addonsV2ClawdDead", 0)) || 0;
        dead = deadAt > 0;
        spawn();
        if (dead && Date.now() - deadAt >= reviveAfter) rising.start();  // 3 h later, the shell starting again revives him
    }

    Connections {
        target: Clawd
        function onCommand(name, arg) { if (name === "quota") pet.enqueueQuota(arg); else if (name === "play" || name === "react") pet.perform(arg); }
        function onActivityChanged() { pet.busy(); }
        function onSessionStarted() { pet.revive(); }  // a new Claude Code / Codex session brings him back
        function onWorkAnimChanged() { if (pet.mode === "work" && Clawd.activity === "work") pet.enter("work", Clawd.variant(Clawd.workAnim)); }
    }
    // Window reactions (Mind arbitrates); physics (his own window going away) is revalidate's.
    Connections {
        target: pet.world
        function onUpdated() { Qt.callLater(pet.revalidate); }
        function onWindowOpened(id, rect) { if (rect.display === Clawd.screenName) pet.feel("window_open", rect.x + rect.w / 2, rect.y + rect.h / 2); }
        function onWindowClosed(id, rect) { pet.closed(id, rect); }
        function onFocusMoved(id) { const w = pet.world.win(id); if (w && w.display === Clawd.screenName) pet.feel("focus", w.x + w.w / 2, w.y + w.h / 2); }
        function onWorkspaceSwitched(monitor) { if (monitor === Clawd.screenName && !pet.support) pet.feel("workspace", 0, 0); }  // on a window he just falls
    }

    // The single clock for his frames; every overlay sprite shows clock.frame.
    ClawdSprite {
        id: clock
        running: !pet.blasting
        animation: pet.animation
        reverse: pet.reverse
        speed: pet.speed
        onFinished: pet.next()
    }
    Timer {
        id: shuffler
        interval: 10000; repeat: true
        running: pet.mode === "work" && Clawd.activity === "work"
        onTriggered: { interval = 8000 + Math.random() * 4000; pet.shuffle(); }
    }
    Timer { id: rising; interval: 1500; onTriggered: pet.revive() }
    Timer { id: brain; onTriggered: pet.mode === "idle" || pet.mode === "perch" ? pet.think() : pet.next() }
    Timer { id: drowsy; interval: pet.sleepAfter; onTriggered: { pet.tired = true; if (["sit", "perch"].indexOf(pet.mode) >= 0 || pet.mode === "idle" && pet.animation === "idle") pet.sleep(); } }
    Timer { interval: 16; repeat: true; running: ["walk", "fall", "hop", "corpse"].indexOf(pet.mode) >= 0; onTriggered: pet.step() }
    Timer { interval: 2000; repeat: true; running: Clawd.follow && !Clawd.lowMotion && !!pet.world; onTriggered: pet.follow() }
}
