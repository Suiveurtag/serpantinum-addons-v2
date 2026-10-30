import QtQuick
import QtQuick.Effects

// Independent of the desktop engine and its shared JS clock.
Item {
    id: art
    enabled: false
    Accessible.ignored: true
    property url source
    property real ignition: 1
    property real phase: 0
    readonly property bool glitch: phase > 0.83 && phase < 0.88
    NumberAnimation on phase { from: 0; to: 1; duration: 6200; loops: Animation.Infinite; running: art.visible }
    Repeater {
        model: 7
        Rectangle {
            required property int index
            x: art.width * (0.16 + index * 0.11)
            y: art.height * (0.24 + (index % 3) * 0.15) + Math.sin(art.phase * Math.PI * 2 + index) * 5
            width: 2 + index % 3; height: 22 + index * 4
            rotation: -25 + index * 9
            color: index % 2 ? "#ff245d" : "#7d3af5"
            opacity: (0.15 + art.ignition * 0.4) * (0.6 + Math.sin(art.phase * Math.PI * 2 + index) * 0.4)
        }
    }
    Repeater {
        model: ["#7d3af5", "#ff245d"]
        Image {
            required property int index
            required property string modelData
            anchors.fill: parent
            source: art.source; sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit; asynchronous: true
            transform: Translate { x: art.glitch ? (index ? -7 : 7) : (index ? -2 : 3); y: index ? 0 : 2 }
            opacity: art.glitch ? 0.8 : 0.24
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1; colorizationColor: modelData }
        }
    }
    Image {
        anchors.fill: parent; source: art.source; sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit; asynchronous: true
        transform: Translate { x: art.glitch ? 3 : 0; y: Math.sin(art.phase * Math.PI * 2) * 3 }
    }
    Rectangle { width: parent.width; height: 1; color: "#fcf2f6"; opacity: 0.12; y: art.phase * art.height }
}
