import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    property int subTabIndex: 1
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex && rootObj.currentSubTab === subTabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    readonly property string trackpadBackend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/trackpad.py"
    readonly property string mouseAccelerationBackend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/mouse_acceleration.py"
    readonly property string customCursorBackend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/custom_cursor.py"
    property string customCursorImagePath: Config.getSetting("addonsV2CustomCursorPath", "")
    property string customCursorError: ""
    property var trackpadSettings: ({speed: 0, disableWhileTyping: false, disableClicksWhileTyping: false})
    property var trackpadDevices: []
    property string trackpadRevision: ""
    property string trackpadError: ""
    property bool trackpadAvailable: false
    readonly property bool noTrackpadDetected: trackpadRevision !== "" && !trackpadAvailable
    readonly property bool trackpadEnabled: trackpadAvailable && !trackpadStatus.running && !trackpadApply.running
    property bool mouseAccelerationEnabled: false
    property string mouseAccelerationRevision: ""
    property string mouseAccelerationError: ""
    readonly property bool mouseAccelerationBusy: mouseAccelerationStatus.running || mouseAccelerationApply.running
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
    function acceptMouseAcceleration(raw, applying) {
        try {
            let result = JSON.parse(raw);
            if (!result.ok) throw new Error(result.error);
            mouseAccelerationEnabled = result.data.enabled;
            mouseAccelerationRevision = result.data.revision;
            if (applying) mouseAccelerationError = "";
        } catch (e) { mouseAccelerationError = String(e); }
    }
    function refreshMouseAcceleration() {
        if (!mouseAccelerationBusy) mouseAccelerationStatus.running = true;
    }
    function saveMouseAcceleration(enabled) {
        if (mouseAccelerationBusy || !mouseAccelerationRevision) return;
        mouseAccelerationApply.command = ["python3", mouseAccelerationBackend, "save", JSON.stringify({
            enabled: enabled, revision: mouseAccelerationRevision
        })];
        mouseAccelerationApply.running = true;
    }
    function applyCustomCursor(path) {
        if (!path || customCursorApply.running) return;
        customCursorApply.command = ["python3", customCursorBackend, "apply", path];
        customCursorApply.running = true;
    }
    function selectCustomCursor(path) {
        if (!path || path === customCursorImagePath) return;
        customCursorImagePath = path;
        Config.setSetting("addonsV2CustomCursorPath", path);
        applyCustomCursor(path);
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
    Process {
        id: mouseAccelerationStatus
        command: ["python3", root.mouseAccelerationBackend, "status"]
        stdout: StdioCollector { onStreamFinished: root.acceptMouseAcceleration(text, false) }
    }
    Process {
        id: mouseAccelerationApply
        stdout: StdioCollector { onStreamFinished: root.acceptMouseAcceleration(text, true) }
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0) root.refreshMouseAcceleration(); }
    }
    Process {
        id: customCursorApply
        stderr: StdioCollector { onStreamFinished: root.customCursorError = text.trim() }
        onExited: (exitCode, exitStatus) => { if (exitCode === 0) root.customCursorError = "" }
    }
    Timer { id: trackpadDebounce; interval: 350; onTriggered: root.saveTrackpad() }
    onVisibleChanged: {
        if (visible) {
            refreshTrackpad();
            refreshMouseAcceleration();
        }
    }
    Component.onCompleted: {
        refreshTrackpad();
        refreshMouseAcceleration();
    }
    ImagePicker {
        id: customCursorImagePicker
        rootObj: root.rootObj
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif"]
        onImageSelected: function(filePath, fileName) {
            root.selectCustomCursor(filePath);
        }
    }
    Flickable {
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_custom_cursor"; searchTab: "addons"
                searchKeywords: "custom cursor pointer image souris curseur image"
                title: qsTr("Custom cursor"); description: root.customCursorError || qsTr("Choose cursor image"); icon: "󰆹"; wrapText: true
                RowLayout {
                    spacing: root.rootObj.s(12)

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: root.rootObj.s(8)

                        ClickButton {
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: root.rootObj.s(32)
                            buttonText: qsTr("Select")
                            buttonIcon: "󰉋"
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            horizontalPadding: root.rootObj.s(14)
                            iconFontSize: root.rootObj.s(15)
                            textFontSize: root.rootObj.s(11)
                            onTriggered: customCursorImagePicker.openPicker(root.customCursorImagePath)
                        }

                        Dropdown {
                            id: customCursorPathDropdown
                            Layout.alignment: Qt.AlignRight
                            implicitWidth: root.rootObj.s(280)
                            implicitHeight: root.rootObj.s(32)
                            options: root.customCursorImagePath !== "" ? [root.customCursorImagePath] : []
                            currentIndex: 0
                            isPathSelector: true
                            fuzzySearch: true
                            placeholderText: root.customCursorImagePath !== "" ? root.customCursorImagePath : qsTr("Select image path...")
                            fontFamily: ThemeBackend.fontFamily
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            hoverColor: ThemeBackend.surface1
                            dropdownColor: ThemeBackend.surface0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            fontPixelSize: root.rootObj.s(11)
                            onValueChanged: function(index, value) { root.selectCustomCursor(value); }
                            onSelected: function(index, value) { root.selectCustomCursor(value); }
                        }
                    }

                    Rectangle {
                        id: customCursorPreviewRect
                        Layout.preferredWidth: root.rootObj.s(72)
                        Layout.preferredHeight: root.rootObj.s(72)
                        radius: ThemeBackend.borderRadius
                        color: ThemeBackend.surface0
                        border.color: Qt.alpha(ThemeBackend.surface2, 0.6)
                        border.width: 1

                        Rectangle {
                            id: customCursorMask
                            anchors.fill: parent
                            radius: ThemeBackend.borderRadius
                            color: "black"
                            visible: false
                            layer.enabled: true
                        }

                        Loader {
                            id: customCursorPreviewLoader
                            anchors.fill: parent
                            visible: false
                            active: root.customCursorImagePath !== ""
                            sourceComponent: Image {
                                source: root.customCursorImagePath !== "" ? "file://" + root.customCursorImagePath : ""
                                sourceSize: Qt.size(root.rootObj.s(64), root.rootObj.s(64))
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                            }
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: customCursorPreviewLoader.status === Loader.Ready ? customCursorPreviewLoader.item : null
                            maskEnabled: true
                            maskSource: customCursorMask
                            visible: customCursorPreviewLoader.status === Loader.Ready
                                     && customCursorPreviewLoader.item.status !== Image.Error
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.customCursorImagePath === ""
                                     || (customCursorPreviewLoader.status === Loader.Ready
                                         && customCursorPreviewLoader.item.status === Image.Error)
                            text: "󰍽"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.rootObj.s(28)
                            color: ThemeBackend.subtext0
                        }
                    }
                }
            }
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
                    }
                ]
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_zoom_click_through"; searchTab: "addons"
                searchKeywords: "desktop zoom click through mouse clickthrough souris clic"
                title: qsTr("Allow clicks while zoomed")
                description: qsTr("Pass clicks through without closing zoom. The scroll wheel also passes to the app.")
                icon: "󰍽"; wrapText: true
                Toggle {
                    checked: Config.getSetting("addonsV2ZoomAllowClicks", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: Config.setSetting("addonsV2ZoomAllowClicks", checked)
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_mouse_acceleration"; searchTab: "addons"
                searchKeywords: "mouse pointer acceleration speed souris accélération pointeur"
                title: "Mouse acceleration"; icon: "󰍽"; wrapText: true
                description: root.mouseAccelerationError || (root.mouseAccelerationRevision ?
                    (root.mouseAccelerationEnabled ? "Adaptive acceleration is enabled." : "Acceleration is disabled.") :
                    "Loading mouse settings…")
                Toggle {
                    enabled: !!root.mouseAccelerationRevision && !root.mouseAccelerationBusy
                    checked: root.mouseAccelerationEnabled
                    accentColor: ThemeBackend.mauve
                    onToggled: function(checkedValue) {
                        root.saveMouseAcceleration(checkedValue);
                        checked = Qt.binding(function() { return root.mouseAccelerationEnabled; });
                    }
                }
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
