import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    readonly property string trackpadBackend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/trackpad.py"
    property var trackpadSettings: ({speed: 0, disableWhileTyping: false, disableClicksWhileTyping: false})
    property var trackpadDevices: []
    property string trackpadRevision: ""
    property string trackpadError: ""
    property bool trackpadAvailable: false
    readonly property bool noTrackpadDetected: trackpadRevision !== "" && !trackpadAvailable
    readonly property bool trackpadEnabled: trackpadAvailable && !trackpadStatus.running && !trackpadApply.running
    function acceptTrackpad(raw, applying) {
        try {
            let result = JSON.parse(raw);
            if (!result.ok) throw new Error(result.error);
            trackpadSettings = result.data.settings;
            trackpadDevices = result.data.devices;
            trackpadRevision = result.data.revision;
            trackpadAvailable = result.data.available;
            if (applying) trackpadError = "";
        } catch (e) { trackpadError = String(e); }
    }
    function refreshTrackpad() {
        if (!trackpadStatus.running && !trackpadApply.running && !trackpadSpeed.isDragging && !trackpadDebounce.running)
            trackpadStatus.running = true;
    }
    function changeTrackpad(key, value) {
        let settings = Object.assign({}, trackpadSettings);
        settings[key] = value;
        trackpadSettings = settings;
    }
    function saveTrackpad() {
        if (!trackpadEnabled) return;
        trackpadApply.command = ["python3", trackpadBackend, "save", JSON.stringify({
            settings: trackpadSettings, devices: trackpadDevices, revision: trackpadRevision
        })];
        trackpadApply.running = true;
    }
    Process {
        id: trackpadStatus
        command: ["python3", root.trackpadBackend, "status"]
        stdout: StdioCollector { onStreamFinished: root.acceptTrackpad(text, false) }
    }
    Process {
        id: trackpadApply
        stdout: StdioCollector { onStreamFinished: root.acceptTrackpad(text, true) }
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0) root.refreshTrackpad(); }
    }
    Timer { id: trackpadDebounce; interval: 350; onTriggered: root.saveTrackpad() }
    onVisibleChanged: { if (visible) refreshTrackpad(); }
    Component.onCompleted: refreshTrackpad()
    Flickable {
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
            // BEGIN serpantinum-night-v2 option
            HalloweenCard { rootObj: root.rootObj; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-night-v2 option
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_legacy_clock"; searchTab: "addons"; searchKeywords: "calendar clock legacy horloge calendrier"
                title: "Legacy clock design"; description: "Restore the v1 calendar and clock panel."; icon: "󰥔"
                Toggle {
                    checked: Config.getSetting("addonsV2LegacyClock", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2LegacyClock", checked); }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_weather_city_obfuscation"; searchTab: "addons"; searchKeywords: "weather city location privacy obfuscated météo ville localisation"
                title: "Obfuscate weather location"; description: "Scramble the city name in the weather widget."; icon: "󰖟"
                Toggle {
                    checked: Config.getSetting("addonsV2ObfuscateWeatherCity", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2ObfuscateWeatherCity", checked); }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_mullvad_dns"; searchTab: "addons"; searchKeywords: "dns mullvad network privacy"
                title: "Mullvad DNS"; icon: "󰖟"
                description: dns.errorMessage || (dns.connectionName ? "DNS over TLS · " + dns.connectionName : "Connect to a network to change its DNS.")
                wrapText: true
                DnsControl { id: dns; Layout.preferredWidth: root.rootObj.s(170); pollEnabled: root.visible }
            }
            SettingsGroup {
                rootObj: root.rootObj
                icon: "󰟸"
                title: "Trackpad"
                description: root.trackpadError || (!root.trackpadRevision ? "Loading trackpad settings…" :
                    !root.trackpadAvailable ? "No trackpad detected." : "Adjust trackpad speed and typing protection.")
                opacity: root.noTrackpadDetected ? 0.38 : 1.0
                subSettings: [
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_trackpad_speed"; searchTab: "addons"
                        searchKeywords: "trackpad touchpad speed sensitivity vitesse pavé tactile"
                        title: "Trackpad speed"; icon: "󰟸"; wrapText: true
                        description: "Adjust pointer speed for the trackpad."
                        Draggable {
                            id: trackpadSpeed
                            Layout.rightMargin: root.rootObj.s(8)
                            implicitWidth: root.rootObj.s(180); implicitHeight: root.rootObj.s(18)
                            enabled: root.trackpadEnabled
                            from: -1; to: 1; stepSize: 0.05; defaultValue: 0
                            value: root.trackpadSettings.speed
                            showValueBubble: true
                            valueFormatter: function(v) { return (v > 0 ? "+" : "") + v.toFixed(2); }
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onDragStarted: trackpadDebounce.stop()
                            onMoved: function(val) {
                                root.changeTrackpad("speed", Math.round(val * 100) / 100);
                                if (!isDragging) trackpadDebounce.restart();
                            }
                            onDragFinished: { trackpadDebounce.stop(); root.saveTrackpad(); }
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_trackpad_typing"; searchTab: "addons"
                        searchKeywords: "trackpad touchpad typing keyboard disable saisie frappe clavier pavé tactile"
                        title: "Disable trackpad while typing"; icon: "󰌌"; wrapText: true
                        description: "Use the trackpad's native protection against accidental movement and taps while typing."
                        Toggle {
                            enabled: root.trackpadEnabled
                            checked: root.trackpadSettings.disableWhileTyping
                            accentColor: ThemeBackend.mauve
                            onToggled: function(c) {
                                trackpadDebounce.stop();
                                root.changeTrackpad("disableWhileTyping", c);
                                checked = Qt.binding(function() { return root.trackpadSettings.disableWhileTyping; });
                                root.saveTrackpad();
                            }
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_trackpad_clicks_typing"; searchTab: "addons"
                        searchKeywords: "trackpad touchpad clicks tap typing disable saisie frappe clics pavé tactile"
                        title: "Disable trackpad clicks while typing"; icon: "󰟸"; wrapText: true
                        description: "Block trackpad clicks during text entry and for 600 ms afterwards. Pointer movement stays available."
                        Toggle {
                            enabled: root.trackpadEnabled
                            checked: root.trackpadSettings.disableClicksWhileTyping
                            accentColor: ThemeBackend.mauve
                            onToggled: function(c) {
                                trackpadDebounce.stop();
                                root.changeTrackpad("disableClicksWhileTyping", c);
                                checked = Qt.binding(function() { return root.trackpadSettings.disableClicksWhileTyping; });
                                root.saveTrackpad();
                            }
                        }
                    }
                ]
            }
        }
    }
}
