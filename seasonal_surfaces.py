"""Seasonal surface hooks; compose with the core hooks rather than duplicate UI."""
import re
from seasonal import insert, MARK


def shadows(text, anchor, name, active, parent=''):
    return insert(text, anchor, (name, f'''{' ' * 8}Loader {{
            enabled: false
            {('parent: ' + parent + ';') if parent else ''}
            anchors.fill: parent; z: {'1' if parent else '0'}
            active: Halloween.animationEnabled && ({active})
            sourceComponent: DistantBats {{}}
        }}
'''))


def calendar(text):
    return shadows(text, '                id: centralHub\n', 'calendar shadows', 'window.visible', 'centralHub.parent')


def guide(text):
    return insert(text, '                id: contentArea\n', ('settings shadows', '''                Loader {
                    id: seasonalSettingsAtmosphere
                    anchors.fill: parent
                    z: 4; enabled: false
                    active: Halloween.activeSeason && root.visible && width > 0 && height > 0
                    sourceComponent: NightPanel {
                        scene: "guide"
                        cornerRadius: root.standalone ? 0 : ThemeBackend.borderRadius
                        DistantBats { anchors.fill: parent }
                    }
                }
'''))


def music(text):
    return insert(text, '                id: bgEffectsLayer\n', ('music shadows', '''                Loader {
                    anchors.fill: parent; z: 2; enabled: false
                    active: Halloween.animationEnabled && root.active
                    sourceComponent: DistantBats {}
                }
'''))


def network(text):
    legacy_anchor = '                id: orbitContainer\n'
    if legacy_anchor in text:
        return shadows(text, legacy_anchor, 'network shadows', 'window.visible')
    anchor = '            NetworkCoreLayer {\n'
    if anchor not in text:
        anchor = '            NetworkControls {\n'
    return insert(text, anchor, ('network shadows', '''            Loader {
                enabled: false
                anchors.fill: parent; z: 0
                active: Halloween.animationEnabled && window.visible
                sourceComponent: DistantBats {}
            }
'''))


def network_core(text):
    return insert(text, '                id: centralCore\n', ('network hold', '''                property Item seasonalCharge: HoldEnergy {
                    parent: centralCore; anchors.fill: parent; z: 6
                    held: coreMa.pressed && window.currentConn && !showPassword
                    charge: centralCore.disconnectFill
                }
'''))


def fill(text):
    return insert(text, '    id: root\n', ('hold discharge', '''    property Item seasonalHold: HoldEnergy {
        parent: root; anchors.fill: parent; z: 9
        held: btnMa.pressed && root.enabled
        charge: root.fillLevel
    }
'''))


def system(text):
    return insert(text, '        id: sidebarPanel\n', ('system light', '''        Loader {
            anchors.fill: parent; z: 2; enabled: false
            active: Halloween.activeSeason && root.visible
            sourceComponent: LockVeil { authenticating: root.isDraggingVol || root.isDraggingBri }
        }
'''))


def system_power_actions(text):
    return insert(text, '            id: actionCapsule\n', ('power charge', '''            property Item seasonalCharge: HoldEnergy {
                parent: actionCapsule; anchors.fill: parent; z: 7
                held: actionMa.pressed && !actionCapsule.isDisabled
                charge: actionCapsule.fillLevel
                            }
'''))


def user_face(text):
    return insert(text, '                        id: actionCapsule\n', ('power charge', '''                        property Item seasonalCharge: HoldEnergy {
                            parent: actionCapsule; anchors.fill: parent; z: 7
                            held: actionMa.pressed
                            charge: actionCapsule.fillLevel
                        }
'''))


def launcher(text):
    # A window-sized layer lets bats leave the growing frontier without being clipped.
    return insert(text, '    id: launcherWindow\n', ('launcher storm', '''    Loader {
        id: seasonalStorm
        enabled: false; anchors.fill: parent; z: 200
        active: Halloween.animationEnabled && launcherWindow.isVisible
        sourceComponent: LauncherStorm {
            resultCount: appModel.count; query: searchInput.text
            edge: launcherWindow.attachEdge
            panelRect: Qt.rect(container.x, container.y, container.width, container.height)
        }
    }
'''))


