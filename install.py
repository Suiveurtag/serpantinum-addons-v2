#!/usr/bin/env python3
"""Install only v2 addons, preserving upstream files and unrelated v1 work."""
import argparse
import os
import shlex
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
QS = Path(os.environ.get('SERPANTINUM_HOME', DATA / 'serpantinum')) / 'src/quickshell'
DEPLOY = DATA / 'serpantinum-addons-v2'
MARK = 'serpantinum-addons-v2'


def patch_guide(text):
    import re
    # Migrate our first revision while leaving every upstream tab intact.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs[\s,]*(?=    \])', '', text, flags=re.S)
    text = re.sub(r'\n                                // BEGIN serpantinum-addons-v2 sidebar.*?                                // END serpantinum-addons-v2 sidebar\n', '', text, flags=re.S)
    text = text.replace('tabAbout, tabAddonAddons, tabAddonMonitors, tabAddonKeybinds', 'tabAbout')
    anchor = '        { id: "About", key: "about", name: "About", icon: "󰋽", file: "AboutTab.qml", iconOffsetX: 0 }'
    text = text.replace(anchor + ',\n', anchor + '\n')
    if text.count(anchor) != 1: raise ValueError('Guide tabs anchor changed')
    block = '''        // BEGIN serpantinum-addons-v2 tabs
        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "AddonsTab.qml", iconOffsetX: 0 },
        { id: "Monitors", key: "addon_monitors", name: "Monitors", icon: "󰍹", file: "AddonMonitorsTab.qml", iconOffsetX: 0 },
        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },
        // END serpantinum-addons-v2 tabs
'''
    # End marker sits before About now; remove it separately on later installs.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs\n', '', text, flags=re.S)
    text = text.replace(anchor, block + anchor, 1)
    start = text.index('                                Rectangle {\n                                    id: tabAbout')
    depth = 0
    for stop in range(start, len(text)):
        if text[stop] == '{': depth += 1
        elif text[stop] == '}':
            depth -= 1
            if depth == 0: break
    original = text[start:stop + 1]
    # About's prior index can be 11 (first install) or 14 (reinstall).
    original = original.replace('(14)', '(11)').replace('[14]', '[11]').replace('=== 14', '=== 11').replace('= 14;', '= 11;')
    blocks = []
    for index, name, icon in [(11, 'Addons', '󰐱'), (12, 'Monitors', '󰍹'), (13, 'Keybinds', '󰌌')]:
        entry = original.replace('tabAbout', 'tabAddon' + name).replace('(11)', '(' + str(index) + ')').replace('[11]', '[' + str(index) + ']').replace('=== 11', '=== ' + str(index)).replace('= 11;', '= ' + str(index) + ';').replace('I18n.t("guide.tabs.about", "About")', '"' + name + '"').replace('"󰋽"', '"' + icon + '"')
        blocks.append(entry)
    about = original.replace('(11)', '(14)').replace('[11]', '[14]').replace('=== 11', '=== 14').replace('= 11;', '= 14;')
    sidebar = '\n                                // BEGIN serpantinum-addons-v2 sidebar\n' + '\n'.join(blocks) + '\n                                // END serpantinum-addons-v2 sidebar\n'
    text = text[:start] + sidebar + about + text[stop + 1:]
    return text.replace('                                    tabAbout\n', '                                    tabAddonAddons, tabAddonMonitors, tabAddonKeybinds, tabAbout\n', 1)


def patch_main(text):
    if '// BEGIN serpantinum-addons-v2 drag area' in text: return text
    start = text.index('        DragHandler {\n            id: windowDragHandler')
    depth = 0
    for stop in range(start, len(text)):
        if text[stop] == '{': depth += 1
        elif text[stop] == '}':
            depth -= 1
            if depth == 0: break
    handler = text[start:stop + 1].replace('            acceptedButtons: Qt.LeftButton', '            acceptedButtons: Qt.LeftButton\n            grabPermissions: PointerHandler.CanTakeOverFromHandlersOfSameType | PointerHandler.ApprovesTakeOverByAnything')
    wrapper = '''        // BEGIN serpantinum-addons-v2 drag area
        Item {
            width: masterWindow.currentActive === "guide" ? Scaler.s(260) : parent.width
            height: masterWindow.currentActive === "guide" ? Scaler.s(60) : parent.height
''' + handler + '\n        }\n        // END serpantinum-addons-v2 drag area'
    return text[:start] + wrapper + text[stop+1:]


