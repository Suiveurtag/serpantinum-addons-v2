import QtQuick
import "../"

Item {
    id: mist
    enabled: false
    property bool engaged: false
    property real direction: 1
    property real intensity: Halloween.mistIntensity
    property real cornerRadius: 0
    property real reveal: engaged ? 1 : 0
    Behavior on reveal {
        enabled: Halloween.activeSeason
        NumberAnimation { duration: mist.engaged ? Halloween.enterDuration : Halloween.leaveDuration; easing.type: Easing.OutCubic }
    }
    Loader {
        enabled: false
        anchors.fill: parent
        active: Halloween.activeSeason && mist.visible && mist.reveal > 0.001
        sourceComponent: FogLayer {
            intensity: mist.intensity
            direction: mist.direction
            cornerRadius: mist.cornerRadius
            opacity: mist.reveal
        }
    }
}
