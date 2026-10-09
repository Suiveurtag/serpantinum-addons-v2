import QtQuick
import "../"

Item {
    id: hold
    enabled: false
    property bool held: false
    property real charge: 0
    property real amount: Halloween.animationEnabled && visible && held ? Math.max(0.15, charge) : 0
    Behavior on amount { enabled: Halloween.animationEnabled; NumberAnimation { id: holdFade; duration: 220; easing.type: Easing.OutCubic } }
    onVisibleChanged: if(!visible) holdFade.stop()
    Connections { target: Halloween; function onAnimationEnabledChanged() { if(!Halloween.animationEnabled) holdFade.stop(); } }
    Loader {
        id: discharge
        anchors.fill: parent; enabled: false
        active: Halloween.animationEnabled && hold.visible && hold.amount > 0.001
        sourceComponent: ArcStrike { strength: hold.amount * 0.85; lightColor: Halloween.candle }
        onLoaded: item.strike()
    }
    Timer {
        interval: 260
        running: Halloween.animationEnabled && hold.visible && hold.held && discharge.item !== null
        repeat: true
        onTriggered: discharge.item.strike()
    }
}
