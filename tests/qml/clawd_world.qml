import QtQuick
import Quickshell

// Clawd and the windows around him, without Hyprland: the world is fed through world.inject().
ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property var p: host.pet
        property var w: host.world
        property string main: Quickshell.screens[0].name
        property real mark: 0
        property var seen: null
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({ mode: p.mode, anim: p.animation, x: p.x, y: p.y, support: p.support, cover: p.cover, intent: p.intent, here: p.here }) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function win(id, x, y, ww, h) { return { address: id, at: [x, y], size: [ww, h], workspace: { id: 1 }, mapped: true, floating: true, focusHistoryID: 3 }; }
        function screen(name, x) { return { name, x, y: 0, width: 1280, height: 720 }; }
        function monitor(name, x) { return { name, x, y: 0, activeWorkspace: { id: 1 }, reserved: [0, 40, 0, 0] }; }
        function feed(clients) { expect(w.inject({ clients }), "inject works without Hyprland"); }
        // pick him up and let go with his centre at cx and his top at top
        function drop(cx, top) {
            p.press(Qt.LeftButton, p.x + 10, p.y + 10);
            p.move(cx - p.width / 2 + 10, top + 10);
            p.release(cx - p.width / 2 + 10, top + 10);
        }
        function cx() { return p.x + p.width / 2; }
        function seat() { return p.y + (Clawd.manifest.animations.perch && Clawd.manifest.animations.perch.grip ? Clawd.manifest.animations.perch.grip[1] : Clawd.manifest.frame.h) * Clawd.scale; }
        onTriggered: {
            switch (step++) {
            case 0:
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(!!p && !!w && !!Clawd.manifest && p.mode === "idle", "spawned")) break;
                expect(Clawd.world && Clawd.follow, "world and follow on by default");
                expect(w.inject({ screens: [screen(main, 0)], monitors: [monitor(main, 0)], clients: [] }), "prime");
                expect(w.ledges.length === 1 && w.ledges[0].kind === "floor" && w.ledges[0].y === 720 && w.displays[0].top === 40, "one floor: " + JSON.stringify(w.ledges));
                break;
            case 2:
                expect(Math.abs(p.y + p.height - 720) < 1 && !p.support, "on the injected floor");
                feed([win("0xw1", 400, 300, 500, 300)]);
                expect(w.wins.length === 1 && w.ledges.some(l => l.id === "0xw1" && l.kind === "win" && l.y === 300), "floating window = ledge");
                drop(650, 100);
                expect(p.mode === "fall", "dropped above the window");
                break;
            case 3:
                if (!wait(p.mode === "perch", "lands, then perches on the window")) break;
                expect(p.support && p.support.kind === "win" && p.support.id === "0xw1" && p.riding, "support = the window: " + JSON.stringify(p.support));
                expect(Math.abs(seat() - 300) < 1 && Math.abs(cx() - 650) < 1, "seated on its top: " + p.y);
                expect(!Clawd.manifest.animations.perch || p.animation === "perch" || p.animation === "perch_look", "perch animation");
                feed([win("0xw1", 450, 320, 500, 300)]);
                break;
            case 4:
                expect(p.support && p.support.id === "0xw1" && Math.abs(seat() - 320) < 1 && Math.abs(cx() - 700) < 1, "rides the window: " + cx());
                feed([]);
                break;
            case 5:
                if (!wait(p.mode === "land" && p.animation === "oops" || p.mode === "fall", "window closed: falls")) break;
                expect(!p.support, "support lost");
                break;
            case 6:
                if (!wait(p.mode === "land" && p.animation === "oops", "oops on landing")) break;
                expect(Math.abs(p.y + p.height - 720) < 1 && !p.support, "on the floor");
                feed([win("0xw2", 300, 400, 300, 200)]);
                drop(450, 200);
                break;
            case 7: {
                if (!wait(p.mode === "perch" && p.support && p.support.id === "0xw2", "perched on the narrow window")) break;
                const lo = 300, hi = 600 - p.width;
                for (let i = 0; i < 40; i++) {
                    p.walk();
                    expect(p.target === null || p.target >= lo - 0.01 && p.target <= hi + 0.01, "walk target on the window top: " + p.target);
                    p.idle();
                }
                expect(p.mode === "perch", "still perched");
                expect(p.walkTo(hi, { kind: "edge" }), "walk to the end");
                break;
            }
            case 8:
                expect(p.x <= 600 - p.width + 0.01 && p.x >= 299.99, "never walks off the ledge: " + p.x);
                if (!wait(p.mode === "teeter", "teeters at the end")) break;
                expect(Math.abs(p.x - (600 - p.width)) < 0.01 && p.support && p.support.id === "0xw2", "at the end of the window top");
                expect(p.animation === (Clawd.manifest.animations.teeter ? "teeter" : "idle"), "teeter animation (or its fallback)");
                p.idle();
                Config.setSetting("addonsV2ClawdSummon", 1);
                break;
            case 9:
                if (!wait(p.mode === "idle" && !p.support, "respawned on the floor")) break;
                feed([win("0xw3", 700, 150, 400, 565)]);
                seen = p.peekSpot();
                expect(seen && seen.id === "0xw3" && seen.side === -1, "a window edge to peek from: " + JSON.stringify(seen));
                expect(p.peek(seen), "peek starts");
                break;
            case 10: {
                if (!wait(p.mode === "peek", "behind the window")) break;
                const o = host.overlays[0];
                expect(p.mirrored && p.cover && p.cover.x === 700 && Math.abs(p.x - (700 - p.width / 3)) < 0.01, "2/3 behind its left edge, facing out");
                expect(o.viewport.visible && o.viewport.width > 0 && o.viewport.width < o.frameBox.width - 10 && o.viewport.x === o.frameBox.x, "viewport clipped: " + o.viewport.width + " / " + o.frameBox.width);
                expect(o.hitBox.x === o.viewport.x && o.hitBox.y === o.viewport.y && o.hitBox.width === o.viewport.width && o.hitBox.height === o.viewport.height && o.hitBox.visible, "hitBox mirrors the viewport");
                feed([win("0xw3", 720, 150, 400, 565)]);
                break;
            }
            case 11: {
                const o = host.overlays[0];
                expect(!p.cover && (p.mode === "turn" || p.mode === "walk") && p.intent && p.intent.kind === "out", "window moved: steps out");
                expect(o.viewport.width === o.frameBox.width && o.hitBox.width === o.frameBox.width, "unclipped again");
                break;
            }
            case 12:
                if (!wait(p.mode === "idle", "out, then idle")) break;
                p.mind = ({ last: {}, recent: [] });
                feed([win("0xw3", 720, 150, 400, 565), win("0xw4", 100, 100, 300, 200)]);
                expect(p.mode === "react" && p.animation.startsWith("look") && p.mind.recent.length === 1, "a window opens: he looks at it");
                mark = p.mind.last.window_open;
                break;
            case 13:
                feed([win("0xw3", 720, 150, 400, 565), win("0xw4", 100, 100, 300, 200), win("0xw5", 900, 100, 200, 150)]);
                expect(p.mind.recent.length === 1 && p.mind.last.window_open === mark, "two opens within 1 s: one reaction");
                Config.setSetting("general.performance", true);
                break;
            case 14:
                if (!wait(p.mode === "idle", "reaction over")) break;
                expect(!p.explore(), "low motion: no exploring");
                for (let i = 0; i < 40; i++) {
                    p.think();
                    expect(["hop", "peek"].indexOf(p.mode) < 0 && !(p.intent && p.intent.kind === "peek"), "low motion: no hop, no peek");
                    p.idle();
                }
                Config.setSetting("general.performance", false);
                feed([win("0xw3", 720, 150, 400, 565), win("0xw6", Math.round(cx() - 150), 650, 300, 70)]);
                break;
            case 15:
                expect(w.ledges.some(l => l.id === "0xw6"), "a low window right above him");
                expect(p.explore(), "explores again");
                Config.setSetting("addonsV2ClawdWorld", false);
                break;
            case 16:
                if (!wait(w.wins.length === 0 && w.ledges.length === 1 && ["idle", "land", "fall"].indexOf(p.mode) >= 0 && !p.support, "world off: floor only")) break;
                expect(!p.explore(), "world off: no exploring");
                drop(900, 100);
                break;
            case 17:
                if (!wait(p.mode === "idle" || p.mode === "land", "plain floor behaviour: falls to the floor")) break;
                expect(!p.support && Math.abs(p.y + p.height - 720) < 1, "on the floor, not on the window under him");
                p.mind = ({ last: {}, recent: [] });
                feed([win("0xw3", 720, 150, 400, 565), win("0xw7", 100, 100, 300, 200)]);
                expect(p.mind.recent.length === 0, "world off: no window reactions");
                Config.setSetting("addonsV2ClawdWorld", true);
                break;
            case 18:
                if (!wait(w.wins.length === 2 && p.mode === "idle", "world back")) break;
                expect(p.mind.recent.length === 0, "windows already there are not news");
                // a second screen on his right, the cursor on it
                expect(w.inject({ screens: [screen(main, 0), screen("side", 1280)], monitors: [monitor(main, 0), monitor("side", 1280)], pointer: { x: 1800, y: 300 } }), "second screen");
                p.follow(); p.follow();
                expect(p.intent && p.intent.kind === "cross" && p.intent.to === "side", "cursor elsewhere twice: walks over: " + JSON.stringify(p.intent));
                break;
            case 19:
                if (!wait(Clawd.screenName === "side", "crossed to the next screen")) break;
                expect(Math.abs(p.y + p.height - 720) < 1, "walked over on the floor");
                break;
            case 20:
                if (!wait(p.mode === "idle", "arrived")) break;
                expect(p.x >= 1280 && Clawd.screenName === "side", "on the side screen");
                expect(w.inject({ screens: [screen(main, 0)], monitors: [monitor(main, 0)], pointer: null, clients: [] }), "side screen gone");
                break;
            case 21:
                if (!wait(Clawd.screenName === main && p.mode === "idle", "back on a screen that exists")) break;
                expect(w.refreshes > 10, "snapshots counted");
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 22:
                if (!wait(Clawd.instances === 0 && !host.world, "OFF unloads the world")) break;
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