def patch_network(text):
    if '// BEGIN ' + MARK + ' dns' in text: return text
    anchor = '    id: window\n'
    if text.count(anchor) != 1: raise ValueError('Network root anchor changed')
    block = '''
    // BEGIN serpantinum-addons-v2 dns
    DnsControl {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: window.s(18); anchors.topMargin: window.s(16)
        width: window.s(160); height: window.s(32); z: 100
        visible: window.activeMode === "wifi" || window.activeMode === "eth"
        pollEnabled: window.visible && visible
    }
    // END serpantinum-addons-v2 dns
'''
    return text.replace(anchor, anchor + block, 1)


def patch_theme(text):
    import re
    text = re.sub(r'                        // BEGIN serpantinum-addons-v2 theme.*?                        // END serpantinum-addons-v2 theme\n', '', text, flags=re.S)
    if '// BEGIN serpantinum-addons-v2 theme cards' in text:
        return text.replace('themeTabRoot.systemPresets = sys;', 'themeTabRoot.systemPresets = sys.slice();')
    anchor = '                        themeTabRoot.userPresets = usr;'
    if text.count(anchor) != 1: raise ValueError('Theme preset list anchor changed')
    text = text.replace(anchor, '''                        // BEGIN serpantinum-addons-v2 theme cards
                        let matugenIndex = sys.findIndex(p => p.isMatugen === true);
                        if (matugenIndex !== -1) {
                            sys.splice(matugenIndex + 1, 0,
                                {name: "Vibrant", isMatugen: true, addonColorMode: "vibrant"},
                                {name: "Vivid", isMatugen: true, addonColorMode: "vivid"});
                            themeTabRoot.systemPresets = sys.slice();
                        }
                        // END serpantinum-addons-v2 theme cards
''' + anchor, 1)
    anchor = '        let isMatugen = modelData.isMatugen === true;'
    block = '''        if (modelData.isMatugen === true) {
            Config.setSetting("addonsV2ColorMode", modelData.addonColorMode || "matugen");
            Matugen._hasGeneratedSuccessfully = false;
        }
'''
    text = text.replace(anchor, block + anchor, 1)
    # Give the addon cards the exact existing wallpaper tile, selection, dots and motion.
    return text


def patch_matugen(text):
    if '// BEGIN ' + MARK + ' generation' in text: return text
    anchor = '''        matugenProcess.command = [
            "matugen", "image", cleanPath,
            "-c", root.configPath,
            "-m", selectedMode,
            "-t", selectedType,
            "--source-color-index", "0"
        ];'''
    if text.count(anchor) != 1: raise ValueError('Matugen command anchor changed')
    replacement = '''        // BEGIN serpantinum-addons-v2 generation
        matugenProcess.command = [
            "python3", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/colors.py",
            cleanPath, root.configPath, root.configPathStatic, selectedMode, selectedType,
            Config.getSetting("addonsV2ColorMode", "matugen"), Caching.stateDir
        ];
        // END serpantinum-addons-v2 generation'''
    return text.replace(anchor, replacement, 1)


def patch_shell(text):
    anchor = '    ScreenshotOverlay {}\n'
    addition = '    // BEGIN serpantinum-addons-v2 color picker\n    AddonColorPicker {}\n    // END serpantinum-addons-v2 color picker\n'
    if addition in text: return text
    if text.count(anchor) != 1: raise ValueError('Shell screenshot anchor changed')
    return text.replace(anchor, anchor + addition, 1)


def patch_floating(text):
    marker = '                                // BEGIN serpantinum-addons-v2 picker action\n'
    if marker in text:
        return text.replace('Quickshell.execDetached(["quickshell", "ipc", "call", "addonColorPicker", "toggle"]);', 'Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonColorPicker", "toggle"]);')
    anchor = '                                Rectangle {\n                                    id: pinButton'
    if text.count(anchor) != 1: raise ValueError('Quickactions pin anchor changed')
    action = '''                                // BEGIN serpantinum-addons-v2 picker action
                                Rectangle {
                                    id: pickerButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    radius: width / 2
                                    x: (parent.width - width) / 2
                                    y: floatingWidget.activeEdge === "left"
                                        ? pinButton.y + pinButton.height + floatingWidget.s(6)
                                        : pinButton.y - height - floatingWidget.s(6)
                                    color: pickerMouse.containsMouse ? Qt.alpha(ThemeBackend.mauve, 0.25) : "transparent"
                                    border.width: floatingWidget.s(1)
                                    border.color: pickerMouse.containsMouse ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.text, 0.22)
                                    scale: pickerMouse.pressed ? 0.88 : (pickerMouse.containsMouse ? 1.12 : 1)
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰈊"
                                        color: pickerMouse.containsMouse ? ThemeBackend.mauve : ThemeBackend.text
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: floatingWidget.s(12)
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    MouseArea {
                                        id: pickerMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()
                                        onClicked: {
                                            floatingWidget.isExpanded = false;
                                            floatingWidget.isSidebarVisible = false;
                                            Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonColorPicker", "toggle"]);
                                        }
                                    }
                                }
                                // END serpantinum-addons-v2 picker action

'''
    text = text.replace(anchor, action + anchor, 1)
    return text.replace('property real controlAreaHeight: buttonSize * 2 + s(10)', 'property real controlAreaHeight: buttonSize * 3 + s(16)', 1)


