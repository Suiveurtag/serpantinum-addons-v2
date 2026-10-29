import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

// Full-screen transparent surface; input reaches only her (and her mask or biochip), the rest of the desktop stays clickable.
PanelWindow {
    id: overlay
    readonly property bool petHere: Capri.screenName ? Capri.screenName === screen.name : screen === Quickshell.screens[0]
    required property var world
    readonly property var engine: petHere ? world.engine : null
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.namespace: "qs-addon-capri"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        Region { item: overlay.engine && overlay.engine.hitbox.visible ? overlay.engine.hitbox : null }
        Region { item: overlay.engine && overlay.engine.maskBox.visible ? overlay.engine.maskBox : null }
        Region { item: overlay.engine && overlay.engine.chipBox.visible ? overlay.engine.chipBox : null }
    }

    Component.onCompleted: { Capri.mounted(); world.registerSurface(screen.name, overlay); }
    Component.onDestruction: { world.unregisterSurface(screen.name); Capri.unmounted(); }
}
