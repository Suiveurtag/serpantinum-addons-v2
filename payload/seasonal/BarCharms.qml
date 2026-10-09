import QtQuick
import QtQuick.Window
import "../"

Item {
    id: charms
    enabled: false
    property string moduleId: ""
    property bool vertical: false
    property string edge: "top"
    property real cornerRadius: 12
    readonly property bool hasBat: ["left", "workspaces", "timedate", "media", "bat"].indexOf(moduleId) !== -1
    readonly property bool awake: Halloween.animationEnabled && visible && width > 0 && height > 0 && (!Window.window || Window.window.visible)
    property bool clockHeld: false
    readonly property real beat: Halloween.phase * 30 + moduleId.length
    function sync() {
        if (awake === clockHeld) return;
        clockHeld = awake; Halloween.requestClock(clockHeld);
    }
    onAwakeChanged: sync()
    Component.onCompleted: { Halloween.mounted(); sync(); }
    Component.onDestruction: { if (clockHeld) Halloween.requestClock(false); Halloween.unmounted(); }
    // Kept in the module's own bounds: grouped, resized and side modules keep their input geometry.
    Item {
        visible: charms.hasBat
        width: charms.vertical ? Math.min(23, charms.width*0.62) : Math.min(26, charms.width*0.25)
        height: width*0.46
        x: charms.vertical ? (charms.width-width)/2 : charms.width-width-3
        y: charms.edge === "bottom" ? charms.height-height-4 : 4
        rotation: Math.sin(charms.beat*0.7)*8
        BatSilhouette { anchors.fill: parent; wingPhase: charms.beat*2.1; rim: 0.92; opacity: 0.94 }
    }
    Rectangle {
        width: 3; height: 3; radius: 1.5; color: Halloween.candle
        x: charms.vertical ? charms.width-3 : 5+(charms.width-12)*(0.5+0.5*Math.sin(charms.beat*0.27))
        y: charms.vertical ? 5+(charms.height-12)*(0.5+0.5*Math.sin(charms.beat*0.27)) : charms.height-3
        opacity: 0.45+0.35*Math.sin(charms.beat*1.3)
    }
}
