import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../"
import "../reusables"

AddonGlassSurface {
    id: card
    required property var rootObj
    required property var strings
    property bool consumerVisible: true
    readonly property bool motionAllowed: !Config.getSetting("general.performance", false) && Capri.motion !== "reduced"
    readonly property bool previewActive: preview.status === Loader.Ready && preview.item !== null
    property real ignition: Capri.enabled ? 1 : 0
    Layout.fillWidth: true
    implicitHeight: rootObj.s(width < rootObj.s(440) ? 210 : 180)
    radius: rootObj.s(18)
    surfaceColor: ThemeBackend.surface0
    clip: true
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: roundedMask }
    Behavior on ignition { enabled: card.motionAllowed; NumberAnimation { duration: Capri.enabled ? 300 : 240; easing.type: Easing.InOutCubic } }
    Rectangle { id: roundedMask; anchors.fill: parent; radius: card.radius; color: "black"; visible: false; layer.enabled: true }
    Image {
        id: still
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: parent.width * 0.48
        source: Qt.resolvedUrl("assets/capri-icon.png"); sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit; asynchronous: true; mipmap: true
        opacity: preview.active ? 0 : 0.42 + card.ignition * 0.3
        Accessible.ignored: true
    }
    Loader {
        id: preview
        anchors.fill: still
        enabled: false
        active: Capri.enabled && card.visible && card.consumerVisible && card.width > 0 && card.height > 0
            && card.Window.window !== null && card.Window.window.visible && card.motionAllowed
        sourceComponent: CapriCardPreview { source: still.source; ignition: card.ignition }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ThemeBackend.liquidGlass ? Qt.alpha(ThemeBackend.base, 0.16) : ThemeBackend.surface0 }
            GradientStop { position: 0.5; color: ThemeBackend.liquidGlass ? Qt.alpha(ThemeBackend.base, 0.16) : ThemeBackend.surface0 }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: master.toggle() }
    RowLayout {
        anchors.fill: parent; anchors.margins: card.rootObj.s(24); spacing: card.rootObj.s(16)
        ColumnLayout {
            Layout.fillWidth: true; spacing: card.rootObj.s(6)
            Text { Layout.fillWidth: true; text: card.strings.eyebrow; elide: Text.ElideRight; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10); font.letterSpacing: 2; color: ThemeBackend.subtext0 }
            Text { Layout.fillWidth: true; text: card.strings.headline; wrapMode: Text.WordWrap; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(card.width < card.rootObj.s(440) ? 18 : 22); font.bold: true; color: ThemeBackend.text }
            Text { Layout.fillWidth: true; Layout.maximumWidth: card.width * 0.58; text: card.strings.body; wrapMode: Text.WordWrap; color: ThemeBackend.subtext1; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(12) }
            Text { Layout.fillWidth: true; text: "Super+Shift+K"; elide: Text.ElideRight; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10) }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            CapriSwitch { id: master; objectName: "capriMaster"; uiScale: 1.35; motionAllowed: card.motionAllowed; accessibleName: card.strings.toggle }
            Text { Layout.alignment: Qt.AlignHCenter; text: Capri.enabled ? card.strings.enabled : card.strings.disabled; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10) }
        }
    }
}
