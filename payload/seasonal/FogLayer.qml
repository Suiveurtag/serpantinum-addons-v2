import QtQuick
import QtQuick.Window
import "../"

ShaderEffect {
    id: fog
    enabled: false
    property real intensity: Halloween.mistIntensity
    property real speed: 1
    property real direction: 1
    property real warmth: 0
    property real mode: 0 // 0: directional edge mist, 1: rising hearth vapor/light
    property real energy: 0
    property real cornerRadius: 0
    property bool animationEnabled: true
    readonly property size extent: Qt.size(width, height)
    readonly property color coldColor: mode === 1 ? Halloween.vapor : Halloween.moonlight
    readonly property color warmColor: Halloween.ember
    readonly property bool surfaceVisible: !Window.window || Window.window.visible
    property real parkedPhase: 0
    property real phaseOffset: 0
    readonly property real time: clockHeld ? Halloween.phase + phaseOffset : parkedPhase
    property bool clockHeld: false
    function syncClock() {
        let next = visible && surfaceVisible && width > 0 && height > 0 && opacity > 0.001 && animationEnabled && Halloween.animationEnabled;
        if (next === clockHeld) return;
        if (!next) parkedPhase = Halloween.phase + phaseOffset;
        else phaseOffset = parkedPhase - Halloween.phase;
        clockHeld = next;
        Halloween.requestClock(next);
    }
    onVisibleChanged: syncClock()
    onWidthChanged: syncClock()
    onHeightChanged: syncClock()
    onSurfaceVisibleChanged: syncClock()
    onOpacityChanged: syncClock()
    onAnimationEnabledChanged: syncClock()
    Connections {
        target: Halloween
        function onAnimationEnabledChanged() { fog.syncClock(); }
    }
    Component.onCompleted: { Halloween.mounted(); syncClock(); }
    Component.onDestruction: { if (clockHeld) Halloween.requestClock(false); Halloween.unmounted(); }
    fragmentShader: Qt.resolvedUrl("shaders/atmosphere.frag.qsb")
}
