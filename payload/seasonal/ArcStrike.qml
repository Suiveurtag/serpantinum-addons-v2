import QtQuick
import QtQuick.Window
import "../"

Item {
    id: arc
    enabled: false
    property real strength: 1
    property color lightColor: Halloween.moonlight
    property real pulse: 0
    property int seed: 1
    readonly property bool live: Halloween.animationEnabled && visible && (!Window.window || Window.window.visible)
    function strike() {
        if (!live) return;
        seed = 1 + Math.floor(Math.random() * 100000);
        lightning.restart();
    }
    onLiveChanged: if (!live) { lightning.stop(); pulse = 0; }
    Component.onCompleted: Halloween.mounted()
    Component.onDestruction: Halloween.unmounted()
    SequentialAnimation {
        id: lightning
        NumberAnimation { target: arc; property: "pulse"; to: 1; duration: 55; easing.type: Easing.OutCubic }
        NumberAnimation { target: arc; property: "pulse"; to: 0.24; duration: 105; easing.type: Easing.OutCubic }
        NumberAnimation { target: arc; property: "pulse"; to: 0.65; duration: 45; easing.type: Easing.OutCubic }
        NumberAnimation { target: arc; property: "pulse"; to: 0; duration: 600; easing.type: Easing.OutCubic }
    }
    Canvas {
        id: bolts
        anchors.fill: parent
        opacity: arc.pulse * arc.strength
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: arc; function onSeedChanged() { bolts.requestPaint(); } function onLightColorChanged() { bolts.requestPaint(); } }
        onPaint: {
            let c = getContext("2d"); c.reset();
            let state = arc.seed;
            function random() { state = (state * 16807) % 2147483647; return (state - 1) / 2147483646; }
            function subdivide(a, b, spread, depth) {
                if (!depth) return [a, b];
                let dx=b.x-a.x, dy=b.y-a.y, len=Math.max(1,Math.hypot(dx,dy));
                let shift=(random()-0.5)*spread;
                let mid={x:(a.x+b.x)/2-dy/len*shift,y:(a.y+b.y)/2+dx/len*shift};
                let left=subdivide(a,mid,spread*0.52,depth-1), right=subdivide(mid,b,spread*0.52,depth-1);
                return left.slice(0,-1).concat(right);
            }
            function stroke(points, width, alpha, color) {
                c.beginPath(); c.moveTo(points[0].x,points[0].y);
                for(let i=1;i<points.length;i++)c.lineTo(points[i].x,points[i].y);
                c.lineWidth=width; c.lineJoin="round"; c.lineCap="round"; c.strokeStyle=Qt.alpha(color,alpha); c.stroke();
            }
            for(let side=0;side<2;side++) {
                let y=height*(side ? 0.89 : 0.11);
                let points=subdivide({x:width*0.08,y:y},{x:width*0.92,y:y},Math.min(width,height)*0.23,5);
                stroke(points,9,0.06,arc.lightColor); stroke(points,3.1,0.23,arc.lightColor); stroke(points,0.85,0.90,"#f3efff");
                for(let branch=0;branch<3;branch++) {
                    let a=points[6+branch*9], dir=side ? -1 : 1;
                    let b={x:a.x+width*(random()-0.5)*0.12,y:a.y+dir*height*(0.06+random()*0.11)};
                    let fork=subdivide(a,b,Math.min(width,height)*0.06,3);
                    stroke(fork,2.5,0.13,arc.lightColor); stroke(fork,0.65,0.5,"#f3efff");
                }
            }
        }
    }
}
