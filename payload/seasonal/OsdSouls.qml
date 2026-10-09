import QtQuick
import QtQuick.Window
import "../"

Item {
    id: stream
    enabled: false
    property rect originRect: Qt.rect(0,0,width,height)
    property bool vertical: false
    property double lastRelease: 0
    readonly property bool live: Halloween.animationEnabled && visible && (!Window.window || Window.window.visible)
    function release() {
        if (!live || Date.now()-lastRelease < 240) return;
        let emitted=0;
        for(let i=0;i<souls.count && emitted<2;i++) {
            let soul=souls.itemAt(i);
            if(soul && !soul.flying) { soul.depart(emitted ? 1 : -1, originRect); emitted++; }
        }
        if(emitted) lastRelease=Date.now();
    }
    onLiveChanged: if(!live) for(let i=0;i<souls.count;i++) souls.itemAt(i).cancel()
    Repeater {
        id: souls
        model: 8
        delegate: Item {
            id: soul
            required property int index
            property real travel: 1
            property real side: 1
            property rect emission: Qt.rect(0,0,0,0)
            readonly property bool flying: flight.running
            readonly property real p: travel*travel*(3-2*travel)
            function depart(direction, rect) { side=direction; emission=rect; flight.restart(); }
            function cancel() { flight.stop(); travel=1; }
            x: emission.x+emission.width/2+side*(stream.vertical ? emission.width*0.35 : emission.width*0.4)
                +side*p*(82+(index%3)*17)-width/2
            y: emission.y+emission.height/2-height/2+Math.sin(p*Math.PI)*(index%2 ? -22 : 25)-p*12
            width: 52-(index%3)*4; height: 24
            opacity: Math.pow(Math.sin(travel*Math.PI),0.65)*0.9
            rotation: side>0 ? 0 : 180
            scale: 1-p*0.28
            NumberAnimation { id: flight; target: soul; property: "travel"; from: 0; to: 1; duration: 1550; easing.type: Easing.Linear }
            Loader {
                anchors.fill: parent; enabled: false
                active: soul.flying && stream.live
                sourceComponent: FogLayer { mode: 9; intensity: 0.85; energy: soul.travel; animationEnabled: false }
            }
        }
    }
}