def osd(text):
    return insert(text, '    id: osdWindow\n', ('osd souls', '''    Loader {
        id: seasonalSouls; anchors.fill: parent; z: 200; enabled: false
        active: Halloween.animationEnabled && osdWindow.isVisible
        sourceComponent: OsdSouls {
            originRect: Qt.rect(osdContainer.x, osdContainer.y, osdContainer.width, osdContainer.height)
            vertical: osdWindow.isVerticalLayout
        }
        onLoaded: Qt.callLater(function() { if (seasonalSouls.item) seasonalSouls.item.release(); })
    }
    Connections {
        target: osdWindow
        function onCurrentValChanged() { if (osdWindow.isVisible && seasonalSouls.item) seasonalSouls.item.release(); }
        function onIsVisibleChanged() { if (osdWindow.isVisible && seasonalSouls.item) seasonalSouls.item.release(); }
    }
'''))


def lock(text):
    anchor = 'id: passwordInput\n'
    if text.count(anchor) == 1:
        index = text.index(anchor)
        indent = text[text.rfind('\n', 0, index) + 1:index]
        insertion = anchor
        block = '''property Item seasonalFocusLight: ControlEffects {
    parent: passwordInput; anchors.fill: parent; z: 3
    engaged: passwordInput.activeFocus && rootLock.locked
    cornerRadius: ThemeBackend.borderRadius
    charge: lockUI.authenticating ? 1 : 0
}
'''
        rendered = ''.join(indent + line for line in block.splitlines(keepends=True))
        text = text.replace(rendered, '')
        text = text.replace(insertion, insertion + rendered, 1)
    elif 'readonly property var passwordInput:' in text and text.count('id: dashboard\n') == 1:
        # Current upstream moved the password editor into LockLayoutView and
        # exposes it through dashboard.passwordInput instead of declaring it
        # inline in LockDashboard.qml.
        anchor = '    id: dashboard\n'
        block = '''    property Item seasonalFocusLight: ControlEffects {
        parent: dashboard.passwordInput
        anchors.fill: parent
        z: 3
        engaged: dashboard.passwordInput && dashboard.passwordInput.activeFocus && dashboard.visible
        cornerRadius: ThemeBackend.borderRadius
        charge: dashboard.screenRoot.lockUI.authenticating ? 1 : 0
    }
'''
        text = text.replace(block, '', 1)
        text = text.replace(anchor, anchor + block, 1)
    else:
        raise ValueError('Lock password input anchor changed')
    return insert(text, '        id: mainDashboardShell\n', ('lock veil', '''        Loader {
                                    anchors.fill: parent; z: 5; enabled: false
                                    active: Halloween.activeSeason && rootLock.locked && mainDashboardShell.visible && !screenRoot.isUnlocking
                                    sourceComponent: LockVeil { authenticating: lockUI.authenticating; failed: lockUI.failed }
                                }
'''))


def volume(text):
    text = insert(text, '                            id: centralCore\n', ('sound aura', '''                            Loader {
                                anchors.fill: parent; z: 2; enabled: false
                                active: Halloween.activeSeason && window.visible
                                sourceComponent: FogLayer {
                                    mode: 6; intensity: window.activeMute ? 0.15 : 0.46
                                    energy: Math.min(1,window.activeVol/100)
                                    cornerRadius: ThemeBackend.borderRadius
                                    warmth: window.activeTab === "inputs" ? 0.2 : 0.75
                                    Behavior on energy { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                }
                            }
'''))
    return insert(text, '                            id: delegateRoot\n', ('sound mist', '''                            property Item seasonalMist: EdgeMist {
                                parent: delegateRoot; anchors.fill: parent; z: 1
                                engaged: delegateRoot.isHovered
                                direction: window.activeTab === "inputs" ? -1 : 1
                                cornerRadius: delegateRoot.radius
                            }
'''))


def audio_boost_view(text):
    if 'audioBoostToggle' in text:
        return text
    anchor = '        SettingsRow {\n            Layout.fillWidth: true\n            rootObj: root\n            opacity: root.audioIntroDynamics'
    block = '''        SettingsRow {
            Layout.fillWidth: true
            rootObj: root
            title: "Boost +3 dB"
            titlePixelSize: 12
            titleBold: true
            verticalPadding: root.s(9)
            searchable: false

            Toggle {
                id: audioBoostToggle
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.preferredWidth: root.s(44)
                Layout.preferredHeight: root.s(24)
                horizontalPadding: 0
                checked: Number(root.eqData.boost || 0) > 0
                accentColor: ThemeBackend.mauve || "#cba6f7"
                baseColor: Qt.alpha(ThemeBackend.surface2 || "#585b70", ThemeBackend.elementOpacity)
                handleColor: ThemeBackend.base || "#1e1e2e"
                handleOffColor: ThemeBackend.text || "#cdd6f4"
                onToggled: checked => root.setBoost(checked ? 3 : 0)

                Connections {
                    target: root
                    function onEqDataChanged() {
                        audioBoostToggle.checked = Number(root.eqData.boost || 0) > 0;
                    }
                }
            }
        }

'''
    return addon_insert(text, anchor, 'audio boost toggle', block)


