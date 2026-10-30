import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_changes import ROOT, installer

sys.path.insert(0, str(ROOT))
import capri  # noqa: E402
import clawd  # noqa: E402
import seasonal  # noqa: E402

PAYLOAD = ROOT/'payload/clawd'
SPRITES = PAYLOAD/'sprites'
ANIMATIONS = ['idle', 'blink', 'look_left', 'look_right', 'look_up', 'walk', 'turn', 'sit', 'sleep', 'drag', 'fall', 'land', 'spawn']
PALETTE = {(0, 0, 0, 0), (0xD9, 0x77, 0x57, 255), (0, 0, 0, 255), (0xF0, 0xEE, 0xE6, 255)}
COLORS = {'base': '#1e1e2e', 'mantle': '#181825', 'crust': '#11111b', 'text': '#cdd6f4', 'subtext0': '#a6adc8', 'subtext1': '#bac2de', 'surface0': '#313244',
          'surface1': '#45475a', 'surface2': '#585b70', 'overlay0': '#6c7086', 'overlay1': '#7f849c', 'overlay2': '#9399b2', 'blue': '#89b4fa', 'primary': '#89b4fa',
          'mauve': '#cba6f7', 'green': '#a6e3a1', 'red': '#f38ba8', 'pink': '#f5c2e7', 'yellow': '#f9e2af', 'peach': '#fab387'}


class ClawdPatchTests(unittest.TestCase):
    def test_shell_and_qmldir_hooks_are_idempotent_and_removable(self):
        shell = (installer.QS/'Shell.qml').read_text()
        season = seasonal.transformations(installer.QS)[installer.QS/'Shell.qml']
        orders = {'clawd last': lambda text: clawd.patch_shell(capri.patch_shell(season(installer.patch_shell(text)))),
                  'clawd first': lambda text: capri.patch_shell(season(installer.patch_shell(clawd.patch_shell(text))))}
        for name, stacked in orders.items():
            with self.subTest(order=name):
                once = stacked(shell)
                self.assertEqual(once, stacked(once))
                self.assertEqual(once.count('AddonClawd {}'), 1)
                self.assertEqual(once.count('AddonCapri {}'), 1)
                removed = clawd.remove(once)
                self.assertNotIn('Clawd', removed)
                self.assertIn('AddonCapri {}', removed)
                self.assertEqual(clawd.remove(removed), removed)
                self.assertIn('AddonClawd {}', capri.remove(once))
        qmldir = clawd.remove((installer.QS/'qmldir').read_text())  # the live shell may already have Clawd installed
        patched = clawd.patch_qmldir(capri.patch_qmldir(qmldir))
        self.assertEqual(patched, clawd.patch_qmldir(patched))
        self.assertIn('singleton Clawd 1.0 clawd/Clawd.qml', patched)
        self.assertNotIn('clawd/', clawd.remove(patched))
        self.assertEqual(clawd.remove(patched), capri.patch_qmldir(qmldir))
        self.assertIn('capri/', clawd.remove(patched))
        self.assertEqual({line.split()[-1] for line in clawd.TYPES}, {'clawd/' + p.name for p in PAYLOAD.glob('*.qml')})

    def test_changed_shell_fails_closed(self):
        with self.assertRaises(ValueError):
            clawd.patch_shell('ShellRoot {\n    Main {}\n}\n')

    def test_keybind_survives_user_edits_and_is_removable(self):
        original = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"))\n'
        shell_qml = installer.QS/'Shell.qml'
        patched = clawd.patch_keybind(capri.patch_keybind(original, shell_qml), shell_qml)
        self.assertEqual(clawd.patch_keybind(patched, shell_qml), patched)
        self.assertIn('hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(', patched)
        self.assertRegex(patched, r'ipc call clawd toggle"\)\)\n-- END serpantinum-clawd-v2 keybind\n')
        self.assertEqual(clawd.remove(patched), capri.patch_keybind(original, shell_qml))
        self.assertEqual(capri.remove(clawd.remove(patched)), original)
        self.assertIn('ipc call clawd toggle', capri.remove(patched))
        custom = patched.replace('SUPER + SHIFT + L', 'CTRL + ALT + F8')
        self.assertEqual(clawd.patch_keybind(custom, shell_qml), custom)
        with self.assertRaises(ValueError):
            clawd.patch_keybind('hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("custom"))\n', shell_qml)

    def test_settings_option_is_owned_by_clawd_only(self):
        tab = (ROOT/'payload/AddonsTab.qml').read_text()
        self.assertIn('ClawdSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }', tab)
        self.assertIn('addons_clawd_shortcut_passive', tab)
        stripped = clawd.remove(tab)
        self.assertNotIn('Clawd', stripped)
        self.assertNotIn('clawd', stripped)
        self.assertIn('CapriSettings', stripped)
        self.assertIn('HalloweenCard', stripped)
        self.assertIn('ClawdSettings', capri.remove(tab))
        self.assertIn('ClawdSettings', seasonal.remove(tab))

    def test_ipc_surface_is_exactly_four_commands(self):
        host = (PAYLOAD/'AddonClawd.qml').read_text()
        self.assertEqual(re.findall(r'function (\w+\([^)]*\)(?::\s*\w+)?)', host),
                         ['toggle(): void', 'appear(): void', 'hide(): void', 'play(name: string): string'])
        self.assertEqual(host.count('IpcHandler'), 1)
        self.assertIn('target: "clawd"', host)


