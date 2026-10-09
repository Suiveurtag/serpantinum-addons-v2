import QtQuick
import Quickshell
import "./"
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 360
        Item {
            id: scene; anchors.fill: parent
            property int step: 0
            function expect(value,message) { if(!value) { console.error("SEASONAL_FAIL",step,message); Qt.exit(1); } }
            OsdSouls { id: souls; anchors.fill: parent; originRect: Qt.rect(180,140,280,55) }
            HoldEnergy { id: hold; x: 200; y: 220; width: 200; height: 50 }
            DistantBats { anchors.fill: parent }
            LauncherStorm { id: storm; anchors.fill: parent; query: ""; resultCount: 30 }
            Timer {
                interval: 250; running: true; repeat: true
                onTriggered: {
                    switch(scene.step) {
                    case 0: souls.release(); break;
                    case 1: scene.expect(Halloween.instances>=3,"soul heads must render alongside distant/launcher effects"); souls.release(); break;
                    case 2: hold.held=true; hold.charge=0.5; break;
                    case 3: storm.query="cal"; storm.resultCount=8; break;
                    case 5: hold.held=false; break;
                    case 7: Config.setSetting("general.performance",true); break;
                    case 8: scene.expect(Halloween.ambientUsers===0,"performance mode must stop these effects"); Config.setSetting("addonsV2Halloween",false); break;
                    case 9: scene.expect(Halloween.ambientUsers===0 && Halloween.hoverLoops===0,"OFF must not leave an animation clock or repeat loop"); console.log("SEASONAL_PASS"); Qt.quit(); break;
                    }
                    scene.step++;
                }
            }
        }
    }
}
