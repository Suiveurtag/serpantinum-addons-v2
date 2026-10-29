import QtQuick
import "../"

// Placeholder body until the sprite/acting port lands: head with an idle bob.
Item {
    id: pet
    width: Scaler.s(96)
    height: width

    Component.onCompleted: Capri.mounted()
    Component.onDestruction: Capri.unmounted()

    Image {
        id: head
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: width
        source: Qt.resolvedUrl("assets/capri-head.png")
        sourceSize: Qt.size(width, height)
        smooth: true
        SequentialAnimation on y {
            running: Capri.animationEnabled && pet.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: -Scaler.s(4); duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { from: -Scaler.s(4); to: 0; duration: 1400; easing.type: Easing.InOutSine }
        }
    }
}
