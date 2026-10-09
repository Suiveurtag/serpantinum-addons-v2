import QtQuick
import "../"

Item {
    id: sprite
    enabled: false
    property real wingPhase: 0
    property int variant: 0
    property real rim: 0.8
    // Cached wing contours, animated at their shoulders; the body stays steady.
    function paintWing(canvas) {
        let c=canvas.getContext("2d"); c.reset(); c.scale(canvas.width/50,canvas.height/46);
        c.beginPath(); c.moveTo(50,20);
        c.bezierCurveTo(35,11,22,2,0,0);
        c.quadraticCurveTo(12,11,13,26);
        c.quadraticCurveTo(23,20,27,36);
        c.quadraticCurveTo(39,26,48,43);
        c.quadraticCurveTo(49,30,50,20); c.closePath();
        c.fillStyle="#09070c"; c.fill();
        let light=c.createLinearGradient(0,0,0,46);
        light.addColorStop(0,Qt.alpha(Halloween.candle,sprite.rim));
        light.addColorStop(0.48,Qt.alpha(Halloween.candle,sprite.rim*0.42));
        light.addColorStop(1,"transparent");
        c.lineWidth=2.2; c.strokeStyle=light; c.stroke();
    }
    Repeater {
        model: 2
        Canvas {
            id: wing
            required property int index
            x: index*width; width: sprite.width*0.5; height: sprite.height
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: sprite.paintWing(wing)
            transform: [
                Scale { origin.x: wing.width/2; xScale: wing.index===0 ? 1 : -1 },
                Scale {
                    origin.x: wing.index===0 ? wing.width : 0
                    origin.y: wing.height*0.44
                    yScale: 0.68+Math.sin(sprite.wingPhase+sprite.variant*0.61+wing.index*0.12)*0.30
                }
            ]
            Connections { target: sprite; function onRimChanged() { wing.requestPaint(); } }
        }
    }
    Canvas {
        id: body
        x: sprite.width*0.435; y: sprite.height*0.10
        width: sprite.width*0.13; height: sprite.height*0.80
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let c=getContext("2d"); c.reset(); c.scale(width/14,height/40);
            c.beginPath(); c.moveTo(2,0); c.lineTo(6,6); c.lineTo(9,6); c.lineTo(13,0);
            c.lineTo(12,14); c.quadraticCurveTo(17,24,10,38); c.lineTo(7,34); c.lineTo(4,38);
            c.quadraticCurveTo(-2,24,2,14); c.closePath();
            c.fillStyle="#09070c"; c.fill();
            c.strokeStyle=Qt.alpha(Halloween.candle,sprite.rim*0.58); c.lineWidth=1.5; c.stroke();
        }
        Connections { target: sprite; function onRimChanged() { body.requestPaint(); } }
    }
}
