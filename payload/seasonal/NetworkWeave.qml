import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import "../"

Item {
    id: weave
    enabled: false
    required property var cores
    required property var nodes
    property string transport: "wifi"
    property bool connected: false
    property int generation: 0
    readonly property bool surfaceVisible: !Window.window || Window.window.visible
    clip: true
    Connections {
        target: weave.nodes
        function onItemAdded() { weave.generation++; }
        function onItemRemoved() { weave.generation++; }
    }
    Connections {
        target: weave.cores
        function onItemAdded() { weave.generation++; }
        function onItemRemoved() { weave.generation++; }
    }
    // The existing hub(s) own the composition; the halo follows their real pose.
    Repeater {
        model: weave.cores ? weave.cores.count : 0
        delegate: Item {
            id: halo
            required property int index
            readonly property var core: {
                let revision = weave.generation;
                return weave.cores.itemAt(index);
            }
            readonly property point center: {
                if (!core) return Qt.point(0, 0);
                let pose = core.x + core.y + core.scale;
                return core.mapToItem(weave, core.width / 2, core.height / 2);
            }
            width: core ? core.width * core.scale * 1.55 : 0; height: width
            x: center.x - width / 2; y: center.y - height / 2
            visible: core && core.visible && width > 0
            opacity: core ? core.opacity : 0
            Loader {
                anchors.fill: parent
                enabled: false
                active: halo.visible && weave.surfaceVisible
                sourceComponent: FogLayer {
                    mode: 7; intensity: weave.connected ? 0.65 : 0.42
                    energy: weave.transport === "eth" ? 1 : (weave.transport === "bt" ? 0.5 : 0)
                    warmth: weave.transport === "bt" ? 0.20 : 0.75
                }
            }
        }
    }
    Repeater {
        model: weave.nodes ? Math.min(16, weave.nodes.count) : 0
        delegate: Item {
            id: conduit
            required property int index
            anchors.fill: parent
            readonly property var node: {
                let revision = weave.generation;
                return weave.nodes.itemAt(index);
            }
            readonly property var core: {
                let revision = weave.generation;
                return node && node.myParentIdx >= 0 ? weave.cores.itemAt(node.myParentIdx) : weave.cores.itemAt(0);
            }
            readonly property point origin: {
                if (!core) return Qt.point(0, 0);
                let pose = core.x + core.y + core.scale;
                return core.mapToItem(weave, core.width / 2, core.height / 2);
            }
            readonly property point destination: {
                if (!node) return Qt.point(0, 0);
                let pose = node.x + node.y + node.scale;
                return node.mapToItem(weave, node.width / 2, node.height / 2);
            }
            readonly property real dx: destination.x - origin.x
            readonly property real dy: destination.y - origin.y
            readonly property real length: Math.max(1, Math.hypot(dx, dy))
            readonly property real startInset: core ? core.width * core.scale / 2 + 3 : 0
            readonly property real endInset: node ? Math.min(
                node.width * node.scale / (2 * Math.max(0.01, Math.abs(dx / length))),
                node.height * node.scale / (2 * Math.max(0.01, Math.abs(dy / length)))) + 3 : 0
            readonly property point start: Qt.point(origin.x + dx / length * startInset, origin.y + dy / length * startInset)
            readonly property point end: Qt.point(destination.x - dx / length * endInset, destination.y - dy / length * endInset)
            readonly property real bend: weave.transport === "eth" ? 0 : Math.min(length * 0.08, height * 0.035) * (index % 2 ? 1 : -1)
            readonly property point control: Qt.point((start.x + end.x) / 2 - dy / length * bend, (start.y + end.y) / 2 + dx / length * bend)
            visible: node && core && node.isLoaded && core.visible && length > startInset + endInset
            opacity: node && core ? node.opacity * core.opacity : 0
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(weave.transport === "bt" ? Halloween.moonlight : Halloween.candle, 0.22)
                    strokeWidth: 0.8
                    startX: conduit.start.x; startY: conduit.start.y
                    PathQuad { x: conduit.end.x; y: conduit.end.y; controlX: conduit.control.x; controlY: conduit.control.y }
                }
            }
            Repeater {
                model: Halloween.animationEnabled && conduit.visible && weave.surfaceVisible ? 3 : 0
                delegate: Item {
                    id: packet
                    required property int index
                    readonly property real travel: (Halloween.phase / (Math.PI * 2) * (24 + conduit.index % 3 * 4) + index / 3) % 1
                    readonly property real p: travel * travel * (3 - 2 * travel)
                    readonly property real q: 1 - p
                    x: q*q*conduit.start.x + 2*q*p*conduit.control.x + p*p*conduit.end.x
                    y: q*q*conduit.start.y + 2*q*p*conduit.control.y + p*p*conduit.end.y
                    opacity: Math.pow(Math.sin(travel * Math.PI), 0.7) * 0.85
                    rotation: Math.atan2(q*(conduit.control.y-conduit.start.y)+p*(conduit.end.y-conduit.control.y),
                        q*(conduit.control.x-conduit.start.x)+p*(conduit.end.x-conduit.control.x)) * 180 / Math.PI
                    Rectangle {
                        width: weave.transport === "eth" ? 12 : 8; height: 1.6; radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: weave.transport === "bt" ? Halloween.moonlight : Halloween.candle
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: weave.transport === "bt" ? Halloween.moonlight : Halloween.candle }
                        }
                    }
                }
            }
        }
    }
}
