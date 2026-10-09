import QtQuick
import "../"

Item {
    id: hearth
    enabled: false
    property real intensity: Halloween.hearthIntensity
    property real warmth: 0.85
    property bool engaged: false
    property real activation: engaged ? 1 : 0.65
    Behavior on activation { NumberAnimation { duration: 1100; easing.type: Easing.InOutSine } }
    FogLayer {
        anchors.fill: parent
        mode: 1; warmth: hearth.warmth
        intensity: hearth.intensity * hearth.activation
        speed: 0.7
    }
    // Four sparks at most; the shared phase moves them without timers/emitters.
    Repeater {
        model: Halloween.animationEnabled && hearth.visible ? 4 : 0
        delegate: Rectangle {
            required property int index
            readonly property real progress: (Halloween.phase / (Math.PI * 2) * (9 + index) + index * 0.239) % 1
            width: index % 2 ? 1 : 1.5; height: width; radius: width / 2
            color: Halloween.candle
            x: hearth.width * (0.30 + index * 0.12) + Math.sin(progress * Math.PI * 1.4 + index) * hearth.width * 0.025
            y: hearth.height * (1 - progress * 0.85)
            opacity: Math.pow(Math.sin(progress * Math.PI), 2) * hearth.intensity * 0.85
        }
    }
}
