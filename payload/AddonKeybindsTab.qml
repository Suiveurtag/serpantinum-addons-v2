import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Window
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
    function s(value) { return rootObj.s(value); }
    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/control.py"
    property string errorMessage: ""
    readonly property color base: ThemeBackend.base
    readonly property color text: ThemeBackend.text
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color surface0: ThemeBackend.surface0
    readonly property color surface1: ThemeBackend.surface1
    readonly property color surface2: ThemeBackend.surface2
    readonly property color overlay0: ThemeBackend.overlay0
    readonly property color peach: ThemeBackend.peach
    readonly property color red: ThemeBackend.red
    readonly property color green: ThemeBackend.green
    property string revision: ""
    property int highlightedBox: -1
    property string query: ""
    property int modelChange: 0
    property var bindTypes: ["bind"]
    property var dispatchers: ["exec"]
    ListModel { id: dynamicKeybindsModel }
    function clearHighlight() { highlightedBox = -1; }
    function loadData(data) {
        revision = data.revision;
        dynamicKeybindsModel.clear();
        for (let row of data.rows) {
            let parts = row.key.split("+").map(v => v.trim());
            dynamicKeybindsModel.append({type: "bind", mods: parts.slice(0, -1).join(" "), key: parts[parts.length - 1], dispatcher: row.command !== null ? "exec" : row.action, command: row.command || "", execEditable: row.command !== null, isEditing: false, sourceLine: row.line, original: row.original});
        }
        modelChange++;
    }
    function add() {
        dynamicKeybindsModel.append({type: "bind", mods: "SUPER", key: "", dispatcher: "exec", command: "", execEditable: true, isEditing: true, sourceLine: -1, original: ""});
        modelChange++;
        Qt.callLater(() => keybindTabRoot.scrollToBottom());
    }
    function saveAllKeybinds() {
        if (worker.running) return;
        let rows = [];
        for (let i = 0; i < dynamicKeybindsModel.count; i++) {
            let row = dynamicKeybindsModel.get(i);
            let mods = row.mods.replace(/\$mainMod/g, "SUPER").replace(/SHIFT_[LR]/g, "SHIFT").trim().split(/\s+/).filter(v => v !== "");
            rows.push({line: row.sourceLine, key: mods.concat([row.key]).join(" + "), command: row.execEditable ? row.command : null, original: row.original});
        }
        worker.command = ["python3", backend, "save-keys", JSON.stringify({revision: revision, rows: rows})]; worker.running = true;
    }
    function validateKeybind(index, mods, key, dispatcher, command) {
        if (!key.trim()) return "Choose a shortcut first.";
        if (dynamicKeybindsModel.get(index).execEditable && !command.trim()) return "Enter a command first.";
        let chord = (mods + " " + key).replace(/\$mainMod/g, "SUPER").replace(/SHIFT_[LR]/g, "SHIFT").toLowerCase();
        for (let i = 0; i < dynamicKeybindsModel.count; i++) {
            let row = dynamicKeybindsModel.get(i);
            if (i !== index && (row.mods + " " + row.key).replace(/\$mainMod/g, "SUPER").replace(/SHIFT_[LR]/g, "SHIFT").toLowerCase() === chord) return "This shortcut already exists.";
        }
        return "VALID";
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (!result.ok) { root.errorMessage = result.error; return; }
                    root.errorMessage = ""; root.loadData(result.data);
                } catch (e) { root.errorMessage = String(e); }
            }
        }
    }
    function refresh() { if (!worker.running) { worker.command = ["python3", backend, "keys"]; worker.running = true; } }
    Component.onCompleted: refresh()
    ColumnLayout {
        anchors.fill: parent; anchors.margins: root.s(24); spacing: root.s(14)
        SettingsRow {
            rootObj: root.rootObj; title: "Keybinds"; description: "Click a shortcut to edit or record its keys."; icon: "󰌌"
            ClickButton { buttonText: "Reload"; accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text; onClicked: root.refresh() }
            ClickButton { buttonText: "Add"; accentColor: ThemeBackend.peach; textColor: ThemeBackend.crust; onClicked: root.add() }
        }
        Input { Layout.fillWidth: true; placeholderText: "Search shortcuts and commands"; showClearButton: true; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text; accentColor: ThemeBackend.peach; borderColor: ThemeBackend.surface2; onTextEdited: value => root.query = value.toLowerCase() }
        Text { visible: root.errorMessage !== ""; text: root.errorMessage; color: ThemeBackend.red; font.family: ThemeBackend.fontFamily; wrapMode: Text.WordWrap; Layout.fillWidth: true }
Item {
            id: keybindTabRoot
            Layout.fillWidth: true; Layout.fillHeight: true

            function scrollToBottom() {
                keybindFlickable.contentY = Math.max(0, keybindsColLayout.implicitHeight - keybindFlickable.height + root.s(100));
            }
            function scrollTo(y) {
                let maxY = Math.max(0, keybindFlickable.contentHeight - keybindFlickable.height);
                keybindFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
            }
            function scrollToBox(approxItemY) {
                let viewH = keybindFlickable.height;
                let itemTop = approxItemY;
                let itemBottom = approxItemY + root.s(56);
                let curY = keybindFlickable.contentY;
                let maxY = Math.max(0, keybindFlickable.contentHeight - viewH);
                if (itemTop < curY + root.s(10)) {
                    keybindFlickable.contentY = Math.max(0, itemTop - root.s(20));
                } else if (itemBottom > curY + viewH - root.s(10)) {
                    keybindFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
                }
            }

            Flickable {
                id: keybindFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: keybindsColLayout.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

                ColumnLayout {
                    id: keybindsColLayout
                    width: parent.width
                    spacing: root.s(8)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: wsCol.implicitHeight + root.s(32)
                        radius: root.s(12)
                        color: root.surface0
                        border.color: root.surface1; border.width: 1
                        ColumnLayout {
                            id: wsCol
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(10)
                            Text { text: "Workspaces (SUPER + 1–0)"; font.family: ThemeBackend.fontFamily; font.weight: Font.Medium; font.pixelSize: root.s(12); color: root.text; Layout.alignment: Qt.AlignVCenter }
                            Flow {
                                Layout.fillWidth: true; spacing: root.s(7)
                                Repeater {
                                    model: 10
                                    Rectangle {
                                        property int wsNum: index + 1
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: wsMa.containsMouse ? root.peach : root.surface1
                                        border.color: wsMa.containsMouse ? root.peach : "transparent"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent; text: parent.wsNum
                                            font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: wsMa.containsMouse ? root.base : root.peach
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["serpantinum", "msg", "workspace", wsNum.toString()]) }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: kbListView
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        implicitHeight: {
                            let revision = root.modelChange;
                            let total = 0;
                            for (let i = 0; i < count; i++) { let row = itemAtIndex(i); total += row ? row.height + spacing : root.s(56); }
                            return total + root.s(20);
                        }
                        model: dynamicKeybindsModel
                        interactive: false
                        cacheBuffer: root.s(2000)
                        displayMarginBeginning: root.s(100)
                        displayMarginEnd: root.s(100)
                        spacing: root.s(8)

                        delegate: Rectangle {
                            id: kbRowRect
                            property int outerIndex: index
                            visible: root.query === "" || (model.mods + " " + model.key + " " + model.dispatcher + " " + model.command).toLowerCase().indexOf(root.query) !== -1
                            property bool isJumpHighlighted: root.highlightedBox === outerIndex

                            property bool layoutReady: false
                            Component.onCompleted: Qt.callLater(() => layoutReady = true)

                            width: kbListView.width
                            height: visible ? root.s(44) + (model.isEditing ? editPanel.implicitHeight + root.s(12) : 0) : 0
                            onHeightChanged: root.modelChange++
                            radius: root.s(8)

                            HoverHandler { id: rowHover }
                            property bool isHovered: rowHover.hovered || model.isEditing || isJumpHighlighted
                            property bool isTypeOpen: false
                            property bool isDispOpen: false

                            color: isJumpHighlighted ? root.surface1 : (isHovered ? root.surface1 : root.surface0)
                            border.color: isJumpHighlighted ? root.peach : (isHovered ? Qt.alpha(root.peach, 0.5) : root.surface1)
                            border.width: isJumpHighlighted ? 2 : 1

                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.width { NumberAnimation { duration: 150 } }

                            MouseArea { anchors.fill: parent; z: -2; onClicked: root.highlightedBox = outerIndex; }

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(10)

                                Item {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(24); clip: true

                                    Row {
                                        id: modKeyContainer
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: root.s(5)
                                        Rectangle {
                                            width: k1Text.implicitWidth + root.s(10); height: root.s(24); radius: root.s(4)
                                            color: root.surface1
                                            border.color: root.surface2; border.width: 1
                                            visible: model.mods !== ""
                                            Text {
                                                id: k1Text; anchors.centerIn: parent; text: model.mods
                                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                                color: root.peach
                                            }
                                        }
                                        Text {
                                            text: "+"; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                            color: root.overlay0
                                            visible: model.mods !== "" && model.key !== ""; anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Rectangle {
                                            width: k2Text.implicitWidth + root.s(10); height: root.s(24); radius: root.s(4)
                                            color: root.surface1
                                            border.color: root.surface2; border.width: 1
                                            visible: model.key !== ""
                                            Text {
                                                id: k2Text; anchors.centerIn: parent; text: model.key
                                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                                color: root.peach
                                            }
                                        }
                                    }

                                    // Edit button
                                    Rectangle {
                                        id: editButtonSlide
                                        width: root.s(26); height: root.s(26); radius: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: kbRowRect.isHovered ? parent.width - width : parent.width
                                        color: model.isEditing
                                            ? root.peach
                                            : (editMa.containsMouse ? root.peach : root.surface2)

                                        Behavior on x {
                                            enabled: kbRowRect.layoutReady
                                            NumberAnimation { duration: 250; easing.type: Easing.OutQuart }
                                        }
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: model.isEditing ? "▴" : "󰏫"
                                            font.family: model.isEditing ? "Inter" : "Iosevka Nerd Font"
                                            font.pixelSize: root.s(13)
                                            color: model.isEditing
                                                ? root.base
                                                : (editMa.containsMouse ? root.base : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea {
                                            id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                            onClicked: {
                                                dynamicKeybindsModel.setProperty(outerIndex, "isEditing", !model.isEditing);
                                                kbRowRect.isTypeOpen = false;
                                                kbRowRect.isDispOpen = false;
                                                if (!model.isEditing) {
                                                    root.forceActiveFocus();
                                                }
                                            }
                                        }
                                    }
                                    Item {
                                        id: cmdClipRect
                                        anchors.left: modKeyContainer.right; anchors.leftMargin: root.s(8)
                                        anchors.right: editButtonSlide.left; anchors.rightMargin: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter; height: parent.height; clip: true

                                        property int marqueeSpacing: root.s(60)
                                        property bool shouldMarquee: kbRowRect.isHovered && cmdTextMain.implicitWidth > width

                                        Item {
                                            id: marqueeContainer
                                            height: parent.height
                                            width: cmdClipRect.shouldMarquee ? cmdTextMain.implicitWidth * 2 + cmdClipRect.marqueeSpacing : parent.width
                                            anchors.verticalCenter: parent.verticalCenter



                                            Row {
                                                spacing: cmdClipRect.marqueeSpacing; anchors.verticalCenter: parent.verticalCenter

                                                Text {
                                                    id: cmdTextMain; text: (model.dispatcher + " " + model.command).trim()
                                                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                    color: root.subtext0
                                                }
                                                Text {
                                                    id: cmdTextClone; text: cmdTextMain.text; font: cmdTextMain.font; color: cmdTextMain.color
                                                    visible: cmdClipRect.shouldMarquee
                                                }
                                            }

                                            SequentialAnimation on x {
                                                id: cmdAnim; loops: Animation.Infinite
                                                running: cmdClipRect.shouldMarquee && kbRowRect.layoutReady
                                                PauseAnimation { duration: 1500 }
                                                NumberAnimation { from: 0; to: -(cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing); duration: (cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing) * 25 }
                                                PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                            }
                                            onXChanged: { if (!cmdClipRect.shouldMarquee && x !== 0) x = 0; }
                                        }

                                        onShouldMarqueeChanged: {
                                            if (shouldMarquee) { marqueeContainer.x = 0; cmdAnim.restart(); }
                                            else { cmdAnim.stop(); marqueeContainer.x = 0; }
                                        }
                                    }

                                    MouseArea {
                                        id: bindMa
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: editButtonSlide.left
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton; enabled: !model.isEditing
                                        onClicked: dynamicKeybindsModel.setProperty(outerIndex, "isEditing", true)
                                    }
                                }

                                // ── Edit panel ───────────────────────────────
                                ColumnLayout {
                                    id: editPanel
                                    Layout.fillWidth: true; visible: model.isEditing; spacing: root.s(8); clip: true

                                    // Record shortcut
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(6)
                                        color: recordMa.pressed || captureTrap.activeFocus
                                            ? Qt.alpha(root.red, 0.12)
                                            : root.surface0
                                        border.color: recordMa.pressed || captureTrap.activeFocus
                                            ? root.red
                                            : root.surface2
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent; font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: captureTrap.activeFocus ? root.red : root.text
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            text: captureTrap.activeFocus ? "Press Keys (Esc to confirm)..." : (model.mods ? model.mods + " + " : "") + (model.key || "[Click to Record Shortcut]")
                                        }
                                        MouseArea {
                                            id: recordMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { captureTrap.accumulatedMods = []; captureTrap.accumulatedKey = ""; captureTrap.forceActiveFocus(); }
                                        }
                                        Item {
                                            id: captureTrap
                                            focus: false
                                            property var accumulatedMods: []
                                            property string accumulatedKey: ""
                                            Keys.onTabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onBacktabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onReturnPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEnterPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEscapePressed: (event) => { captureTrap.focus = false; event.accepted = true; }
                                            Keys.onShortcutOverride: (event) => { event.accepted = true; }
                                            Keys.onReleased: (event) => { event.accepted = true; }
                                            Keys.onPressed: (event) => { event.accepted = true; processKey(event); }
                                            function processKey(event) {
                                                if (event.key === Qt.Key_Escape) return;
                                                let newMods = [];
                                                if (event.modifiers & Qt.MetaModifier) newMods.push("$mainMod");
                                                if (event.modifiers & Qt.ControlModifier) newMods.push("CTRL");
                                                if (event.modifiers & Qt.AltModifier) newMods.push("ALT");
                                                if (event.modifiers & Qt.ShiftModifier) newMods.push("SHIFT_L");
                                                let isModifierOnly = (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R ||
                                                                      event.key === Qt.Key_Meta || event.key === Qt.Key_Control ||
                                                                      event.key === Qt.Key_Alt || event.key === Qt.Key_Shift ||
                                                                      event.key === Qt.Key_CapsLock);
                                                if (isModifierOnly) {
                                                    let mergedMods = [...captureTrap.accumulatedMods];
                                                    for (let m of newMods) { if (!mergedMods.includes(m)) mergedMods.push(m); }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", mergedMods.join(" "));
                                                    captureTrap.accumulatedMods = mergedMods;
                                                    return;
                                                }
                                                let k = "";
                                                if (event.key === Qt.Key_Space) k = "SPACE";
                                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) k = "RETURN";
                                                else if (event.key === Qt.Key_Tab) k = "TAB";
                                                else if (event.key === Qt.Key_Print) k = "Print";
                                                else if (event.key === Qt.Key_Left) k = "left";
                                                else if (event.key === Qt.Key_Right) k = "right";
                                                else if (event.key === Qt.Key_Up) k = "up";
                                                else if (event.key === Qt.Key_Down) k = "down";
                                                else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) { k = "F" + (event.key - Qt.Key_F1 + 1); }
                                                else if (event.text && event.text.length > 0) k = event.text.toUpperCase();
                                                else k = event.key.toString();
                                                captureTrap.accumulatedMods = newMods;
                                                dynamicKeybindsModel.setProperty(outerIndex, "mods", newMods.join(" "));
                                                captureTrap.accumulatedKey = k;
                                                dynamicKeybindsModel.setProperty(outerIndex, "key", k);
                                            }
                                            ShortcutInhibitor { window: captureTrap.Window.window; enabled: captureTrap.activeFocus }
                                            onActiveFocusChanged: if (!activeFocus) { accumulatedMods = []; accumulatedKey = ""; }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: root.s(8); Layout.alignment: Qt.AlignTop; z: 2
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(8)) * 0.4; Layout.alignment: Qt.AlignTop; spacing: root.s(4)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(6)
                                                scale: kbRowRect.isTypeOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isTypeOpen
                                                    ? Qt.alpha(root.peach, 0.12)
                                                    : root.surface0
                                                border.color: kbRowRect.isTypeOpen ? root.peach : root.surface2
                                                border.width: kbRowRect.isTypeOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Behavior on border.width { NumberAnimation { duration: 150 } }
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(7)
                                                    Text {
                                                        text: model.type; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isTypeOpen ? "▴" : "▾"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kbRowRect.isTypeOpen = !kbRowRect.isTypeOpen; kbRowRect.isDispOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isTypeOpen ? root.bindTypes.length * root.s(26) : 0
                                                radius: root.s(6); color: root.surface0; clip: true
                                                border.color: root.surface1; border.width: kbRowRect.isTypeOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.bindTypes; interactive: false
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: typeItemMa.containsMouse ? Qt.alpha(root.peach, 0.12) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(8); text: modelData
                                                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                            color: model.type === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: typeItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "type", modelData); kbRowRect.isTypeOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(8)) * 0.6; Layout.alignment: Qt.AlignTop; spacing: root.s(4)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(6)
                                                scale: kbRowRect.isDispOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isDispOpen
                                                    ? Qt.alpha(root.peach, 0.12)
                                                    : root.surface0
                                                border.color: kbRowRect.isDispOpen ? root.peach : root.surface2
                                                border.width: kbRowRect.isDispOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Behavior on border.width { NumberAnimation { duration: 150 } }
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(7)
                                                    Text {
                                                        text: model.dispatcher; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isDispOpen ? "▴" : "▾"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: model.execEditable
                                                    onClicked: { kbRowRect.isDispOpen = !kbRowRect.isDispOpen; kbRowRect.isTypeOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isDispOpen ? Math.min(root.s(140), root.dispatchers.length * root.s(26)) : 0
                                                radius: root.s(6); color: root.surface0; clip: true
                                                border.color: root.surface1; border.width: kbRowRect.isDispOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.dispatchers; interactive: true
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: dispItemMa.containsMouse ? Qt.alpha(root.peach, 0.12) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(8); text: modelData
                                                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                            color: model.dispatcher === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: dispItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "dispatcher", modelData); kbRowRect.isDispOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Command input
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(6)
                                        color: cmdInput.activeFocus ? Qt.alpha(root.peach, 0.08) : root.surface0
                                        border.color: cmdInput.activeFocus ? root.peach : root.surface2
                                        border.width: 1; z: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        TextInput {
                                            id: cmdInput
                                            anchors.fill: parent; anchors.margins: root.s(9)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: model.command
                                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                            color: root.text; clip: true; selectByMouse: true
                                            readOnly: !model.execEditable
                                            onTextEdited: dynamicKeybindsModel.setProperty(outerIndex, "command", text)
                                            Text {
                                                text: "Command arguments..."
                                                color: root.subtext0
                                                visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; Layout.alignment: Qt.AlignRight; spacing: root.s(8); z: 0
                                        // Delete button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            color: delMa.containsMouse ? root.red : root.surface1
                                            border.color: delMa.containsMouse ? root.red : Qt.alpha(root.red, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆴"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: "Delete"; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); font.weight: Font.Medium
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea {
                                                id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                                onClicked: {
                                                    root.forceActiveFocus();
                                                    dynamicKeybindsModel.remove(outerIndex);
                                                    root.saveAllKeybinds();
                                                }
                                            }
                                        }
                                        // Save button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            color: rowSaveMa.containsMouse ? root.green : root.surface1
                                            border.color: rowSaveMa.containsMouse ? root.green : Qt.alpha(root.green, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: "Save"; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); font.weight: Font.Medium
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea {
                                                id: rowSaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let validationResult = root.validateKeybind(outerIndex, model.mods, model.key, model.dispatcher, model.command);
                                                    if (validationResult !== "VALID") {
                                                        root.errorMessage = validationResult;
                                                        return;
                                                    }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "isEditing", false);
                                                    root.forceActiveFocus();
                                                    root.saveAllKeybinds();
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
        }
    }
}
