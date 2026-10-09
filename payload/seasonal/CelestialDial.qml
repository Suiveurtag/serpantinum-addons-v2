import QtQuick
import "../"

Item {
    id: dial
    enabled: false
    property real reveal: 0
    property bool perchedBats: false
    Component.onCompleted: reveal = 1
    Behavior on reveal { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
    opacity: reveal
    Repeater {
        model: dial.perchedBats && Halloween.animationEnabled ? 3 : 0
        BatSilhouette {
            required property int index
            width: Math.max(24, Math.min(36, dial.width*0.045)) - index*3
            height: width*0.46
            x: dial.width * [0.30,0.42,0.53][index] - width/2
            y: dial.height * [0.70,0.82,0.83][index] - height/2
            wingPhase: Halloween.phase*23+index*1.8
            variant: index; rim: 0.8; opacity: 0.78
            rotation: [-10,12,-6][index]
        }
    }
    Repeater {
        model: Halloween.animationEnabled ? 3 : 0
        delegate: Rectangle {
            required property int index
            readonly property real angle: Halloween.phase * (2 + index) + index * Math.PI * 0.62
            width: index === 0 ? 3 : 2; height: width; radius: width / 2
            color: index === 1 ? Halloween.moonlight : Halloween.candle
            opacity: 0.7
            x: dial.width / 2 + Math.cos(angle) * dial.width * 0.48 - width / 2
            y: dial.height / 2 + Math.sin(angle) * dial.height * 0.46 - height / 2
        }
    }
    Canvas {
        id: engraving
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: Halloween.mounted()
        Component.onDestruction: Halloween.unmounted()
        onPaint: {
            let c = getContext("2d"); c.reset();
            let cx = width / 2, cy = height / 2;
            function arc(rx, ry, start, end, alpha, color) {
                c.beginPath();
                for (let a = start; a <= end; a += 0.015) {
                    let x = cx + Math.cos(a) * rx, y = cy + Math.sin(a) * ry;
                    if (a === start) c.moveTo(x, y); else c.lineTo(x, y);
                }
                c.lineWidth = 0.7; c.strokeStyle = Qt.alpha(color, alpha); c.stroke();
            }
            arc(width * 0.43, height * 0.39, 0.12, 2.85, 0.30, Halloween.candle);
            arc(width * 0.43, height * 0.39, 3.27, 6.05, 0.22, Halloween.moonlight);
            arc(width * 0.48, height * 0.46, 3.7, 5.9, 0.16, Halloween.candle);
            arc(width * 0.48, height * 0.46, 0.5, 2.5, 0.12, Halloween.moonlight);
            for (let i = 0; i < 48; i++) {
                let a = i * Math.PI / 24, r = i % 4 === 0 ? 0.016 : 0.007;
                c.beginPath(); c.moveTo(cx + Math.cos(a) * width * 0.465, cy + Math.sin(a) * height * 0.44);
                c.lineTo(cx + Math.cos(a) * width * (0.465 + r), cy + Math.sin(a) * height * (0.44 + r));
                c.strokeStyle = Qt.alpha(Halloween.candle, i % 4 === 0 ? 0.27 : 0.10); c.stroke();
            }
            // Three small points, leaving the central time and weather nodes clear.
            for (let i = 0; i < 3; i++) {
                let a = 3.95 + i * 0.62;
                c.beginPath(); c.arc(cx + Math.cos(a) * width * 0.48, cy + Math.sin(a) * height * 0.46, i === 1 ? 1.7 : 1, 0, Math.PI * 2);
                c.fillStyle = Qt.alpha(Halloween.candle, 0.55); c.fill();
            }
        }
    }
}
