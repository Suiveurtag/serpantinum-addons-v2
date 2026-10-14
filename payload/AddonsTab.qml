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
            SettingsGroup {
                rootObj: root.rootObj; title: "Mouse spotlight"; icon: "󰍽"
                description: "Animated pointer highlight"
                subSettings: [
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_mouse_spotlight"; searchTab: "addons"
                        searchKeywords: "mouse spotlight pointer cursor souris curseur powertoys raccourci"
                        title: "Mouse spotlight"; icon: "󰍽"; wrapText: true
                        description: "Highlight the pointer with an animated spotlight. Search addonMouseSpotlight in Keybinds to edit or record its shortcut. Click, press Escape or use the shortcut again to dismiss. Scroll to resize the circle."
                        ClickButton {
                            buttonText: "Shortcut"; accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                            visible: typeof root.rootObj.gotoTab === "function"
                            onClicked: root.rootObj.gotoTab("addon_keybinds")
                        }
                        ClickButton {
                            buttonText: "Try spotlight"; accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
                            onClicked: Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonMouseSpotlight", "toggle"])
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_spotlight_radius"; searchTab: "addons"
                        searchKeywords: "mouse spotlight souris cercle luminosité animation"
                        title: "Circle size"; description: "Radius of the spotlight. The mouse wheel also adjusts and saves this size."; icon: "󰍽"; wrapText: true
                        Draggable {
                            implicitWidth: root.rootObj.s(180); implicitHeight: root.rootObj.s(18)
                            from: 35; to: 350; stepSize: 5
                            value: Config.getSetting("addonsV2SpotlightRadius", 95)
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) + " px"; }
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onMoved: function(val) { Config.setSetting("addonsV2SpotlightRadius", Math.round(val)); }
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_spotlight_brightness"; searchTab: "addons"
                        searchKeywords: "mouse spotlight souris cercle luminosité animation"
                        title: "Background brightness"; description: "Brightness outside the spotlight: 0% is black, 100% leaves the desktop unchanged."; icon: "󰍽"; wrapText: true
                        Draggable {
                            implicitWidth: root.rootObj.s(180); implicitHeight: root.rootObj.s(18)
                            from: 0; to: 100; stepSize: 1
                            value: (1 - Config.getSetting("addonsV2SpotlightDimming", 0.65)) * 100
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) + "%"; }
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onMoved: function(val) { Config.setSetting("addonsV2SpotlightDimming", 1 - val / 100); }
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_spotlight_entrance"; searchTab: "addons"
                        searchKeywords: "mouse spotlight souris cercle luminosité animation"
                        title: "Entrance animation"; description: "Duration of the fade-in and circle convergence."; icon: "󰍽"; wrapText: true
                        Draggable {
                            implicitWidth: root.rootObj.s(180); implicitHeight: root.rootObj.s(18)
                            from: 100; to: 1600; stepSize: 50
                            value: Config.getSetting("addonsV2SpotlightEntrance", 650)
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) + " ms"; }
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onMoved: function(val) { Config.setSetting("addonsV2SpotlightEntrance", Math.round(val)); }
                        }
                    },
                    SettingsRow {
                        rootObj: root.rootObj; settingId: "addons_spotlight_exit"; searchTab: "addons"
                        searchKeywords: "mouse spotlight souris cercle luminosité animation"
                        title: "Exit animation"; description: "Duration of the smooth fade-out and circle expansion."; icon: "󰍽"; wrapText: true
                        Draggable {
                            implicitWidth: root.rootObj.s(180); implicitHeight: root.rootObj.s(18)
                            from: 100; to: 2000; stepSize: 50
                            value: Config.getSetting("addonsV2SpotlightExit", 800)
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) + " ms"; }
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onMoved: function(val) { Config.setSetting("addonsV2SpotlightExit", Math.round(val)); }
                        }
                    }
                ]
            }
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
            Rectangle {
                id: passiveAddonsCard
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(18)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.72)
                border.width: rootObj.s(1)
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)
                implicitHeight: passiveContent.implicitHeight + rootObj.s(28)

                ColumnLayout {
                    id: passiveContent
                    anchors.fill: parent
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(8)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)
                        Rectangle {
                            Layout.preferredWidth: rootObj.s(34)
                            Layout.preferredHeight: rootObj.s(34)
                            radius: ThemeBackend.borderRadius
                            color: ThemeBackend.surface1
                            Text {
                                anchors.centerIn: parent
                                text: "󰐱"
                                color: ThemeBackend.text
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: rootObj.s(17)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text {
                                text: "Passive addons"
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Shell tools enabled without individual switches"
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(10)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: rootObj.s(2)
                        Layout.bottomMargin: rootObj.s(2)
                        height: rootObj.s(1)
                        color: Qt.alpha(ThemeBackend.surface2, 0.65)
                    }

                    Repeater {
                        model: [
                            { id: "addons_passive_color_picker", title: "Color picker", icon: "󰈊", keywords: "color picker pipette palette couleur", detail: "Super+Shift+C" },
                            { id: "addons_passive_screenshot", title: "Screenshot tools", icon: "󰹑", keywords: "screenshot capture freeze screenshot tool capture écran image", detail: "Frozen capture fixed · Super+Shift+S" },
                            { id: "addons_passive_monitors", title: "Monitor tools", icon: "󰍹", keywords: "monitor display screen monitors écran", detail: "" },
                            { id: "addons_passive_keybinds", title: "Keybind editor", icon: "󰌌", keywords: "keybind shortcut keyboard raccourci clavier", detail: "" },
                            { id: "addons_passive_theme_modes", title: "Vibrant and Vivid theme modes", icon: "󰏘", keywords: "theme matugen vibrant vivid color mode thème", detail: "" }
                        ]
                        delegate: SettingsRow {
                            required property var modelData
                            rootObj: root.rootObj
                            settingId: modelData.id; searchTab: "addons"; searchKeywords: modelData.keywords
                            title: modelData.title; icon: modelData.icon; description: modelData.detail
                            iconSize: 24; iconFontSize: 12
                            horizontalPadding: rootObj.s(8); verticalPadding: rootObj.s(6)
                            spacing: rootObj.s(10); innerSpacing: rootObj.s(4); textSpacing: rootObj.s(1)
                            titlePixelSize: 12; descriptionPixelSize: 10
                            baseColor: "transparent"; hoverColor: "transparent"

                            Rectangle {
                                Layout.preferredWidth: enabledLabel.implicitWidth + rootObj.s(18)
                                Layout.preferredHeight: rootObj.s(24)
                                radius: ThemeBackend.borderRadius
                                color: Qt.alpha(ThemeBackend.green, 0.13)
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: rootObj.s(5)
                                    Rectangle {
                                        Layout.preferredWidth: rootObj.s(6)
                                        Layout.preferredHeight: rootObj.s(6)
                                        radius: width / 2
                                        color: ThemeBackend.green
                                    }
                                    Text {
                                        id: enabledLabel
                                        text: "Enabled"
                                        color: ThemeBackend.green
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(10)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
