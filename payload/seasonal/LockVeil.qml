import QtQuick
import "../"

Item {
    id: veil
    enabled: false
    property bool authenticating: false
    property bool failed: false
    property real activity: authenticating ? 1 : 0.25
    Behavior on activity { enabled: Halloween.animationEnabled; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    FogLayer { anchors.fill: parent; mode: 4; intensity: 0.46; energy: veil.activity; warmth: veil.failed ? 0.85 : 0.2; cornerRadius: ThemeBackend.borderRadius*1.5 }
    ArcStrike { id: feedback; anchors.fill: parent; strength: 0.38; lightColor: veil.failed ? ThemeBackend.red : Halloween.moonlight }
    onAuthenticatingChanged: if(authenticating) feedback.strike()
    onFailedChanged: if(failed) feedback.strike()
}
