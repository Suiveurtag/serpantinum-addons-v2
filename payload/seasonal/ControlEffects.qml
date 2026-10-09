import QtQuick
import QtQuick.Window
import "../"

Item {
    id: control
    enabled: false
    property bool engaged: false
    property bool major: false
    property real cornerRadius: 8
    property real charge: 0
    property real level: 0
    property real impulse: 0
    property bool initialized: false
    readonly property bool surfaceVisible: !Window.window || Window.window.visible
    readonly property bool interactionLive: Halloween.activeSeason && visible && surfaceVisible
    readonly property bool effectiveEngaged: interactionLive && engaged
    function updateLevel() {
        reveal.stop();
        let target = effectiveEngaged ? 1 : 0;
        if (Halloween.animationEnabled && interactionLive) {
            reveal.to = target;
            reveal.duration = effectiveEngaged ? 230 : 580;
            reveal.start();
        } else level = target;
    }
    function stopMotion() {
        flash.stop(); impulse = 0;
        bats.requested = false;
    }
    function activate() {
        if (!Halloween.animationEnabled || !interactionLive || !initialized) return;
        flash.restart();
        if (!major) return;
        if (bats.item) bats.item.play();
        else if (Date.now() - Halloween.lastBurst >= Halloween.burstCooldown) bats.requested = true;
    }
    onEffectiveEngagedChanged: {
        updateLevel();
        if (initialized && effectiveEngaged && major) activate();
    }
    onInteractionLiveChanged: if (!interactionLive) stopMotion()
    Component.onCompleted: {
        initialized = true;
        updateLevel();
        if (effectiveEngaged && major) Qt.callLater(control.activate);
    }
    NumberAnimation { id: reveal; target: control; property: "level"; easing.type: Easing.OutCubic }
    Timer {
        property bool reported: false
        interval: Halloween.hoverBurstInterval
        repeat: true
        running: control.initialized && Halloween.animationEnabled && control.major && control.effectiveEngaged
        onTriggered: control.activate()
        onRunningChanged: {
            if (reported === running) return;
            reported = running;
            Halloween.hoverLoops = Math.max(0, Halloween.hoverLoops + (reported ? 1 : -1));
        }
        Component.onDestruction: if (reported) Halloween.hoverLoops = Math.max(0, Halloween.hoverLoops - 1)
    }
    Connections {
        target: Halloween
        function onAnimationEnabledChanged() {
            if (!Halloween.animationEnabled) control.stopMotion();
            control.updateLevel();
        }
    }
    SequentialAnimation {
        id: flash
        NumberAnimation { target: control; property: "impulse"; to: 1; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: control; property: "impulse"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
    }
    Loader {
        enabled: false
        anchors.fill: parent; anchors.margins: -3
        active: control.interactionLive && (control.level > 0.001 || control.impulse > 0.001)
        sourceComponent: FogLayer {
            mode: 2; intensity: 0.72
            energy: control.charge + control.impulse
            cornerRadius: control.cornerRadius + 3
            opacity: Math.max(control.level * 0.85, control.impulse)
            warmth: 0.65
        }
    }
    Loader {
        id: bats
        enabled: false
        x: -control.width * 4.5; y: -control.height * 5
        width: control.width * 10; height: control.height * 9
        property bool requested: false
        active: control.interactionLive && Halloween.animationEnabled && control.major && requested
        onActiveChanged: if (!active) requested = false
        sourceComponent: BatBurst {
            originY: height * (5.5 / 9)
            density: 10
            onFinished: bats.requested = false
        }
        onLoaded: if (!item.play()) requested = false
    }
}
