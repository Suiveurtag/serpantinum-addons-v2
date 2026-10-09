import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: window
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "serpantinum-night-intro"
    mask: Region {}
    IntroScene { anchors.fill: parent }
}
