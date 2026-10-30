import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Direct ShellRoot child: the IPC target must exist while Clawd is OFF.
Scope {
    readonly property var pet: loader.item ? loader.item.pet : null

    IpcHandler {
        target: "clawd"
        function toggle(): void { Config.setSetting("addonsV2Clawd", !Clawd.enabled); }
        function appear(): void { Config.setSetting("addonsV2Clawd", true); }
        function hide(): void { Config.setSetting("addonsV2Clawd", false); }
        function play(name: string): string { return Clawd.play(name); }
    }

    // OFF destroys every window, timer and socket.
    Loader {
        id: loader
        active: Clawd.enabled
        sourceComponent: Scope {
            readonly property alias pet: body
            ClawdPet { id: body }
            Variants {
                model: Quickshell.screens
                delegate: ClawdOverlay { required property var modelData; screen: modelData; pet: body }
            }
        }
    }
}