def patch_keybinds(text):
    marker = '-- BEGIN serpantinum-addons-v2 color picker'
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonColorPicker toggle'
    if marker in text:
        return text.replace('quickshell ipc call addonColorPicker toggle', command)
    if '"SUPER + SHIFT + C"' in text: raise ValueError('Color picker shortcut already in use')
    anchor = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })'
    if text.count(anchor) != 1: raise ValueError('Screenshot shortcut anchor changed')
    addition = '''\n-- BEGIN serpantinum-addons-v2 color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("''' + command + '''"), { locked = true })
-- END serpantinum-addons-v2 color picker'''
    return text.replace(anchor, anchor + addition, 1)


def install():
    # Calculate all transformations first. Never partly apply an unknown upstream revision.
    patches = {QS/'Main.qml': patch_main, QS/'Shell.qml': patch_shell, QS/'quickactions/Floating.qml': patch_floating, QS/'guide/GuidePopup.qml': patch_guide, QS/'guide/theme/ThemeTab.qml': patch_theme, QS/'network/NetworkPopup.qml': patch_network, QS/'singletons/theme/Matugen.qml': patch_matugen}
    pending = {path: transform(path.read_text()) for path, transform in patches.items()}
    keybind_path = HOME/'.config/hypr/config/keybinds.lua'
    pending[keybind_path] = patch_keybinds(keybind_path.read_text())
    payloads = {'AddonColorPicker.qml': 'AddonColorPicker.qml', 'AddonsTab.qml': 'guide/AddonsTab.qml', 'AddonMonitorsTab.qml': 'guide/AddonMonitorsTab.qml', 'AddonKeybindsTab.qml': 'guide/AddonKeybindsTab.qml', 'DnsControl.qml': 'network/DnsControl.qml', 'LegacyCalendar.qml': 'calendar/LegacyCalendar.qml', 'CalendarPopup.qml': 'calendar/CalendarPopup.qml'}
    for source, target in payloads.items(): pending[QS/target] = (SOURCE/'payload'/source).read_text()
    # Both tabs use the same DNS component; identical payload with appropriate relative imports.
    pending[QS/'guide/DnsControl.qml'] = (SOURCE/'payload/DnsControl.qml').read_text()
    qmldir = QS/'qmldir'
    qmldir_text = qmldir.read_text()
    pending[qmldir] = qmldir_text if 'AddonColorPicker 1.0 AddonColorPicker.qml' in qmldir_text else qmldir_text + '\nAddonColorPicker 1.0 AddonColorPicker.qml\n'
    for folder in ('guide', 'network'):
        directory = QS/folder/'qmldir'
        original = directory.read_text() if directory.exists() else ''
        pending[directory] = original if 'DnsControl 1.0 DnsControl.qml' in original else original + '\nDnsControl 1.0 DnsControl.qml\n'
    calendar = QS/'calendar/CalendarPopup.qml'
    if '// BEGIN serpantinum-addons-v2 calendar wrapper' not in calendar.read_text():
        pending[QS/'calendar/NativeCalendar.qml'] = calendar.read_text()
    elif not (QS/'calendar/NativeCalendar.qml').is_file():
        raise ValueError('Native calendar backup is missing')
    backup = DEPLOY/'backups'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    changed = 0
    for path, text in pending.items():
        if path.is_file() and path.read_text() == text: continue
        backup.mkdir(parents=True, exist_ok=True)
        if path.exists():
            relative = Path('hypr/keybinds.lua') if path == keybind_path else path.relative_to(QS)
            saved = backup/relative; saved.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, saved)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(dir=path.parent, prefix='.'+path.name)
        with os.fdopen(fd, 'w') as f: f.write(text)
        os.replace(name, path); changed += 1
    shutil.copytree(SOURCE/'scripts', DEPLOY/'scripts', dirs_exist_ok=True)
    print(f'v2 installed: {changed} shell files changed; backups: {backup}')


if __name__ == '__main__':
    install()
