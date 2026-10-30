import QtQuick
import Quickshell

ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property real startX: 0
        property var p: host.pet
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({mode: p.mode, anim: p.animation, x: p.x, y: p.y, h: p.height, here: p.here}) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function floorY() { return p.here.floor - p.height; }
        function hook(agent, event, session, extra) { Clawd.ingest(JSON.stringify(Object.assign({ agent, event, session_id: session, dir: "proj" }, extra || {}))); }
        onTriggered: {
            switch (step++) {
            case 0:
                // the test runner sends one real hook through node + clawd.sock while Clawd is OFF
                if (!wait(!!Clawd.sessions["claude:e2e"], "hook line through the socket while OFF")) break;
                expect(Clawd.activity === "work" && Clawd.sessions["claude:e2e"].dir === "e2e-dir", "socket session tracked: " + JSON.stringify(Clawd.sessions));
                hook("claude", "SessionEnd", "e2e");
                expect(Clawd.activity === "" && Object.keys(Clawd.sessions).length === 0, "SessionEnd forgets");
                expect(Clawd.instances === 0 && !host.pet, "OFF loads nothing");
                expect(Clawd.play("walk") === "off", "play while OFF");
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(Clawd.instances === Quickshell.screens.length && Clawd.manifest && host.pet, "one overlay per screen")) break;
                expect(Object.keys(Clawd.manifest.animations).length === 20 && Clawd.manifest.frame.w === 21, "manifest loaded");
                expect(p.mode === "spawn" && Clawd.screenName === Quickshell.screens[0].name, "spawns on a screen");
                expect(Math.abs(p.y - floorY()) < 1 && p.height === Clawd.manifest.frame.h * 4, "spawn on the floor at x4");
                break;
            case 2:
                if (!wait(p.mode === "idle", "spawn finishes")) break;
                expect(Clawd.play("nope") === "unknown", "unknown animation");
                expect(Clawd.play("walk") === "ok", "play ok");
                expect(p.mode === "play" && p.animation === "walk", "plays walk");
                break;
            case 3:
                if (!wait(p.mode === "idle", "loop play ends after ~3 s")) break;
                Clawd.play("land");
                expect(p.mode === "play" && p.animation === "land", "one-shot play");
                break;
            case 4:
                if (!wait(p.mode === "idle", "one-shot play ends")) break;
                p.press(Qt.MiddleButton, p.x + 5, p.y + 5);
                expect(p.mode === "play" && p.animation === "petpet" && !p.grab, "middle click pets");
                p.press(Qt.MiddleButton, p.x + 5, p.y + 5);
                expect(p.animation === "petpetheart", "petting again gets hearts");
                p.idle();
                p.press(Qt.LeftButton, p.x + 10, p.y + 10);
                p.move(p.x + 12, p.y + 10);
                expect(p.mode !== "drag", "tiny move is not a drag");
                p.move(p.x + 110, p.y - 290);
                expect(p.mode === "drag" && p.animation === "drag" && p.y < floorY() - 200, "drag lifts");
                p.release(p.x + 10, p.y + 10);
                expect(p.mode === "fall", "release falls");
                break;
            case 5:
                if (!wait(p.mode === "land" || p.mode === "idle", "falls to the floor")) break;
                expect(Math.abs(p.y - floorY()) < 1, "landed on the floor");
                break;
            case 6:
                if (!wait(p.mode === "idle", "land, then idle")) break;
                p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.release(p.x + 5, p.y + 5);
                expect(p.mode === "land", "click reacts");
                p.walk();
                break;
            case 7:
                if (!wait(p.mode === "walk", "walk starts after turn")) break;
                startX = p.x; expect(p.mirrored === (p.target < p.x), "faces the walk");
                break;
            case 8:
                if (!wait(p.mode === "idle" && !p.mirrored, "walk ends facing front")) break;
                expect(Math.abs(p.x - startX) >= 8 && Math.abs(p.y - floorY()) < 1, "walked along the floor");
                p.sleepAfter = 300; p.touch();
                break;
            case 9:
                if (!wait(p.mode === "sleep" && p.animation === "sleep", "falls asleep")) break;
                p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.release(p.x + 5, p.y + 5);
                expect(p.mode === "idle", "click wakes");
                p.sleepAfter = 600000; p.touch();
                break;
            case 10:
                p.sleep();
                expect(p.mode === "sleep", "sleeps on demand");
                expect(Clawd.play("sit") === "ok" && p.mode === "play", "play wakes");
                p.x += 50;
                Config.setSetting("addonsV2ClawdSummon", 1);
                expect(p.mode === "spawn" && Math.abs(p.x - (p.here.x + (p.here.w - p.width) / 2)) <= 1, "summon respawns centred");
                break;
            case 11:
                if (!wait(p.mode === "idle", "summon spawn ends")) break;
                Config.setSetting("addonsV2ClawdSleep", 7);
                expect(p.mode === "idle" && p.sleepAfter === 600000, "unrelated setting does not respawn");
                expect(p.pause() < 20000, "normal idle pace");
                Config.setSetting("general.performance", true);
                break;
            case 12:
                expect(Clawd.lowMotion && p.pause() >= 20000, "performance mode: far fewer idle actions");
                for (let i = 0; i < 40; i++) { p.think(); expect(p.animation.indexOf("look_") !== 0, "no looks in performance mode"); p.idle(); }
                Config.setSetting("general.performance", false);
                p.press(Qt.RightButton, p.x + 5, p.y + 5);
                expect(p.menuOpen, "right click opens the menu");
                Config.setSetting("addonsV2ClawdScale", 6);
                break;
            case 13:
                expect(p.height === Clawd.manifest.frame.h * 6 && Math.abs(p.y - floorY()) < 1, "rescale stays grounded");
                p.menuOpen = false;
                for (const bad of ["", "nope", "[]", "null", '{"agent":"x","event":"Stop"}', '{"agent":"claude","event":"Rm"}', '{"agent":"claude","event":7}'])
                    Clawd.ingest(bad);
                expect(Object.keys(Clawd.sessions).length === 0 && !Clawd.bubble, "bad lines ignored");
                hook("claude", "PreToolUse", "s0");  // a turn already running when the shell started
                expect(Clawd.activity === "work" && p.mode === "work" && p.animation === "work", "unknown session at work");
                hook("claude", "SessionEnd", "s0");
                expect(p.mode === "idle", "back to normal life");
                hook("claude", "UserPromptSubmit", "s1");
                expect(Clawd.activity === "work" && p.mode === "play" && p.animation === "think", "prompt: think");
                break;
            case 14:
                if (!wait(p.mode === "work" && p.animation === "work", "think, then work")) break;
                p.walk(); p.idle();
                expect(p.mode === "work", "no wandering while busy");
                hook("claude", "PostToolUseFailure", "s1");
                expect(p.animation === "oops", "failure: oops");
                break;
            case 15:
                if (!wait(p.mode === "work" && p.animation === "work", "oops, then work")) break;
                hook("claude", "Notification", "s1", { notification_type: "permission_prompt" });
                expect(Clawd.activity === "alert" && p.animation === "alert" && Clawd.bubble.kind === "permission" && Clawd.bubble.text === "⚠ permission · proj", "permission alert");
                hook("codex", "Notification", "c1", { notification_type: "agent_needs_input" });
                expect(Clawd.bubble.kind === "permission", "waiting never hides a permission");
                hook("claude", "PreToolUse", "s1");
                expect(!Clawd.bubble && Clawd.activity === "work" && p.animation === "work", "approved: back to work");
                hook("claude", "Stop", "s1");
                expect(Clawd.activity === "" && p.animation === "happy" && Clawd.bubble.text === "✓ terminé · proj", "stop: happy + bubble");
                hook("claude", "PostToolUse", "s1");
                expect(Clawd.activity === "", "a late async hook does not revive a stopped session");
                break;
            case 16:
                if (!wait(p.mode === "idle", "happy, then idle")) break;
                hook("codex", "UserPromptSubmit", "c2");
                hook("codex", "Notification", "c3", { notification_type: "permission_prompt" });
                hook("codex", "Interrupt", "c3");
                expect(Clawd.activity === "work" && !Clawd.bubble, "interrupt drops its alert");
                hook("codex", "Notification", "c3", { notification_type: "permission_prompt" });
                Clawd.staleMs = 400;
                break;
            case 17:
                if (!wait(!Clawd.sessions["codex:c2"], "stale session purged")) break;
                expect(Clawd.sessions["codex:c3"].phase === "alert" && Clawd.activity === "alert", "pending permission never purged");
                Clawd.staleMs = 120000;
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 18:
                expect(Clawd.instances === 0 && !host.pet, "OFF unloads");
                expect(Clawd.play("walk") === "off", "play OFF again");
                expect(Clawd.activity === "alert", "OFF keeps tracking");
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 19:
                if (!wait(!!host.pet && host.pet.mode === "work" && host.pet.animation === "alert", "comes back showing the alert")) break;
                hook("codex", "SessionEnd", "c3");
                hook("codex", "SessionEnd", "c1");
                expect(Clawd.activity === "" && !Clawd.bubble && Object.keys(Clawd.sessions).length === 0, "all sessions gone");
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 20:
                expect(Clawd.instances === 0, "OFF again");
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
