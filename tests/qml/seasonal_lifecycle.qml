import QtQuick
import Quickshell
import "./"

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 620; implicitHeight: 360
        color: "#171216"
        Item {
            id: scene
            anchors.fill: parent
            property int step: 0
            property real frozen: 0
            property real phaseSnapshot: 0
            property int repeatBaseline: 0
            property int reflectionBaseline: 0
            function expect(condition, message) {
                if (!condition) { console.error("SEASONAL_FAIL", step, message); Qt.exit(1); }
            }
            Loader { id: fog; active: Halloween.activeSeason; sourceComponent: FogLayer { width: 80; height: 80 } }
            ControlEffects { id: control; width: 43; height: 43; anchors.centerIn: parent; major: true; engaged: true }
            GlassReflection { id: reflection; width: 180; height: 180; visible: false }
            Timer {
                interval: 200; running: true; repeat: true
                onTriggered: {
                    switch (scene.step) {
                    case 0: control.engaged = true; break;
                    case 1: scene.expect(Halloween.burstsStarted === 1, "activation must start exactly one burst"); scene.expect(ThemeBackend.base.toString() === ThemeBackend._normalbase.toString(), "effects must not override the selected theme"); break;
                    case 2: control.activate(); scene.expect(Halloween.burstsStarted === 1, "a running burst must not restart"); break;
                    case 3: control.engaged = false; control.visible = false; break;
                    case 4: scene.expect(Halloween.hoverLoops === 0 && Halloween.instances === 1, "hidden control must unload its effects"); control.visible = true; break;
                    case 5: control.engaged = true; break;
                    case 6: scene.expect(Halloween.burstsStarted === 1 && Halloween.instances === 2, "cooldown rejection must leave no orphan burst"); control.engaged = false; break;
                    case 7: fog.item.animationEnabled = false; scene.frozen = fog.item.time; break;
                    case 9: scene.expect(fog.item.time === scene.frozen, "frozen shader changed: " + fog.item.time + " / " + scene.frozen); break;
                    case 10: scene.expect(Halloween.ambientUsers === 0, "faded control must release its clock"); scene.phaseSnapshot = Halloween.phase; break;
                    case 11: scene.expect(Halloween.phase === scene.phaseSnapshot, "unused clock must be paused"); fog.item.animationEnabled = true; break;
                    case 12: scene.expect(Halloween.phase >= scene.phaseSnapshot, "resuming clock must not rewind"); Config.setSetting("general.performance", true); break;
                    case 13: scene.expect(Halloween.ambientUsers === 0, "performance mode must release motion consumers"); Config.setSetting("general.performance", false); control.engaged = true; break;
                    case 14: scene.expect(Halloween.burstsStarted === 2, "motion must resume"); Config.setSetting("addonsV2Halloween", false); break;
                    case 15: scene.expect(Halloween.instances === 0 && Halloween.ambientUsers === 0 && Halloween.hoverLoops === 0, "OFF during flight must unload every effect"); scene.expect(ThemeBackend.base.toString() === ThemeBackend._normalbase.toString(), "OFF must restore normal palette immediately"); control.engaged = false; break;
                    case 16: Config.setSetting("addonsV2Halloween", true); break;
                    case 17: Halloween.lastBurst = Date.now() - 5000; control.engaged = true; scene.repeatBaseline = Halloween.burstsStarted; break;
                    case 18: scene.expect(scene.repeatBaseline === 3 && Halloween.hoverLoops === 1, "new sustained hover must start one loop and one burst"); break;
                    case 22: scene.reflectionBaseline = Halloween.instances; reflection.visible = true; reflection.sweep(); break;
                    case 23: scene.expect(Halloween.instances === scene.reflectionBaseline + 1, "reflection must load its shader"); break;
                    case 30: scene.expect(!reflection.reflecting && Halloween.instances === 2, "finite reflection must unload its shader"); break;
                    case 39: scene.expect(Halloween.burstsStarted === scene.repeatBaseline + 1, "sustained hover must repeat exactly once at 4.2 seconds"); break;
                    case 40: control.engaged = false; scene.expect(Halloween.hoverLoops === 0, "hover exit must stop repeats immediately"); break;
                    case 48: Config.setSetting("addonsV2Halloween", false); break;
                    case 49: scene.expect(Halloween.instances === 0 && Halloween.ambientUsers === 0 && Halloween.hoverLoops === 0, "final cleanup must be complete"); console.log("SEASONAL_PASS"); Qt.quit(); break;
                    }
                    scene.step++;
                }
            }
        }
    }
}