class ClawdInstallTests(unittest.TestCase):
    def test_without_clawd_flag_parses(self):
        result = subprocess.run([sys.executable, str(ROOT/'install.py'), '--without-clawd', '--help'], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--without-clawd', result.stdout)
        self.assertIn('without_clawd=args.without_clawd', (ROOT/'install.py').read_text())

    def test_payload_copy_covers_every_clawd_file(self):
        qs = Path('/qs')
        copied = clawd.resources(PAYLOAD, qs)
        files = sorted(p for p in PAYLOAD.rglob('*') if p.is_file())
        self.assertEqual([path for path, _ in copied], [qs/'clawd'/p.relative_to(PAYLOAD) for p in files])
        self.assertEqual([blob for _, blob in copied], [p.read_bytes() for p in files])
        names = {str(p.relative_to(PAYLOAD)) for p in files}
        expected = {line.split()[-1].removeprefix('clawd/') for line in clawd.TYPES} | {'sprites/clawd.json'} | {f'sprites/{a}.png' for a in ANIMATIONS}
        self.assertEqual(names, expected)  # nothing stray gets installed


class ClawdSpriteTests(unittest.TestCase):
    def test_generated_sprites_are_current(self):
        result = subprocess.run([sys.executable, str(ROOT/'scripts/clawd/sprites.py'), '--check'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_manifest_strips_and_palette(self):
        from PIL import Image
        manifest = json.loads((SPRITES/'clawd.json').read_text())
        w, h = manifest['frame']['w'], manifest['frame']['h']
        self.assertEqual(list(manifest['animations']), ANIMATIONS)
        for name, clip in manifest['animations'].items():
            with self.subTest(animation=name):
                self.assertEqual(set(clip), {'file', 'frames', 'fps', 'loop'})
                self.assertEqual(clip['file'], name + '.png')
                self.assertIsInstance(clip['loop'], bool)
                self.assertGreater(clip['fps'], 0)
                with Image.open(SPRITES/clip['file']) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(image.size, (clip['frames'] * w, h))
                    self.assertLessEqual({c for _, c in image.getcolors(image.width * image.height)}, PALETTE)
        self.assertEqual({n for n, c in manifest['animations'].items() if c['loop']}, {'idle', 'walk', 'sit', 'sleep', 'drag', 'fall'})


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
class ClawdRuntimeTests(unittest.TestCase):
    def test_pet_lifecycle_play_drag_sleep_summon(self):
        self.run_fixture('clawd_runtime.qml', 90)

    def test_settings_card_controls(self):
        self.run_fixture('clawd_settings.qml', 40)

    def run_fixture(self, scenario, timeout):
        with tempfile.TemporaryDirectory(prefix='serpantinum-clawd-test-') as directory:
            fixture = Path(directory)
            shutil.copytree(PAYLOAD, fixture/'clawd')
            # No layer-shell offscreen: the real overlay in a plain window (the layer surface and mask are checked live).
            overlay = (fixture/'clawd/ClawdOverlay.qml').read_text()
            for line in ('    anchors { top: true; bottom: true; left: true; right: true }\n', '    exclusionMode: ExclusionMode.Ignore\n', '    focusable: menuHere\n',
                         '    WlrLayershell.namespace: "qs-addon-clawd"\n', '    WlrLayershell.layer: WlrLayer.Top\n',
                         '    WlrLayershell.keyboardFocus: menuHere ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n'):
                self.assertIn(line, overlay)
                overlay = overlay.replace(line, '')
            self.assertEqual(overlay.count('PanelWindow {'), 1)
            (fixture/'clawd/ClawdOverlay.qml').write_text(overlay.replace('PanelWindow {', 'FloatingWindow {\n    implicitWidth: 1280; implicitHeight: 720'))
            (fixture/'Shell.qml').write_text((ROOT/'tests/qml'/scenario).read_text())
            base = 'singleton Config 1.0 Config.qml\nsingleton Scaler 1.0 Scaler.qml\nsingleton I18n 1.0 I18n.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\nsingleton Caching 1.0 Caching.qml\nsingleton Sounds 1.0 Sounds.qml\n'
            (fixture/'qmldir').write_text(clawd.patch_qmldir(base))
            if scenario == 'clawd_settings.qml':
                shutil.copytree(installer.QS/'reusables', fixture/'reusables')
                shutil.copytree(ROOT/'payload/seasonal', fixture/'seasonal')
                (fixture/'qmldir').write_text(seasonal.patch_qmldir((fixture/'qmldir').read_text()))
            (fixture/'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var rawSettings: ({})
    function getSetting(key, fallback) { return rawSettings[key] === undefined ? fallback : rawSettings[key]; }
    function setSetting(key, value) { const next = Object.assign({}, rawSettings); next[key] = value; rawSettings = next; }
}
''')
            (fixture/'Scaler.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }\n')
            (fixture/'Caching.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string mainQml: ""; property string serpantinumDir: "" }\n')
            (fixture/'Sounds.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function playSfx(path) {} }\n')
            (fixture/'I18n.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function t(key) { return key; } property string currentLang: "en"; property bool rtl: false; readonly property int layoutDirection: Qt.LeftToRight; readonly property int textAlignment: Qt.AlignLeft }\n')
            (fixture/'ThemeBackend.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string fontFamily: "DejaVu Sans Mono"; property string iconFont: "Iosevka Nerd Font"; property bool liquidGlass: false; property bool glassActive: false; property real elementOpacity: 1; property real borderRadius: 16; property real clampedBorderRadius: 16; '
                                                + '; '.join(f'property color {k}: "{v}"' for k, v in COLORS.items()) + ' }\n')
            runtime = fixture/'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1',
                       XDG_DATA_HOME=str(fixture/'data'), XDG_STATE_HOME=str(fixture/'state'))
            process = subprocess.Popen(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                self.fail('Clawd fixture timed out:\n' + stdout + stderr)
            output = stdout + stderr
            self.assertEqual(process.returncode, 0, output)
            self.assertIn('CLAWD_PASS', output)
            self.assertNotIn('CLAWD_FAIL', output)
            self.assertEqual([line for line in output.splitlines() if re.search(r'clawd/\w+\.qml|Clawd:', line)], [], output)
            self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Binding loop|Cannot assign|Unable to assign')
            return output


if __name__ == '__main__':
    unittest.main()
