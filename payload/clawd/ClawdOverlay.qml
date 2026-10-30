import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../"

// Full-screen transparent surface; input reaches only Clawd and his menu, the rest of the desktop stays clickable.
PanelWindow {
    id: overlay
    required property var pet
    readonly property var here: pet.display(screen.name)
    readonly property bool menuHere: pet.menuOpen && Clawd.screenName === screen.name
    readonly property bool petHere: !!here && pet.width > 0 && pet.x < here.x + here.w && pet.x + pet.width > here.x
        && pet.y < here.y + here.h && pet.y + pet.height > here.y
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: menuHere
    WlrLayershell.namespace: "qs-addon-clawd"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: menuHere ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        Region { item: hitBox.visible ? hitBox : null }
        Region { item: menu.visible ? menu : null }
    }

    ClawdSprite {
        id: body
        // the press keeps its surface (Wayland implicit grab): stay mapped here while dragged onto another screen
        visible: overlay.petHere || hit.pressed
        x: overlay.here ? Math.round(overlay.pet.x - overlay.here.x) : 0
        y: overlay.here ? Math.round(overlay.pet.y - overlay.here.y) : 0
        width: implicitWidth
        height: implicitHeight
        animation: overlay.pet.animation
        mirrored: overlay.pet.mirrored
        reverse: overlay.pet.reverse
        running: false
        frame: overlay.pet.frame

        MouseArea {
            id: hit
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            function at(mouse) {
                const p = mapToItem(overlay.contentItem, mouse.x, mouse.y);
                return Qt.point(p.x + overlay.here.x, p.y + overlay.here.y);
            }
            onPressed: mouse => { const p = at(mouse); overlay.pet.press(mouse.button, p.x, p.y); }
            onPositionChanged: mouse => { const p = at(mouse); overlay.pet.move(p.x, p.y); }
            onReleased: mouse => { if (mouse.button === Qt.LeftButton) { const p = at(mouse); overlay.pet.release(p.x, p.y); } }
            onCanceled: overlay.pet.release()
        }
    }

    // Region tracks only its item's own geometry, never a moving parent's, so mirror body here.
    Item { id: hitBox; x: body.x; y: body.y; width: body.width; height: body.height; visible: body.visible }

    ClawdMenu {
        id: menu
        pet: overlay.pet
        anchor: body
        visible: overlay.menuHere
    }

    HyprlandFocusGrab { windows: [overlay]; active: overlay.menuHere; onCleared: overlay.pet.menuOpen = false }
    Component.onCompleted: Clawd.mounted()
    Component.onDestruction: Clawd.unmounted()
}
