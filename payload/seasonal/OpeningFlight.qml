import QtQuick
import QtQuick.Window
import "../"

// The moving frontier of the panel carries the flock. This lives outside its clip.
Item {
    id: flock
    enabled: false
    property rect panelRect: Qt.rect(0, 0, width, height)
    property string edge: "center"
    property string corner: ""
    property int density: 9
    property real sizeScale: 1
    property real travelScale: 1
    property real progress: 1
    readonly property bool flying: motion.running
    readonly property bool awake: Halloween.animationEnabled && visible && (!Window.window || Window.window.visible)
    signal finished()
    function play() {
        if (!awake || flying || panelRect.width < 10 || panelRect.height < 10) return false;
        Halloween.burstsStarted++;
        motion.restart();
        return true;
    }
    function cancel() { motion.stop(); progress = 1; }
    onAwakeChanged: if (!awake) cancel()
    Component.onCompleted: Halloween.mounted()
    Component.onDestruction: Halloween.unmounted()
    NumberAnimation {
        id: motion; target: flock; property: "progress"
        from: 0; to: 1; duration: 2050; easing.type: Easing.Linear
        onFinished: flock.finished()
    }
    Repeater {
        model: flock.progress < 1 ? Math.min(14, flock.density) : 0
        delegate: Item {
            id: bat
            objectName: "opening-bat"
            required property int index
            // Stagger launch by 65 ms; time and wing rhythm remain independent.
            readonly property real t: Math.max(0, Math.min(1, (flock.progress - index * 0.032) / (1 - index * 0.032)))
            readonly property real p: 1 - Math.pow(1 - t, 2.2)
            readonly property real lane: (index + 0.5) / Math.max(1, flock.density)
            readonly property real side: index % 2 ? 1 : -1
            readonly property bool horizontal: flock.edge === "left" || flock.edge === "right" || flock.edge === "center"
            readonly property real dx: flock.edge === "left" ? 1 : (flock.edge === "right" ? -1 : (flock.edge === "center" ? side : 0))
            readonly property real dy: flock.edge === "top" ? 1 : (flock.edge === "bottom" ? -1 : 0)
            readonly property real reach: Math.max(95, Math.min(270, (horizontal ? flock.panelRect.width : flock.panelRect.height) * 0.42)) * (0.7 + lane * 0.6) * flock.travelScale
            readonly property bool fromCorner: flock.corner.length > 0
            readonly property bool cornerLeft: flock.corner.indexOf("left") !== -1
            readonly property bool cornerTop: flock.corner.indexOf("top") !== -1
            readonly property real spread: fromCorner
                ? (horizontal ? (cornerTop ? 1 : -1)*flock.panelRect.height : (cornerLeft ? 1 : -1)*flock.panelRect.width)*lane*0.52
                : (lane - 0.5) * (horizontal ? flock.panelRect.height : flock.panelRect.width) * 0.50
            readonly property real launchX: flock.panelRect.x + (fromCorner
                ? (cornerLeft ? 9 : flock.panelRect.width-9)
                : flock.panelRect.width * (flock.edge === "left" ? 1 : (flock.edge === "right" ? 0 : (flock.edge === "center" ? (side > 0 ? 0.945 : 0.055) : 0.22 + lane * 0.56))))
            readonly property real launchY: flock.panelRect.y + (fromCorner
                ? (cornerTop ? 7 : flock.panelRect.height-7)
                : flock.panelRect.height * (flock.edge === "top" ? 1 : (flock.edge === "bottom" ? 0 : 0.25 + lane * 0.5)))
            readonly property real bend: Math.sin(t * Math.PI) * (12 + index % 3 * 9)
            width: (43 + index % 4 * 8) * flock.sizeScale; height: width * 0.46
            x: launchX + dx * reach * p + (horizontal ? side * bend * 0.35 : spread * (fromCorner ? p : p*p)) - width / 2
            y: launchY + dy * reach * p + (horizontal ? spread * (fromCorner ? p : p*p) - bend : side * bend) - height / 2
            rotation: horizontal ? dx * (-14 + t * 25) : dy * (lane - 0.5) * 40
            scale: 0.85 + Math.sin(t * Math.PI) * 0.22 - t * 0.18
            opacity: Math.min(1, t / 0.07) * (1 - Math.pow(t, 2.5)) * 0.98
            BatSilhouette {
                anchors.fill: parent; rim: 0.95
                wingPhase: flock.progress * Math.PI * (20 + bat.index % 3 * 2)
                variant: bat.index
            }
            // A short rim-light slipstream accompanies each bat, like the Play reference.
            Rectangle {
                width: 18 + bat.t * 26; height: 1.4; radius: 1
                x: bat.dx > 0 ? -width : (bat.dx < 0 ? bat.width : bat.width / 2)
                y: bat.dy > 0 ? -8 : (bat.dy < 0 ? bat.height + 8 : bat.height / 2)
                rotation: bat.horizontal ? 0 : 90
                opacity: Math.sin(bat.t * Math.PI) * 0.48
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.7; color: Halloween.candle }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }
}
