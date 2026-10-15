import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool active: false
    property string errorMessage: ""

    function syncWithDoNotDisturb() {
        let idleSettings = Config.getSetting("idle", ({})) || ({});
        let shouldBeActive = idleSettings.enabled === true
            && idleSettings.manualInhibit === true
            && idleSettings.keepSystemAwake === true;
        if (shouldBeActive === active) return;
        active = shouldBeActive;
        if (active) {
            errorMessage = "";
            inhibitor.running = true;
        } else if (inhibitor.running) {
            inhibitor.running = false;
        }
    }

    IpcHandler {
        target: "addonAwake"
        function status(): string {
            return JSON.stringify({active: root.active, running: inhibitor.running, error: root.errorMessage})
        }
    }

    Process {
        id: inhibitor
        command: ["systemd-inhibit", "--what=handle-lid-switch:sleep", "--mode=block",
                  "--who=Serpantinum", "--why=Keep the desktop awake for downloads and AI workflows",
                  "sleep", "infinity"]
        onExited: (exitCode, exitStatus) => {
            if (root.active && exitCode !== 0) {
                root.errorMessage = "Could not keep the laptop awake. Check that systemd-inhibit is available."
                console.warn("Awake addon inhibitor exited with code", exitCode)
                Quickshell.execDetached(["notify-send", "-a", "Serpantinum", "Awake", root.errorMessage])
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: if (!inhibitor.running) inhibitor.running = true
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() {
            root.syncWithDoNotDisturb()
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() { root.syncWithDoNotDisturb() }
    }

    Component.onCompleted: root.syncWithDoNotDisturb()
}
