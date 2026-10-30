import QtQuick
import "../"
import "../reusables"

Item {
    id: control
    property real uiScale: 1
    property bool motionAllowed: !Config.getSetting("general.performance", false) && Capri.motion !== "reduced"
    property string accessibleName: "Capri"
    readonly property bool checked: Capri.enabled
    property real ignition: checked ? 1 : 0
    function u(v) { return Scaler.s(v) * uiScale; }
    function toggle() { Config.setSetting("addonsV2Capri", !checked); }
    implicitWidth: u(80)
    implicitHeight: u(44)
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: toggle()
    Keys.onSpacePressed: toggle()
    Keys.onReturnPressed: toggle()
    Behavior on ignition { enabled: control.motionAllowed; NumberAnimation { duration: control.checked ? 300 : 240; easing.type: Easing.InOutCubic } }
    AddonGlassSurface {
        id: track
        anchors.centerIn: parent
        width: control.u(72); height: control.u(36); radius: height / 2
        surfaceColor: control.checked ? "#291b40" : ThemeBackend.crust
        border.width: control.activeFocus ? 2 : 1.5
        border.color: control.activeFocus ? ThemeBackend.text : (control.checked ? "#b795ff" : ThemeBackend.overlay0)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? control.u(10) : track.width - width - control.u(8)
            text: control.checked ? "ON" : "OFF"
            font.family: ThemeBackend.fontFamily; font.pixelSize: control.u(10); font.bold: true
            color: control.checked ? "#fcf2f6" : ThemeBackend.subtext0
            opacity: Math.abs(control.ignition - 0.5) * 1.6 + 0.2
        }
        AddonGlassSurface {
            width: track.height - control.u(8); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: control.u(4) + control.ignition * (track.width - width - control.u(8))
            surfaceColor: control.checked ? "#b795ff" : ThemeBackend.subtext1
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { control.forceActiveFocus(); control.toggle(); } }
}
