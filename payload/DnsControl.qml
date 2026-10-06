import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Switch {
    id: root
    property bool pollEnabled: visible
    property string connectionName: ""
    property string errorMessage: ""
    property string mode: "loading"
    readonly property string script: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/dns.sh"
    options: ["Off", "Mullvad"]
    currentIndex: mode === "mullvad" ? 1 : 0
    enabled: !status.running && !apply.running && mode !== "unavailable" && mode !== "loading"
    accentColor: ThemeBackend.mauve
    baseColor: ThemeBackend.surface0
    textColor: ThemeBackend.text
    activeTextColor: ThemeBackend.crust
    cornerRadius: ThemeBackend.borderRadius
    function accept(raw) {
        try {
            let data = JSON.parse(raw);
            connectionName = data.connection || "";
            errorMessage = data.status === "ok" ? "" : data.message;
            mode = data.status === "ok" ? data.mode : "unavailable";
        } catch (e) { errorMessage = String(e); mode = "unavailable"; }
    }
    function refresh() { if (!status.running && !apply.running) status.running = true; }
    onValueChanged: (index, value) => {
        apply.command = ["bash", script, "set", index === 1 ? "mullvad" : "home"]; apply.running = true;
    }
    Process { id: status; command: ["bash", root.script, "status"]; stdout: StdioCollector { onStreamFinished: root.accept(text) } }
    Process { id: apply; stdout: StdioCollector { onStreamFinished: root.accept(text) } onExited: root.refresh() }
    Timer { interval: 4000; running: root.pollEnabled; repeat: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
