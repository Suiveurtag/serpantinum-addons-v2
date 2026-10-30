import QtQuick
import QtQuick.Layouts
import Quickshell
import QtTest

ShellRoot {
    id: test
    property int step: 0
    property string wentTo: ""
    property var searchItems: ({})
    TestCase { id: input; when: false }
    function expect(condition, reason) { if (!condition) { console.error("CLAWD_FAIL", step, reason); Qt.exit(1); } }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function click(name) { const k = find(settings, name); expect(!!k, "missing " + name); if (k.enabled) k.activated(); }
    function realClick(name) { const k = find(settings, name); expect(!!k, "missing " + name); input.mouseMove(k, k.width / 2, k.height / 2); input.mouseClick(k, k.width / 2, k.height / 2); input.mouseMove(guide, 2, guide.height - 2); }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 820; implicitHeight: 760; color: ThemeBackend.base
        Item {
            id: guide
            anchors.fill: parent
            property int currentTab: 0
            property int currentSubTab: 0
            property bool isGuidePopup: true
            function s(v) { return v; }
            function gotoTab(tab) { test.wentTo = tab; }
            function registerSearchItem(info) { test.searchItems[info.id] = info; }
            function unregisterSearchItem(key) {}
            Flickable {
                id: viewport
                anchors.fill: parent; anchors.margins: 24; clip: true
                contentWidth: width; contentHeight: column.implicitHeight
                ColumnLayout {
                    id: column
                    property int tabIndex: 0
                    property int subTabIndex: 0
                    width: viewport.width
                    ClawdSettings { id: settings; rootObj: guide; viewport: viewport }
                }
            }
        }
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            const card = test.find(settings, "clawdCard");
            const get = (k, f) => Config.getSetting(k, f);
            switch (test.step++) {
            case 0:
                test.expect(!!card && !!Clawd.manifest && card.height > 0, "card and manifest");
                test.expect(!!test.searchItems.addons_clawd, "search registration");
                test.expect(card.animate, "animates while visible");
                test.realClick("clawdSummon");
                test.expect(get("addonsV2ClawdSummon", 0) === 0, "summon disabled while off");
                test.realClick("clawdEnable");
                break;
            case 1:
                test.expect(get("addonsV2Clawd", false) === true && Clawd.enabled, "enable writes addonsV2Clawd");
                test.click("clawdScaleUp"); test.expect(get("addonsV2ClawdScale", 0) === 5, "scale up");
                for (let i = 0; i < 6; i++) test.click("clawdScaleUp");
                test.expect(get("addonsV2ClawdScale", 0) === 8 && Clawd.scale === 8, "scale clamps at 8");
                for (let i = 0; i < 9; i++) test.click("clawdScaleDown");
                test.expect(get("addonsV2ClawdScale", 0) === 2, "scale clamps at 2");
                card.setScale(3.6); test.expect(get("addonsV2ClawdScale", 0) === 4, "integer scale only");
                test.click("clawdSpeed_active"); test.expect(get("addonsV2ClawdSpeed", "") === "active" && Clawd.speed === "active", "speed");
                test.click("clawdSleepUp"); test.expect(get("addonsV2ClawdSleep", 0) === 10, "sleep up");
                test.click("clawdSleepDown"); test.click("clawdSleepDown"); test.expect(get("addonsV2ClawdSleep", 0) === 3, "sleep down");
                for (let i = 0; i < 12; i++) test.click("clawdSleepUp");
                test.expect(get("addonsV2ClawdSleep", 0) === 60, "sleep clamps at 60");
                test.realClick("clawdSummon"); test.click("clawdSummon");
                test.expect(get("addonsV2ClawdSummon", 0) === 2, "summon increments");
                test.click("clawdShortcut"); test.expect(test.wentTo === "addon_keybinds", "shortcut opens keybinds");
                break;
            case 2: {
                const k = test.find(settings, "clawdEnable");
                k.forceActiveFocus(); input.keyClick(Qt.Key_Space);
                test.expect(!Clawd.enabled, "keyboard toggle");
                input.keyClick(Qt.Key_Space);
                test.expect(Clawd.enabled, "keyboard toggle back");
                const hook = test.find(settings, "clawdHook_claude");
                test.expect(hook.enabled && hook.label === "[ ] claude", "hooks status loaded: " + hook.label);
                test.click("clawdHook_claude");
                test.expect(!hook.enabled && hook.label === "[…] claude", "connecting");
                Config.setSetting("general.performance", true);
                break;
            }
            case 3: test.expect(!card.animate, "performance mode stills the card"); Config.setSetting("general.performance", false); break;
            case 4:
                test.expect(card.animate, "animates again");
                test.expect(test.find(settings, "clawdHook_claude").label === "[x] claude" && card.hookNote === "start a new claude session", "claude connected");
                test.expect(test.find(settings, "clawdHook_codex").label === "[ ] codex", "codex untouched"); viewport.contentY = 2000; settings.visible = false; break;
            case 5: test.expect(!card.animate, "hidden card stills"); console.log("CLAWD_PASS"); Qt.quit(); break;
            }
        }
    }
}
