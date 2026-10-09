import QtQuick
import "../"

Canvas {
    id: web
    enabled: false
    property real intensity: Halloween.webIntensity
    property bool rightCorner: true
    property real inset: 12
    readonly property real span: Math.min(width * 0.075, height * 0.13)
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onIntensityChanged: requestPaint()
    onRightCornerChanged: requestPaint()
    onInsetChanged: requestPaint()
    Component.onCompleted: Halloween.mounted()
    Component.onDestruction: Halloween.unmounted()
    onPaint: {
        let c = getContext("2d"); c.reset();
        if (span < 10) return;
        c.translate(rightCorner ? width - inset : inset, inset);
        if (rightCorner) c.scale(-1, 1);
        c.strokeStyle = Qt.alpha(Halloween.moonlight, intensity);
        c.lineWidth = 0.65;
        let angles = [0.04, 0.29, 0.58, 0.85, 1.16, 1.51];
        let lengths = [0.95, 0.84, 1, 0.87, 0.92, 0.78];
        for (let i = 0; i < angles.length; i++) {
            c.beginPath(); c.moveTo(0, 0);
            c.lineTo(Math.cos(angles[i]) * span * lengths[i], Math.sin(angles[i]) * span * lengths[i]); c.stroke();
        }
        for (let ring = 1; ring < 6; ring++) {
            let r = span * Math.pow(ring / 6, 1.25);
            c.beginPath(); c.moveTo(Math.cos(angles[0]) * r * lengths[0], Math.sin(angles[0]) * r * lengths[0]);
            for (let i = 1; i < angles.length; i++) {
                // One broken outer strand keeps the corner from looking stamped.
                if (ring === 5 && i === 3) { c.moveTo(Math.cos(angles[i]) * r * lengths[i], Math.sin(angles[i]) * r * lengths[i]); continue; }
                let a = (angles[i] + angles[i-1]) / 2;
                c.quadraticCurveTo(Math.cos(a) * r * 0.69, Math.sin(a) * r * 0.69,
                    Math.cos(angles[i]) * r * lengths[i], Math.sin(angles[i]) * r * lengths[i]);
            }
            c.stroke();
        }
    }
}
