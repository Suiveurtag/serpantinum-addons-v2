import QtQuick
import "../"

Item {
    id: vigil
    enabled: false
    property real cornerRadius: 14
    property bool urgent: false
    FogLayer {
        anchors.fill: parent; cornerRadius: vigil.cornerRadius
        mode: 1; intensity: vigil.urgent ? 0.35 : 0.24; warmth: 1
    }
    CandleLight {
        x: 3; y: vigil.height - height - 6
        width: 16; height: Math.min(43, vigil.height * 0.58)
    }
    CandleLight {
        x: vigil.width - width - 3; y: vigil.height - height - 6
        width: 14; height: Math.min(35, vigil.height * 0.5); strength: 0.78
    }
}
