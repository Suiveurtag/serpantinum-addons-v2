import QtQuick
import QtQuick.Effects
import "../"
import "../reusables"

// The knob is a moon: new when OFF, waxing to full as the night comes in.
Item {
    id: control
    property real uiScale: 1
    function u(value) { return Scaler.s(value) * uiScale; }
    implicitWidth: u(104)
    implicitHeight: u(48)
    readonly property bool checked: Halloween.activeSeason
    property real ignition: checked ? 1 : 0
    Behavior on ignition { enabled: Halloween.animationEnabled; NumberAnimation { duration: control.checked ? 700 : 360; easing.type: Easing.InOutSine } }
    Accessible.role: Accessible.CheckBox
    Accessible.name: "Halloween mode"
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: control.toggle()
    activeFocusOnTab: true
    function toggle() { Config.setSetting("addonsV2Halloween", !checked); }
    Keys.onSpacePressed: toggle()
    Keys.onReturnPressed: toggle()
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.tint(Qt.alpha(Halloween.colors.crust, 0.7), Qt.alpha("#3a1810", control.ignition * 0.8))
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Halloween.colors.text
            : Qt.alpha(Halloween.candle, (mouse.containsMouse ? 0.45 : 0.22) + control.ignition * 0.25)
    }
    Item {
        id: moon
        width: control.height - control.u(12); height: width
        anchors.verticalCenter: parent.verticalCenter
        x: control.u(6) + control.ignition * (control.width - width - control.u(12))
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: moonMask }
        Rectangle { id: moonMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        Rectangle { anchors.fill: parent; color: Qt.tint(Halloween.colors.overlay0, Qt.alpha(Halloween.ember, control.ignition)) }
        // the earth's shadow slides off as the moon waxes
        Rectangle {
            width: parent.width; height: width; radius: width / 2
            x: control.ignition * width * 1.05
            color: Halloween.colors.surface0
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { control.forceActiveFocus(); control.toggle(); }
    }
}
