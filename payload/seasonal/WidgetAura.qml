import QtQuick
import "../"

Item {
    id: aura
    enabled: false
    property string kind: "time"
    property bool engaged: false
    property bool roundShape: false
    readonly property bool musical: kind === "music" || kind === "visualizer"
    readonly property bool weather: kind === "weather"
    readonly property bool clock: kind === "time" || kind === "clock"
    readonly property bool meter: ["cpu", "ram", "temp", "disk", "battery"].indexOf(kind) !== -1
    property real reveal: 0
    Component.onCompleted: reveal = 1
    opacity: reveal
    Behavior on reveal { NumberAnimation { duration: 750; easing.type: Easing.OutCubic } }
    FogLayer {
        anchors.fill: parent
        mode: aura.weather ? 0 : (aura.musical ? 6 : (aura.clock && aura.roundShape ? 3 : (aura.clock || aura.meter ? 2 : 5)))
        cornerRadius: aura.roundShape ? Math.min(width, height) / 2 : ThemeBackend.borderRadius
        direction: -1
        warmth: aura.weather ? 0.20 : (aura.clock ? 0.48 : 0.85)
        intensity: aura.musical ? 0.48 : (aura.weather ? 0.35 : 0.43)
        energy: aura.musical && Cava.barLevels.length ? Math.min(1, Cava.barLevels.slice(0, 8).reduce((a, b) => a + b, 0) / 8) : 0
    }
    HearthGlow {
        visible: (aura.clock && !aura.roundShape) || aura.meter
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.8; height: parent.height * 0.24
        intensity: 0.34
        engaged: aura.engaged
    }
}
