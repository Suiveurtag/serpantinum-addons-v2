import QtQuick
import Quickshell
import "./"
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 960; implicitHeight: 640
        Item {
            id: scene; anchors.fill: parent
            property int step: 0
            property var snapshots: []
            function expect(value, message) { if (!value) { console.error("SEASONAL_FAIL",step,message); Qt.exit(1); } }
            function bat(flock) { return flock.children.find(c => c.objectName === "opening-bat"); }
            function positions() { return [top,left,right,bottom,center].map(f => { let b=bat(f); return {x:b.x,y:b.y}; }); }
            OpeningFlight { id: top; anchors.fill: parent; edge: "top"; panelRect: Qt.rect(300,160,300,250) }
            OpeningFlight { id: bottom; anchors.fill: parent; edge: "bottom"; panelRect: top.panelRect }
            OpeningFlight { id: left; anchors.fill: parent; edge: "left"; panelRect: top.panelRect }
            OpeningFlight { id: right; anchors.fill: parent; edge: "right"; panelRect: top.panelRect }
            OpeningFlight { id: center; anchors.fill: parent; edge: "center"; panelRect: top.panelRect }
            OpeningFlight { id: musicCorner; anchors.fill: parent; edge: "top"; corner: "bottom-right"; panelRect: top.panelRect }
            OpeningFlight { id: networkCorner; anchors.fill: parent; edge: "top"; corner: "bottom-left"; panelRect: top.panelRect }
            DistantBats { id: shadows; anchors.fill: parent }
            Loader { id: bar; active: Halloween.animationEnabled; sourceComponent: BarCharms { width: 140; height: 40; moduleId: "timedate" } }
            Loader { id: sideBar; active: Halloween.animationEnabled; sourceComponent: BarCharms { width: 40; height: 140; moduleId: "workspaces"; vertical: true; edge: "left" } }
            Loader { active: Halloween.animationEnabled; sourceComponent: CandleVigil { width: 350; height: 130 } }
            Loader { active: Halloween.animationEnabled && Halloween.introRunning; sourceComponent: IntroScene { width: 960; height: 640 } }
            Timer {
                interval: 200; repeat: true; running: true
                onTriggered: {
                    switch(scene.step) {
                    case 0:
                        scene.expect(Halloween.introRunning && Halloween.introsStarted===1,"startup must ignite one intro");
                        [top,left,right,bottom,center,musicCorner,networkCorner].forEach(f=>scene.expect(f.play(),"simultaneous panel openings must not lose their flock to a shared cooldown")); break;
                    case 1:
                        scene.expect(scene.bat(top).width>=43,"opening bats must be readable");
                        scene.expect(scene.bat(musicCorner).x>555 && scene.bat(networkCorner).x<345,"music and network flocks must originate at their respective corners");
                        scene.snapshots=scene.positions(); break;
                    case 2:
                        let now=scene.positions(), before=scene.snapshots;
                        scene.expect(now[0].y>before[0].y && now[3].y<before[3].y,"top and bottom flights must follow the advancing edge");
                        scene.expect(now[1].x>before[1].x && now[2].x<before[2].x && now[4].x<before[4].x,"side and centered flights must escape in the matching direction");
                        scene.expect(!top.play(),"a running opening must never restart"); break;
                    case 6:
                        scene.expect(shadows.crossingsStarted>=1 && shadows.flying,"a first background crossing must be visible quickly");
                        top.visible=false;
                        scene.expect(!top.flying,"hidden panels must cancel their opening flight"); break;
                    case 7:
                        let users=Halloween.ambientUsers;
                        bar.visible=false; sideBar.visible=false;
                        scene.expect(Halloween.ambientUsers===users-2,"hiding modular bar decorations must park both clock consumers"); break;
                    case 8:
                        Config.setSetting("general.performance",true); break;
                    case 9:
                        scene.expect(Halloween.ambientUsers===0 && !shadows.flying && !Halloween.introRunning,"performance must stop intro, crossings and permanent decorations");
                        Config.setSetting("general.performance",false); break;
                    case 10:
                        scene.expect(Halloween.introsStarted===1,"resuming performance must not replay the intro");
                        Config.setSetting("addonsV2Halloween",false); break;
                    case 11:
                        scene.expect(Halloween.ambientUsers===0,"OFF must release the bar and candle clock");
                        Config.setSetting("addonsV2Halloween",true); break;
                    case 12:
                        scene.expect(Halloween.introRunning && Halloween.introsStarted===2,"enabling effects must replay exactly one intro"); break;
                    case 33:
                        scene.expect(!Halloween.introRunning && Halloween.introsStarted===2,"intro must finish and unload after its finite lifetime");
                        Config.setSetting("addonsV2Halloween",false); break;
                    case 34:
                        scene.expect(Halloween.ambientUsers===0,"final cleanup must release all motion consumers");
                        console.log("SEASONAL_PASS"); Qt.quit(); break;
                    }
                    scene.step++;
                }
            }
        }
    }
}
