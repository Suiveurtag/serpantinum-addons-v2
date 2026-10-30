import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from test_changes import ROOT, installer

sys.path.insert(0, str(ROOT))
import capri  # noqa: E402
import clawd  # noqa: E402
import seasonal  # noqa: E402

PAYLOAD = ROOT/'payload/clawd'
SPRITES = PAYLOAD/'sprites'
ANIMATIONS = ['idle', 'blink', 'look_left', 'look_right', 'look_up', 'walk', 'turn', 'sit', 'sleep', 'drag', 'fall', 'land', 'spawn',
              'think', 'work', 'oops', 'alert', 'happy', 'petpet', 'petpetheart']
HOOKS = ROOT/'scripts/clawd/hooks.py'
HOOK = ROOT/'scripts/clawd/hooks/clawd-hook.js'
CAPRI = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node "/x/capri-hook.js"', 'async': True}]}],
                   'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'node "/x/capri-hook.js"'}]}]},
         'model': 'opus'}
PALETTE = {(0, 0, 0, 0), (0xD9, 0x77, 0x57, 255), (0, 0, 0, 255), (0xF0, 0xEE, 0xE6, 255), (0xEC, 0x5B, 0x86, 255)}
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
        expected = {line.split()[-1].removeprefix('clawd/') for line in clawd.TYPES} | {'sprites/clawd.json'} | {f'sprites/{a}.png' for a in ANIMATIONS + ['hand']}
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
        self.assertEqual({n for n, c in manifest['animations'].items() if c['loop']}, {'idle', 'walk', 'sit', 'sleep', 'drag', 'fall', 'work', 'alert', 'petpet', 'petpetheart'})
        self.assertEqual(manifest['hand']['frames'], manifest['animations']['petpet']['frames'])  # the hand is frame-locked to him


class ClawdHooksInstallerTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix='clawd-hooks-'))
        self.addCleanup(shutil.rmtree, self.home)
        self.env = dict(os.environ, CLAUDE_CONFIG_DIR=str(self.home/'claude'), CODEX_HOME=str(self.home/'codex'))

    def hooks(self, action, agent):
        result = subprocess.run([sys.executable, str(HOOKS), action, agent], env=self.env, capture_output=True, text=True, timeout=20)
        out = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0 if out['ok'] else 1)
        return out

    def test_install_keeps_other_hooks_backs_up_and_uninstalls_cleanly(self):
        for agent, name in (('claude', 'settings.json'), ('codex', 'hooks.json')):
            with self.subTest(agent=agent):
                file = self.home/agent/name
                file.parent.mkdir()
                file.write_text(json.dumps(CAPRI))
                self.assertFalse(self.hooks('status', agent)['data']['installed'])
                data = self.hooks('install', agent)['data']
                self.assertTrue(data['installed'] and data['changed'])
                settings = json.loads(file.read_text())
                self.assertEqual(settings['hooks']['Stop'][0], CAPRI['hooks']['Stop'][0])
                self.assertEqual(settings['model'], 'opus')
                ours = [h for groups in settings['hooks'].values() for g in groups for h in g['hooks'] if 'clawd-hook.js' in h['command']]
                self.assertEqual(len(ours), 8)
                self.assertEqual({h['command'].endswith(' --agent codex') for h in ours}, {agent == 'codex'})
                self.assertEqual({h.get('async', False) for h in ours}, {agent == 'claude'})
                self.assertEqual(len(list(file.parent.glob(name + '.clawd-backup-*'))), 1)
                self.assertFalse(self.hooks('install', agent)['data']['changed'])  # idempotent: no backup spam
                self.assertEqual(len(list(file.parent.glob(name + '.clawd-backup-*'))), 1)
                data = self.hooks('uninstall', agent)['data']
                self.assertTrue(data['changed'] and not data['installed'] and data['events'] == [])
                self.assertEqual(json.loads(file.read_text()), CAPRI)

    def test_removes_only_its_command_from_a_shared_group(self):
        file = self.home/'claude/settings.json'
        file.parent.mkdir()
        shared = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node /x/capri-hook.js'}, {'type': 'command', 'command': 'node /y/clawd-hook.js'}]}]}}
        file.write_text(json.dumps(shared))
        self.hooks('uninstall', 'claude')
        self.assertEqual(json.loads(file.read_text()), {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node /x/capri-hook.js'}]}]}})

    def test_missing_files_and_bad_files(self):
        self.assertFalse(self.hooks('uninstall', 'codex')['data']['changed'])
        self.assertFalse((self.home/'codex').exists())  # uninstall never creates a file
        self.assertTrue(self.hooks('install', 'codex')['data']['installed'])
        self.assertEqual(list((self.home/'codex').glob('*backup*')), [])
        for bad in ('{nope', '[]', '{"hooks": []}', '{"hooks": {"Stop": [{"command": "x"}]}}'):
            with self.subTest(bad=bad):
                file = self.home/'claude/settings.json'
                file.parent.mkdir(exist_ok=True)
                file.write_text(bad)
                out = self.hooks('install', 'claude')
                self.assertFalse(out['ok'])
                self.assertIn('nothing changed', out['error'])
                self.assertEqual(file.read_text(), bad)
        self.assertFalse(self.hooks('remove', 'claude')['ok'])
        self.assertFalse(self.hooks('status', 'antigravity')['ok'])

    def test_without_clawd_uninstalls_both_agents(self):
        for agent in ('claude', 'codex'):
            self.hooks('install', agent)
        subprocess.run([sys.executable, '-c', 'import clawd; clawd.uninstall_hooks()'], cwd=ROOT, env=self.env, check=True, timeout=20)
        for agent in ('claude', 'codex'):
            self.assertFalse(self.hooks('status', agent)['data']['events'])
        self.assertIn('if without_clawd:\n        clawd.uninstall_hooks()', (ROOT/'install.py').read_text())


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class ClawdHookScriptTests(unittest.TestCase):
    def send(self, payload, *args, runtime):
        started = time.monotonic()
        result = subprocess.run(['node', str(HOOK), *args], input=payload, env=dict(os.environ, XDG_RUNTIME_DIR=str(runtime)), capture_output=True, text=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        self.assertLess(time.monotonic() - started, 3)

    def test_silent_without_shell_and_on_garbage(self):
        with tempfile.TemporaryDirectory() as runtime:
            for payload in ('', 'nope', '{}', json.dumps({'hook_event_name': 'Stop'})):
                self.send(payload, runtime=runtime)

    def test_sends_one_slim_line(self):
        with tempfile.TemporaryDirectory() as runtime:
            (Path(runtime)/'serpantinum').mkdir()
            server = socket.socket(socket.AF_UNIX)
            server.bind(str(Path(runtime)/'serpantinum/clawd.sock'))
            server.listen()
            server.settimeout(5)
            lines = []
            def accept(count):
                for _ in range(count):
                    conn, _ = server.accept()
                    lines.append(conn.makefile().read())
                    conn.close()
            reader = threading.Thread(target=accept, args=(2,))
            reader.start()
            secret = {'prompt': 'my secret prompt', 'tool_input': {'command': 'rm -rf /'}, 'last_assistant_message': 'reply'}
            self.send(json.dumps({'hook_event_name': 'PreToolUse', 'session_id': 's' * 200, 'cwd': '/home/u/Projects/Clawd', 'tool_name': 'Bash', **secret}), runtime=runtime)
            self.send(json.dumps({'hook_event_name': 'PermissionRequest', 'session_id': 'c', 'cwd': '/w', 'tool_name': 'exec_command'}), '--agent', 'codex', runtime=runtime)
            reader.join(10)
            server.close()
            self.assertEqual(len(lines), 2)
            self.assertTrue(all(line.endswith('\n') and line.count('\n') == 1 for line in lines))
            claude, codex = (json.loads(line) for line in lines)
            self.assertEqual(claude, {'agent': 'claude', 'event': 'PreToolUse', 'session_id': 's' * 80, 'tool_name': 'Bash', 'dir': 'Clawd'})
            self.assertEqual(codex, {'agent': 'codex', 'event': 'Notification', 'session_id': 'c', 'tool_name': 'exec_command', 'notification_type': 'permission_prompt', 'dir': 'w'})


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
            runtime = fixture/'runtime'
            (runtime/'serpantinum').mkdir(mode=0o700, parents=True)
            (fixture/'Caching.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string mainQml: ""; property string serpantinumDir: ""; property string runDir: ' + json.dumps(str(runtime/'serpantinum')) + ' }\n')
            shutil.copytree(ROOT/'scripts/clawd', fixture/'data/serpantinum-addons-v2/scripts/clawd')
            (fixture/'Sounds.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function playSfx(path) {} }\n')
            (fixture/'I18n.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function t(key) { return key; } property string currentLang: "en"; property bool rtl: false; readonly property int layoutDirection: Qt.LeftToRight; readonly property int textAlignment: Qt.AlignLeft }\n')
            (fixture/'ThemeBackend.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string fontFamily: "DejaVu Sans Mono"; property string iconFont: "Iosevka Nerd Font"; property bool liquidGlass: false; property bool glassActive: false; property real elementOpacity: 1; property real borderRadius: 16; property real clampedBorderRadius: 16; '
                                                + '; '.join(f'property color {k}: "{v}"' for k, v in COLORS.items()) + ' }\n')
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1',
                       XDG_DATA_HOME=str(fixture/'data'), XDG_STATE_HOME=str(fixture/'state'),
                       CLAUDE_CONFIG_DIR=str(fixture/'claude'), CODEX_HOME=str(fixture/'codex'))
            process = subprocess.Popen(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
            if scenario == 'clawd_runtime.qml':
                threading.Thread(target=self.hook_when_listening, args=(runtime, env), daemon=True).start()
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
            if scenario == 'clawd_settings.qml':
                self.assertTrue(json.loads((fixture/'claude/settings.json').read_text())['hooks'])
            return output

    @staticmethod
    def hook_when_listening(runtime, env):
        # a real hook event through node and the shell's socket, while Clawd is still OFF
        sock = runtime/'serpantinum/clawd.sock'
        for _ in range(200):
            if sock.exists(): break
            time.sleep(0.05)
        subprocess.run(['node', str(HOOK)], input=json.dumps({'hook_event_name': 'UserPromptSubmit', 'session_id': 'e2e', 'cwd': '/tmp/e2e-dir'}),
                       env=env, capture_output=True, text=True, timeout=10)


if __name__ == '__main__':
    unittest.main()