def music_audio_boost(text):
    text, defaults = re.subn(r'("mono": false, "swap": false, "dynamics": "off")(?!, "boost": 0)', r'\1, "boost": 0', text)
    if defaults not in (0, 2):
        raise ValueError('Music audio state defaults changed')
    if '        temp.boost = 0;' not in text:
        text = text.replace('        temp.dynamics = "off";\n', '        temp.dynamics = "off";\n        temp.boost = 0;\n', 1)
    text = addon_insert(text, '    function setDynamics(value) {\n', 'audio boost state', '''    function setBoost(value) {
        var boost = Number(value) > 0 ? 3 : 0;
        var temp = Object.assign({}, root.eqData);
        temp.boost = boost;
        root.eqData = temp;
        root.savedEqData = Object.assign({}, temp);
        root.lastEqUpdate = Date.now();
        root.execCmd(Caching.qsDir + `/media/equalizer.sh set_boost ${boost}`);
    }
''')
    if 'function setBoost(value)' in text:
        return text
    text = re.sub(r'\n[ \t]*// BEGIN serpantinum-addons-v2 audio boost control\n.*?\n[ \t]*// END serpantinum-addons-v2 audio boost control\n', '', text, flags=re.S)
    anchor = '                        ClickButton {\n                            id: audioTestBtn'
    if anchor not in text:
        return text
    return addon_insert(text, anchor, 'audio boost toggle', '''                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: root.s(6)
                            visible: bottomSectionSwitch.currentIndex === 1

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Boost +3 dB")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(10.5)
                                font.weight: Font.Medium
                                color: ThemeBackend.subtext0 || "#a6adc8"
                            }

                            Toggle {
                                id: audioBoostToggle
                                width: root.s(44)
                                height: root.s(24)
                                horizontalPadding: 0
                                cornerRadius: root.s(12)
                                checked: Number(root.eqData.boost || 0) > 0
                                accentColor: ThemeBackend.mauve || "#cba6f7"
                                baseColor: ThemeBackend.surface0 || "#313244"
                                handleColor: ThemeBackend.base || "#1e1e2e"
                                handleOffColor: ThemeBackend.text || "#cdd6f4"
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: qsTr("Audio boost: up to +3 dB, with peak limiting")
                                onToggled: checked => root.setBoost(checked ? 3 : 0)

                                Connections {
                                    target: root
                                    function onEqDataChanged() {
                                        audioBoostToggle.checked = Number(root.eqData.boost || 0) > 0;
                                    }
                                }
                            }
                        }
''')


def addon_insert(text, anchor, name, body):
    marker = f'serpantinum-addons-v2 {name}'
    text = re.sub(r'\n[ \t]*// BEGIN ' + re.escape(marker) + r'\n.*?\n[ \t]*// END ' + re.escape(marker) + r'\n', '', text, flags=re.S)
    if text.count(anchor) != 1:
        raise ValueError(f'Audio boost anchor changed: {name}')
    indent = len(anchor) - len(anchor.lstrip())
    body = body.strip('\n')
    padding = ' ' * indent
    return text.replace(anchor, f'\n{padding}// BEGIN {marker}\n' + body + f'\n{padding}// END {marker}\n' + anchor, 1)


