import QtQuick
import "../"

Item {
    id: aura
    enabled: false
    property bool playing: false
    property real energy: 0
    property real breath: energy
    Behavior on breath { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    FogLayer {
        anchors.fill: parent
        mode: 3
        intensity: aura.playing ? 0.80 : 0.34
        energy: aura.breath
        warmth: 0.82
        animationEnabled: aura.playing
    }
}
