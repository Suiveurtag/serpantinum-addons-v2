import QtQuick
import "../"

Item {
    id: storm
    enabled: false
    property int resultCount: 0
    property string query: ""
    property int previousCount: 0
    property double lastStrike: 0
    property rect panelRect: Qt.rect(0, 0, width, height)
    property string edge: "top"
    Component.onCompleted: { previousCount=resultCount; Qt.callLater(opening); }
    function opening() { launch.restart(); }
    Timer { id: launch; interval: 55; onTriggered: { arc.strike(); bats.play(); } }
    onResultCountChanged: {
        if(query.length && resultCount < previousCount && Date.now()-lastStrike > 380) {
            lastStrike=Date.now(); arc.strike(); bats.play();
        }
        previousCount=resultCount;
    }
    ArcStrike {
        id: arc; x: storm.panelRect.x; y: storm.panelRect.y
        width: storm.panelRect.width; height: storm.panelRect.height; strength: 0.65
    }
    OpeningFlight { id: bats; anchors.fill: parent; panelRect: storm.panelRect; edge: storm.edge; density: 10 }
}
