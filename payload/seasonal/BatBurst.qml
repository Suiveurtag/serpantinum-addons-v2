import QtQuick
import QtQuick.Window
import "../"

Item {
    id: burst
    enabled: false
    property real originX: width / 2
    property real originY: height * 0.40
    property int density: 7
    readonly property int count: Math.max(0, Math.min(12, density))
    readonly property bool flying: flight.running
    readonly property bool surfaceVisible: !Window.window || Window.window.visible
    property real progress: 1
    signal finished()
    visible: progress < 1
    function play() {
        if (flying || !surfaceVisible || !Halloween.allowBurst()) return false;
        flight.restart();
        return true;
    }
    function cancel() {
        let wasFlying = flying;
        flight.stop(); progress = 1;
        if (wasFlying) finished();
    }
    onSurfaceVisibleChanged: if (!surfaceVisible) cancel()
    onVisibleChanged: if (!visible && progress < 1) cancel()
    Connections {
        target: Halloween
        function onAnimationEnabledChanged() { if (!Halloween.animationEnabled) burst.cancel(); }
    }
    Component.onCompleted: Halloween.mounted()
    Component.onDestruction: Halloween.unmounted()
    NumberAnimation {
        id: flight
        target: burst; property: "progress"; from: 0; to: 1; duration: 1750
        // Linear flight time feeds eased paths and steady wing beats separately.
        easing.type: Easing.Linear
        onFinished: burst.finished()
    }
    Repeater {
        model: burst.visible ? burst.count : 0
        delegate: Item {
            id: bat
            required property int index
            readonly property real time: Math.max(0, Math.min(1, (burst.progress - index * 0.025) / (1 - index * 0.025)))
            readonly property real p: time * time * (3 - 2 * time)
            readonly property real lane: (index + 0.5) / Math.max(1, burst.count)
            readonly property real direction: index % 2 ? 1 : -1
            width: 32 + (index % 4) * 6; height: width * 0.45
            // Cubic Bezier trajectories, normalized to the actual panel dimensions.
            x: burst.originX + direction * burst.width * ((0.035 + lane*0.05) * 3*p*Math.pow(1-p,2) + (0.14 + lane*0.25) * 3*p*p*(1-p) + (0.28 + lane*0.20)*p*p*p) - width/2
            y: burst.originY - burst.height * ((0.14 + lane*0.10) * 3*p*Math.pow(1-p,2) + (0.15 + lane*0.18) * 3*p*p*(1-p) + (0.19 + lane*0.24)*p*p*p)
            opacity: Math.min(1, p / 0.09) * Math.pow(1 - p, 0.6) * 0.92
            rotation: direction * (-18 + p * 35)
            scale: 1 - p * 0.4
            BatSilhouette {
                anchors.fill: parent
                wingPhase: burst.progress * Math.PI * 18
                variant: bat.index
            }
        }
    }
    Repeater {
        model: burst.visible ? 9 : 0
        delegate: Rectangle {
            required property int index
            readonly property real p: burst.progress
            width: 7 + (index % 3) * 4; height: 1.2; radius: height / 2
            color: Halloween.candle
            x: burst.originX + (index % 2 ? 1 : -1) * p * burst.width * (0.24 + index * 0.025)
            y: burst.originY + Math.sin(p * Math.PI + index) * burst.height * 0.1 - p * burst.height * 0.16
            opacity: Math.sin(p * Math.PI) * (1-p) * 0.9
            rotation: (index % 2 ? -1 : 1) * p * 18
        }
    }
}
