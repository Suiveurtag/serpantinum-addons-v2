import QtQuick
import "../"

Item {
    id: control
    property real uiScale: 1
    function u(value) { return Scaler.s(value) * uiScale; }
    implicitWidth: control.u(80)
    implicitHeight: control.u(44)
    readonly property bool checked: Halloween.activeSeason
    property real ignition: checked ? 1 : 0
    Behavior on ignition { NumberAnimation { duration: control.checked ? 300 : 240; easing.type: Easing.InOutCubic } }
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
        id: track
        anchors.centerIn: parent
        width: control.u(72); height: control.u(36); radius: height / 2
        color: control.checked ? "#4e342a" : ThemeBackend.crust
        border.width: control.activeFocus ? 2 : 1.5
        border.color: control.activeFocus ? ThemeBackend.text : (control.checked ? Halloween.candle : ThemeBackend.overlay0)
        Behavior on color { ColorAnimation { duration: 240 } }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? control.u(10) : track.width-width-control.u(8)
            text: control.checked ? "ON" : "OFF"
            font.family: ThemeBackend.fontFamily; font.pixelSize: control.u(10); font.bold: true
            color: control.checked ? Halloween.candle : ThemeBackend.subtext0
            opacity: Math.abs(control.ignition-0.5)*1.6+0.2
        }
        Rectangle {
            width: parent.height - control.u(8); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: control.u(4) + control.ignition * (track.width - width - control.u(8))
            color: control.checked ? Halloween.candle : ThemeBackend.subtext1
            Behavior on color { ColorAnimation { duration: 240 } }

        }
    }
    MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: { control.forceActiveFocus(); control.toggle(); }
    }
}
