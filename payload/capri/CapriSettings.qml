import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

// Settings process: master switch and the opt-in agent hooks (written only on a click, with backups).
ColumnLayout {
    id: root
    required property var rootObj
    Layout.fillWidth: true
    spacing: rootObj.s(8)
    property var hooks: ({ claude: null, codex: null })
    property string busy: ""

    function run(action, target) {
        if (busy) return;
        busy = target;
        hookProcess.action = action;
        hookProcess.target = target;
        hookProcess.command = ["node", Capri.scripts + "/hooks.js", action, target];
        hookProcess.running = true;
    }
    function refresh() { if (!busy) run("status", "claude"); }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Process {
        id: hookProcess
        property string action: ""
        property string target: ""
        property string output: ""
        property int pending: 0
        onStarted: pending = 2
        onExited: finish()
        stdout: StdioCollector { onStreamFinished: { hookProcess.output = text; hookProcess.finish(); } }
        // Stream end and exit arrive in either order; restart only once both are in.
        function finish() {
            if (--pending > 0) return;
            let result = null;
            try { result = JSON.parse(output); } catch (error) { result = { ok: false, error: "Capri helper missing: run install.py" }; }
            root.busy = "";
            // Install/uninstall results have no "installed" flag: re-read the status.
            if (action !== "status" && result.ok) return root.run("status", target);
            let next = Object.assign({}, root.hooks);
            next[target] = result;
            root.hooks = next;
            if (target === "claude" && next.codex === null) root.run("status", "codex");
        }
    }

    SettingsRow {
        rootObj: root.rootObj; settingId: "addons_capri"; searchTab: "addons"
        searchKeywords: "capri pet desktop mascot companion claude codex animal compagnon bureau mascotte"
        title: "Capri"; icon: "󰩃"; wrapText: true
        description: "Desktop companion reacting to Claude Code and Codex. Super+Shift+K toggles her; OFF unloads everything."
        Toggle {
            checked: Capri.enabled
            accentColor: ThemeBackend.mauve
            onToggled: Config.setSetting("addonsV2Capri", checked)
        }
    }

    Repeater {
        model: [
            { id: "claude", title: "Claude Code hooks", icon: "󰚩", file: "~/.claude/settings.json", after: "Start a new Claude Code session." },
            { id: "codex", title: "Codex hooks", icon: "󰘦", file: "~/.codex/hooks.json", after: "Restart Codex and trust the hooks when prompted." }
        ]
        delegate: SettingsRow {
            required property var modelData
            readonly property var hook: root.hooks[modelData.id]
            readonly property bool installed: !!(hook && hook.ok && hook.data && hook.data.installed && !hook.data.error)
            rootObj: root.rootObj; settingId: "addons_capri_hooks_" + modelData.id; searchTab: "addons"
            searchKeywords: "capri hooks " + modelData.id + " agent connect connecter brancher"
            title: modelData.title; icon: modelData.icon; wrapText: true
            description: !hook ? "Checking…"
                : !hook.ok ? hook.error
                : hook.data.error ? hook.data.error
                : installed ? "Connected in " + modelData.file + ". " + modelData.after
                : "Not connected. Adds Capri to " + modelData.file + " (a backup is kept)."
            ClickButton {
                buttonText: root.busy === modelData.id ? "…" : (installed ? "Disconnect" : "Connect")
                accentColor: installed ? ThemeBackend.surface1 : ThemeBackend.mauve
                textColor: installed ? ThemeBackend.text : ThemeBackend.crust
                onClicked: root.run(installed ? "uninstall" : "install", modelData.id)
            }
        }
    }
}
