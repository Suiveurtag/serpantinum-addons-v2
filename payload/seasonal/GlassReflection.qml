import QtQuick
import QtQuick.Window
import "../"

Item {
    id: glass
    enabled: false
    property real cornerRadius: Math.min(width, height) / 2
    property real travel: 1
    readonly property bool reflecting: reflection.running
    readonly property bool surfaceVisible: !Window.window || Window.window.visible
    function sweep() {
        if (visible && surfaceVisible && Halloween.animationEnabled) reflection.restart();
    }
    function stop() { reflection.stop(); travel = 1; }
    onVisibleChanged: if (!visible) stop()
    onSurfaceVisibleChanged: if (!surfaceVisible) stop()
    Component.onCompleted: sweep()
    Connections {
        target: Halloween
        function onAnimationEnabledChanged() { if (!Halloween.animationEnabled) glass.stop(); }
    }
    NumberAnimation {
        id: reflection
        target: glass; property: "travel"; from: 0; to: 1; duration: 1100
        easing.type: Easing.InOutCubic
    }
    Loader {
        enabled: false
        anchors.fill: parent
        active: reflection.running && glass.visible && glass.surfaceVisible && Halloween.animationEnabled
        sourceComponent: FogLayer {
            mode: 8; intensity: 0.38
            energy: glass.travel
            cornerRadius: glass.cornerRadius
            animationEnabled: false
        }
    }
}
