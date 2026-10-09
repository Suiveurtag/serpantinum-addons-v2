import QtQuick
import "../"

Item {
    id: panel
    enabled: false
    property string scene: "guide"
    property real cornerRadius: 8
    property real reveal: 0
    clip: true
    Component.onCompleted: reveal = 1
    Behavior on reveal { NumberAnimation { duration: 1000; easing.type: Easing.OutCubic } }
    opacity: reveal
    HearthGlow {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - panel.cornerRadius * 2
        height: Math.min(parent.height * 0.22, parent.width * 0.13)
        intensity: panel.scene === "calendar" ? 0.56 : 0.42
        engaged: true
    }
    ResponsiveCobweb {
        anchors.fill: parent
        visible: panel.scene === "guide"
        inset: panel.cornerRadius + 4
    }
}
