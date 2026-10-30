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
        onTriggered: {
            switch (step++) {
            case 0:
                expect(Clawd.instances === 0 && !host.pet, "OFF loads nothing");
                expect(Clawd.play("walk") === "off", "play while OFF");
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(Clawd.instances === Quickshell.screens.length && Clawd.manifest && host.pet, "one overlay per screen")) break;
                expect(Object.keys(Clawd.manifest.animations).length === 13 && Clawd.manifest.frame.w === 21, "manifest loaded");
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
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 14:
                expect(Clawd.instances === 0 && !host.pet, "OFF unloads");
                expect(Clawd.play("walk") === "off", "play OFF again");
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
