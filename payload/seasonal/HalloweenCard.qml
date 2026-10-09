import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../"

Rectangle {
    id: card
    required property var rootObj
    Layout.fillWidth: true
    implicitHeight: rootObj.s(180)
    radius: rootObj.s(18)
    color: ThemeBackend.surface0
    clip: true
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: roundedMask }
    Rectangle { id: roundedMask; anchors.fill: parent; radius: card.radius; color: "black"; visible: false; layer.enabled: true }
    Image {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: parent.width*0.48
        source: Halloween.artwork
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; mipmap: true
        opacity: 0.72
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ThemeBackend.surface0 }
            GradientStop { position: 0.5; color: ThemeBackend.surface0 }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.setSetting("addonsV2Halloween", !Halloween.activeSeason) }
    RowLayout {
        anchors.fill: parent; anchors.margins: card.rootObj.s(24)
        spacing: card.rootObj.s(24)
        ColumnLayout {
            Layout.fillWidth: true
            Text { text: "HALLOWEEN EFFECTS"; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10); font.letterSpacing: 2; color: ThemeBackend.subtext0 }
            Text { text: "Let the night in"; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(22); font.bold: true; color: ThemeBackend.text }
            Text {
                Layout.fillWidth: true; Layout.maximumWidth: card.width*0.58
                text: "Living mist, spectral light and wings in the shadows."
                wrapMode: Text.WordWrap; color: ThemeBackend.subtext1
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(12)
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            NightSwitch { uiScale: 1.35 }
            Text { Layout.alignment: Qt.AlignHCenter; text: Halloween.activeSeason ? "ENABLED" : "DISABLED"; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10) }
        }
    }
}