def audio_equalizer(text):
    marker = '# BEGIN serpantinum-addons-v2 audio boost'
    if marker in text:
        return text
    changes = [
        ('"dynamics": "off"}', '"dynamics": "off", "boost": 0}'),
        ('and has("dynamics")\'', 'and has("dynamics") and has("boost")\''),
        ('.dynamics //= "off"', '.dynamics //= "off" | .boost //= 0'),
        ("    dynamics = str(data.get('dynamics', 'off'))", "    boost = max(0.0, min(3.0, float(data.get('boost', 0))))\n    dynamics = str(data.get('dynamics', 'off'))"),
        ("'input-gain': 0.0,\n                'output-gain': 0.0,", "'input-gain': boost,\n                'output-gain': 0.0,"),
        ('    dynamics=$(jq -r \'.dynamics // "off"\' "$STATE_FILE")\n', '    dynamics=$(jq -r \'.dynamics // "off"\' "$STATE_FILE")\n    boost=$(jq -r \'.boost // 0\' "$STATE_FILE")\n'),
        ('        --arg dynamics "$dynamics" \\\n', '        --arg dynamics "$dynamics" \\\n        --argjson boost "$boost" \\\n'),
        ('            "dynamics": $dynamics\n', '            "dynamics": $dynamics,\n            "boost": $boost\n'),
        ("'.balance = 0 | .mono = false | .swap = false | .dynamics = \"off\"'", "'.balance = 0 | .mono = false | .swap = false | .dynamics = \"off\" | .boost = 0'"),
    ]
    for old, new in changes:
        if old not in text:
            raise ValueError(f'Audio boost backend anchor changed: {old[:40]}')
        text = text.replace(old, new, 1)
    command_anchor = '    "set_dynamics")\n'
    if command_anchor not in text:
        raise ValueError('Audio boost command anchor changed')
    command = ('    "set_boost")\n'
               '        [[ "$arg1" =~ ^(0|3)(\\.0)?$ ]] || exit 1\n'
               '        jq -c --argjson val "$arg1" \' .boost = $val \' "$STATE_FILE" > "$STATE_FILE.tmp.$$" || exit 1\n'
               '        mv -f "$STATE_FILE.tmp.$$" "$STATE_FILE"\n'
               '        apply_eq\n'
               '        ;;\n\n')
    text = text.replace(command_anchor, command + command_anchor, 1)
    limiter_anchor = "    if dynamics != 'off':\n        night = dynamics == 'night'\n"
    limiter = ("    if boost > 0 and dynamics == 'off':\n"
               "        output['plugins_order'].append('limiter')\n"
               "        output['limiter'] = {'bypass': False, 'threshold': -1.0, 'lookahead': 5.0, 'attack': 5.0, 'release': 50.0, 'output-gain': 0.0, 'input-gain': 0.0}\n\n")
    if limiter_anchor not in text:
        raise ValueError('Audio boost limiter anchor changed')
    text = text.replace(limiter_anchor, limiter + limiter_anchor, 1)
    return text.replace('#!/usr/bin/env bash\n', '#!/usr/bin/env bash\n' + marker + '\n# Adds a capped 3 dB boost with peak limiting.\n# END serpantinum-addons-v2 audio boost\n', 1)


def theme(text):
    if 'property var systemPresets: []' not in text:
        return text
    text = insert(text, '    property var systemPresets: []\n', ('theme data', '''    readonly property var seasonalPresets: [{
        name: "Halloween Night", category: "seasonal", colors: Halloween.colors,
        previewArtwork: Halloween.artwork
    }]
    readonly property var filteredSeasonalPresets: seasonalPresets.filter(p => !themeSearchText.trim() || p.name.toLowerCase().indexOf(themeSearchText.trim().toLowerCase()) !== -1)
'''))
    if 'id: themesGrid' not in text:
        return text
    anchor = '                    GridLayout {\n                        id: themesGrid'
    marker = f'{MARK} theme category'
    text = re.sub(r'\n    // BEGIN ' + re.escape(marker) + r'\n.*?    // END ' + re.escape(marker) + r'\n', '', text, flags=re.S)
    if text.count(anchor) != 1: raise ValueError('Theme grid anchor changed')
    body = '''                    Text {
                        visible: themeTabRoot.filteredSeasonalPresets.length > 0
                        Layout.leftMargin: rootObj.s(14); Layout.topMargin: rootObj.s(14)
                        text: "Seasonal · Halloween"
                        font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext1
                    }
                    GridLayout {
                        visible: themeTabRoot.filteredSeasonalPresets.length > 0
                        Layout.fillWidth: true
                        Layout.maximumWidth: themeTabRoot.tileWidth
                        Layout.leftMargin: rootObj.s(12); Layout.rightMargin: rootObj.s(12)
                        Layout.topMargin: rootObj.s(10); Layout.bottomMargin: rootObj.s(8)
                        columns: 3
                        Repeater { model: themeTabRoot.filteredSeasonalPresets; delegate: presetDelegateComp }
                    }
'''
    text = text.replace(anchor, f'\n    // BEGIN {marker}\n' + body + f'    // END {marker}\n' + anchor, 1)
    text = text.replace('active: modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== ""',
                        'active: !!modelData.previewArtwork || (modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== "")')
    original = 'themeTabRoot.isWallpaperVideo ? ("file://" + Caching.getCacheDir("wallpaper") + "/current_wallpaper.png?rev=" + themeTabRoot.wallpaperRevision) : ("file://" + themeTabRoot.currentWallpaperPath)'
    if 'source: modelData.previewArtwork ?' not in text:
        text = text.replace('source: ' + original, 'source: modelData.previewArtwork ? modelData.previewArtwork : (' + original + ')', 1)
    text = text.replace('Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(modelData.previewArtwork ? 124 : 44)',
                        'Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(44)')
    text = insert(text, '                            id: matugenWall\n', ('theme artwork crop', '''                            verticalAlignment: modelData.previewArtwork ? Image.AlignTop : Image.AlignVCenter
'''))
    if 'if (typeof themesGrid.forceLayout' not in text:
        text = text.replace('themesGrid.forceLayout();', 'if (typeof themesGrid.forceLayout === "function") themesGrid.forceLayout();')
    return text


