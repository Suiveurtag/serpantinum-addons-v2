import QtQuick
import "../"

Item {
    id: arrival
    enabled: false
    property rect panelRect: Qt.rect(0, 0, width, height)
    property string edge: "center"
    property string scene: ""
    property int serial: 0
    function opening() { launch.restart(); }
    onSerialChanged: opening()
    Component.onCompleted: opening()
    Timer {
        id: launch; interval: 55
        onTriggered: if (Halloween.animationEnabled && arrival.visible) { arc.strike(); flock.play(); }
    }
    ArcStrike {
        id: arc
        x: arrival.panelRect.x; y: arrival.panelRect.y
        width: arrival.panelRect.width; height: arrival.panelRect.height
        strength: 0.42
    }
    OpeningFlight {
        id: flock; anchors.fill: parent
        panelRect: arrival.panelRect; edge: arrival.edge
        corner: {
            if (arrival.scene !== "music" && arrival.scene !== "network") return "";
            return (arrival.edge === "top" ? "bottom-" : "top-") + (arrival.scene === "music" ? "right" : "left");
        }
        density: arrival.scene === "guide" ? 11 : 8
    }
}
