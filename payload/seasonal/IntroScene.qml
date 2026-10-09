import QtQuick
import "../"

Item {
    id: intro
    enabled: false
    property real progress: 0
    readonly property real envelope: Math.min(1, progress / 0.17) * Math.min(1, (1-progress) / 0.30)
    Component.onCompleted: { motion.start(); launch.start(); }
    NumberAnimation { id: motion; target: intro; property: "progress"; from: 0; to: 1; duration: 3900 }
    Timer { id: launch; interval: 460; onTriggered: { arc.strike(); flock.play(); } }
    Item {
        width: Math.min(intro.width*0.32, 370); height: width
        anchors.centerIn: parent; opacity: intro.envelope * 0.86
        scale: 0.65 + intro.progress*0.50
        CelestialDial { anchors.fill: parent }
        FogLayer { anchors.fill: parent; mode: 3; intensity: 0.32; warmth: 0.8 }
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let c=getContext("2d"); c.reset();
                let cx=width/2, cy=height/2, r=width*0.23;
                let halo=c.createRadialGradient(cx,cy,r*0.65,cx,cy,r*1.65);
                halo.addColorStop(0,Qt.alpha(Halloween.ember,0.16)); halo.addColorStop(1,"transparent");
                c.fillStyle=halo; c.beginPath(); c.arc(cx,cy,r*1.65,0,Math.PI*2); c.fill();
                let moon=c.createRadialGradient(cx-r*0.3,cy-r*0.35,0,cx,cy,r);
                moon.addColorStop(0,"#efd4a1"); moon.addColorStop(0.68,"#b77442"); moon.addColorStop(1,"#60341f");
                c.fillStyle=moon; c.beginPath(); c.arc(cx,cy,r,0,Math.PI*2); c.fill();
                // Cut an eclipse into the moon without filling the transparent desktop.
                c.globalCompositeOperation="destination-out";
                c.beginPath(); c.arc(cx+r*0.30,cy-r*0.23,r*0.87,0,Math.PI*2); c.fill();
                c.globalCompositeOperation="source-over";
            }
        }
    }
    FogLayer {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: Math.min(210, intro.height*0.24)
        mode: 1; intensity: 0.50; warmth: 0.95; opacity: intro.envelope
    }
    ArcStrike {
        id: arc; width: Math.min(520, intro.width*0.6); height: Math.min(280, intro.height*0.4)
        anchors.centerIn: parent; strength: 0.55
    }
    OpeningFlight {
        id: flock; anchors.fill: parent; edge: "center"; density: 12; sizeScale: 1.2; travelScale: 2.6
        panelRect: Qt.rect(intro.width/2-110, intro.height/2-70,220,140)
    }
    CandleLight { x: intro.width*0.12; y: intro.height-height-28; width: 24; height: 76; opacity: intro.envelope }
    CandleLight { x: intro.width*0.88; y: intro.height-height-28; width: 24; height: 76; opacity: intro.envelope }
    Connections {
        target: Halloween
        function onAnimationEnabledChanged() {
            if (!Halloween.animationEnabled) { motion.stop(); launch.stop(); intro.progress=1; }
        }
    }
}
