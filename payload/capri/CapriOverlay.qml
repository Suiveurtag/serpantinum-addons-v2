import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

// Full-screen transparent surface; input reaches only the pet, the rest of the desktop stays clickable.
PanelWindow {
    id: overlay
    readonly property bool petHere: Capri.screenName ? Capri.screenName === screen.name : screen === Quickshell.screens[0]
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.namespace: "qs-addon-capri"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: overlay.petHere ? pet : null }

    CapriPet {
        id: pet
        visible: overlay.petHere
        x: overlay.width - width - Scaler.s(80)
        y: overlay.height - height - Scaler.s(80)
    }
}
