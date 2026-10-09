import QtQuick
import QtQuick.Window
import "../"

Item {
    id: sky
    enabled: false
    clip: true
    property real travel: 1
    property real altitude: 0.4
    property real bend: 0.08
    property bool fromLeft: true
    property real depth: 0.5
    property int crossingsStarted: 0
    property bool firstPass: true
    readonly property bool flying: flight.running
    readonly property bool awake: Halloween.animationEnabled && visible && (!Window.window || Window.window.visible)
    function schedule() {
        pause.interval = firstPass ? 650 + Math.random() * 550 : 3200 + Math.random() * 4800;
        if (awake) pause.restart();
    }
    onAwakeChanged: {
        if (awake) { firstPass = true; schedule(); }
        else { pause.stop(); flight.stop(); travel = 1; }
    }
    Component.onDestruction: Halloween.unmounted()
    Timer {
        id: pause
        onTriggered: {
            sky.firstPass = false; sky.crossingsStarted++;
            sky.altitude = 0.16 + Math.random() * 0.60;
            sky.bend = (Math.random() - 0.5) * 0.26;
            sky.fromLeft = Math.random() < 0.5;
            sky.depth = Math.random();
            flight.duration = 4600 + Math.random() * 2000;
            flight.restart();
        }
    }
    Component.onCompleted: { Halloween.mounted(); schedule(); }
    NumberAnimation {
        id: flight
        target: sky; property: "travel"; from: 0; to: 1
        easing.type: Easing.Linear
        onFinished: sky.schedule()
    }
    Repeater {
        model: sky.travel < 1 ? 2 : 0
        BatSilhouette {
            required property int index
            readonly property real t: Math.max(0, Math.min(1, (sky.travel - index * 0.09) / 0.91))
            width: Math.max(28, Math.min(54, sky.width * 0.075)) + sky.depth * 9 - index * 6
            height: width * 0.45
            x: (sky.fromLeft ? t : 1 - t) * (sky.width + width * 2) - width
            y: sky.height * (sky.altitude + Math.sin(t * Math.PI) * sky.bend) + index * 23
            wingPhase: sky.travel * Math.PI * (22 + sky.depth * 8) + index * 1.6
            opacity: Math.sin(t * Math.PI) * (0.34 + sky.depth * 0.10 - index * 0.07)
            rim: 0.72
            rotation: sky.fromLeft ? -4 : 4
        }
    }
}