def extensions(qs):
    result = {qs/'guide/GuidePopup.qml':guide, qs/'calendar/NativeCalendar.qml':calendar,
            qs/'media/MusicPopup.qml':music, qs/'network/NetworkPopup.qml':network,
            qs/'media/equalizer.sh':audio_equalizer,
            qs/'network/NetworkCoreLayer.qml':network_core,
            qs/'reusables/buttons/FillButton.qml':fill, qs/'syspanel/SystemPanel.qml':system,
            qs/'syspanel/SystemPanelPowerActions.qml':system_power_actions,
            qs/'launcher/Launcher.qml':launcher, qs/'popouts/Osd.qml':osd,
            qs/'lock/LockDashboard.qml':lock, qs/'volume/VolumePopup.qml':volume,
            qs/'guide/theme/ThemeTabState.qml':theme, qs/'bar/BarModule.qml':bar_module,
            qs/'notifications/Notification.qml':notification, qs/'Shell.qml':shell,
            qs/'widgets/faces/user/UserFace.qml':user_face}
    result[qs/'media/MusicEqualizerState.qml'] = music_audio_boost
    result[qs/'media/MusicAudioView.qml'] = audio_boost_view
    result[qs/'media/MusicPopup.qml'] = music
    legacy_side_module = qs/'bar/BarSideModule.qml'
    if legacy_side_module.exists():
        result[legacy_side_module] = lambda text: bar_module(text, True)
    return result


def bar_module(text, vertical=False):
    return insert(text, '    id: root\n', ('bar charms', '''    Loader {
        enabled: false; anchors.fill: parent; z: 8
        active: Halloween.animationEnabled && root.effectiveVisible && root.visible
            && (!root.barWindow || root.barWindow.isRevealed)
        sourceComponent: BarCharms {
            moduleId: root.moduleId
            vertical: VERTICAL
            edge: root.barWindow ? root.barWindow.barPosition : "top"
            cornerRadius: root.radius
        }
    }
'''.replace('VERTICAL', 'true' if vertical else 'false')))


def notification(text):
    return insert(text, '            id: bgContainer\n', ('notification candles', '''            Loader {
                enabled: false; anchors.fill: parent
                active: Halloween.animationEnabled && typeRoot.visible
                sourceComponent: CandleVigil { cornerRadius: visualItem.radius; urgent: typeRoot.model && typeRoot.model.urgency === 2 }
            }
'''))


def shell(text):
    marker = f'{MARK} night intro'
    text = re.sub(r'\n    // BEGIN ' + re.escape(marker) + r'\n.*?    // END ' + re.escape(marker) + r'\n', '', text, flags=re.S)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Shell screenshot overlay anchor changed')
    block = '''    // BEGIN serpantinum-night-v2 night intro
    Loader {
        active: Halloween.animationEnabled && Halloween.introRunning
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: NightIntro { required property var modelData; screen: modelData }
        }
    }
    // END serpantinum-night-v2 night intro

'''
    return text.replace(anchor, block + anchor, 1)
