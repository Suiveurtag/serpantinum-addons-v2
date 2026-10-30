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

    // Hook ingress stays outside the Loader: Clawd OFF still tracks sessions. One JSON object per line.
    SocketServer {
        id: ingress
        active: false
        path: Caching.runDir + "/clawd.sock"
        handler: Socket { parser: SplitParser { onRead: line => Clawd.ingest(line) } }
    }
    // On reload the old shell generation unlinks clawd.sock when it closes, after the new one bound it:
    // listen only once the old generation is gone.
    Timer { interval: 1500; running: !!Caching.runDir; onTriggered: ingress.active = true }

    // OFF destroys every window, timer and the cursor socket.
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
