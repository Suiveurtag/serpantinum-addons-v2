import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import unittest
import urllib.request
from pathlib import Path

from test_changes import ROOT, control, installer

sys.path.insert(0, str(ROOT))
import capri  # noqa: E402
import seasonal  # noqa: E402

SCRIPTS = ROOT/'scripts/capri'


class CapriPatchTests(unittest.TestCase):
    def test_shell_and_qmldir_hooks_are_idempotent_and_removable(self):
        shell = (installer.QS/'Shell.qml').read_text()
        stacked = lambda text: capri.patch_shell(seasonal.transformations(installer.QS)[installer.QS/'Shell.qml'](installer.patch_shell(text)))
        once = stacked(shell)
        self.assertEqual(once, stacked(once))
        self.assertEqual(once.count('AddonCapri {}'), 1)
        self.assertNotIn('Capri', capri.remove(once))
        self.assertEqual(capri.remove(capri.remove(once)), capri.remove(once))
        qmldir = (installer.QS/'qmldir').read_text()
        patched = capri.patch_qmldir(qmldir)
        self.assertEqual(patched, capri.patch_qmldir(patched))
        self.assertNotIn('capri/', capri.remove(patched))

    def test_changed_shell_fails_closed(self):
        with self.assertRaises(ValueError):
            capri.patch_shell('ShellRoot {\n    Main {}\n}\n')

    def test_keybind_survives_user_edits_and_is_removable(self):
        original = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"))\n'
        shell_qml = installer.QS/'Shell.qml'
        patched = capri.patch_keybind(original, shell_qml)
        self.assertEqual(capri.patch_keybind(patched, shell_qml), patched)
        self.assertIn('ipc call capri toggle', patched)
        self.assertEqual(capri.remove(patched), original)
        custom = patched.replace('SUPER + SHIFT + K', 'CTRL + ALT + F9')
        self.assertEqual(capri.patch_keybind(custom, shell_qml), custom)
        old_config = control.CONFIG
        try:
            with tempfile.TemporaryDirectory() as directory:
                control.CONFIG = Path(directory)
                path = control.CONFIG/'hypr/config/keybinds.lua'
                path.parent.mkdir(parents=True)
                path.write_text(custom)
                rows = [row for row in control.keybinds()['rows'] if 'ipc call capri' in (row['command'] or '')]
                self.assertEqual([row['key'] for row in rows], ['CTRL + ALT + F9'])
        finally:
            control.CONFIG = old_config
        with self.assertRaises(ValueError):
            capri.patch_keybind('hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("custom"))\n', shell_qml)

    def test_sprite_shader_package_matches_its_source(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)/'shaders'
            shutil.copytree(ROOT/'payload/capri/shaders', folder)
            self.assertRegex(installer.shader_package_name(folder, 'sprite'), r'^sprite\.[a-f0-9]{12}\.frag\.qsb$')
            self.assertIn(b'shaders/sprite.frag.qsb', (ROOT/'payload/capri/CapriPet.qml').read_bytes())  # rewritten to it on install
            (folder/'sprite.frag').write_text((folder/'sprite.frag').read_text() + '\n// unrecompiled modification\n')
            with self.assertRaisesRegex(ValueError, 'source/package mismatch'):
                installer.shader_package_name(folder, 'sprite')

    def test_settings_option_is_owned_by_capri_only(self):
        tab = (ROOT/'payload/AddonsTab.qml').read_text()
        self.assertIn('CapriSettings', tab)
        self.assertIn('CapriSettings', seasonal.remove(tab))
        stripped = capri.remove(tab)
        self.assertNotIn('Capri', stripped)
        self.assertIn('HalloweenCard', stripped)


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class CapriSidecarTests(unittest.TestCase):
    def test_brain_rules_and_five_languages(self):
        result = subprocess.run(['node', str(ROOT/'tests/capri/brain.mjs')], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CAPRI_BRAIN_PASS', result.stdout)

    def hooks(self, env, action, target):
        result = subprocess.run(['node', str(SCRIPTS/'hooks.js'), action, target], env=env, capture_output=True, text=True, timeout=10)
        return json.loads(result.stdout)

    def test_hook_installers_preserve_settings_and_restore_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            env = dict(os.environ, CLAUDE_CONFIG_DIR=str(home/'claude'), CODEX_HOME=str(home/'codex'))
            (home/'claude').mkdir()
            original = json.dumps({'model': 'opus', 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'mine'}]}]}}, indent=2) + '\n'
            (home/'claude/settings.json').write_text(original)
            for target, file in (('claude', home/'claude/settings.json'), ('codex', home/'codex/hooks.json')):
                with self.subTest(target=target):
                    self.assertFalse(self.hooks(env, 'status', target)['data']['installed'])
                    self.assertTrue(self.hooks(env, 'install', target)['ok'])
                    installed = file.read_text()
                    self.assertTrue(self.hooks(env, 'status', target)['data']['installed'])
                    self.hooks(env, 'install', target)
                    self.assertEqual(file.read_text(), installed)
                    self.assertTrue(self.hooks(env, 'uninstall', target)['ok'])
                    self.assertFalse(self.hooks(env, 'status', target)['data']['installed'])
            self.assertEqual(json.loads((home/'claude/settings.json').read_text()), json.loads(original))
            self.assertEqual(len(list((home/'claude').glob('settings.json.capri-backup-*'))), 2)
            (home/'claude/settings.json').write_text('{broken')
            self.assertFalse(self.hooks(env, 'install', 'claude')['ok'])
            self.assertEqual((home/'claude/settings.json').read_text(), '{broken')

    def test_hook_reaches_sidecar_stdout_and_sidecar_exits_with_stdin(self):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        env = dict(os.environ, CAPRI_PORT=str(port))
        sidecar = subprocess.Popen(['node', str(SCRIPTS/'sidecar.js')], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertIn('listening', sidecar.stderr.readline())
            sidecar.stdin.write('{"t":"ping","id":1}\n'); sidecar.stdin.flush()
            self.assertEqual(json.loads(sidecar.stdout.readline()), {'t': 'pong', 'id': 1})
            event = {'hook_event_name': 'PreToolUse', 'session_id': 's', 'tool_name': 'Edit', 'tool_input': {'file_path': 'a.js', 'new_string': 'x' * 900}}
            hook = subprocess.run(['node', str(SCRIPTS/'hooks/capri-hook.js')], input=json.dumps(event), env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual((hook.returncode, hook.stdout), (0, ''))
            message = json.loads(sidecar.stdout.readline())
            self.assertEqual(message['t'], 'event')
            self.assertEqual(message['evt']['tool_input'], {'file_path': 'a.js', 'new_string_len': 900})
            request = urllib.request.Request(f'http://127.0.0.1:{port}/event', data=b'{}', headers={'Origin': 'https://evil.example'})
            with self.assertRaises(urllib.error.HTTPError) as refused:
                urllib.request.urlopen(request, timeout=2)
            self.assertEqual(refused.exception.code, 403)
            refused.exception.close()
            sidecar.stdin.write(json.dumps({'t': 'foreground', 'pid': os.getpid(), 'class': 'steam_app_2357570', 'title': 'Overwatch'}) + '\n'); sidecar.stdin.flush()
            self.assertEqual(json.loads(sidecar.stdout.readline()), {'t': 'pc', 'game': 'Overwatch'})
            sidecar.stdin.close()
            self.assertEqual(sidecar.wait(timeout=5), 0)
        finally:
            sidecar.kill()
            sidecar.wait()
            sidecar.stdout.close()
            sidecar.stderr.close()

    def test_sidecar_retries_port_after_reload_overlap(self):
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1', 0)); occupied.listen()
            port = occupied.getsockname()[1]
            sidecar = subprocess.Popen(['node', str(SCRIPTS/'sidecar.js')], env=dict(os.environ, CAPRI_PORT=str(port)),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertIn('already in use', sidecar.stderr.readline())
                occupied.close()
                self.assertIn('listening', sidecar.stderr.readline())
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=2) as reply:
                    self.assertEqual(json.load(reply)['pid'], sidecar.pid)
                sidecar.stdin.close()
                self.assertEqual(sidecar.wait(timeout=5), 0)
            finally:
                sidecar.kill(); sidecar.wait()
                sidecar.stdout.close(); sidecar.stderr.close()

    def test_world_geometry_pc_thresholds_and_linux_events(self):
        result = subprocess.run(['node', str(ROOT/'tests/capri/world.mjs')], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CAPRI_WORLD_PASS', result.stdout)

    def test_hook_is_silent_when_nothing_listens(self):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        hook = subprocess.run(['node', str(SCRIPTS/'hooks/capri-codex-hook.js')], input='{"hook_event_name":"Stop"}',
                              env=dict(os.environ, CAPRI_PORT=str(port)), capture_output=True, text=True, timeout=5)
        self.assertEqual((hook.returncode, hook.stdout, hook.stderr), (0, '', ''))


@unittest.skipUnless(shutil.which('quickshell') and shutil.which('node'), 'Quickshell runtime unavailable')
class CapriRuntimeTests(unittest.TestCase):
    def test_master_switch_loads_and_unloads_everything(self):
        self.run_fixture('capri_lifecycle.qml', 25)

    def test_world_moves_end_to_end(self):
        output = self.run_fixture('capri_world.qml', 60)
        self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Unhandled|is not defined|Binding loop')

    def test_brain_hooks_panels_reminders_end_to_end(self):
        output = self.run_fixture('capri_brain.qml', 45)
        self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Unhandled|is not defined|Binding loop|Error:')

    def test_native_ui_layout(self):
        output = self.run_fixture('capri_ui.qml', 30)
        self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Binding loop|Cannot assign|Unable to assign')

    def test_body_moves_end_to_end(self):
        output = self.run_fixture('capri_body.qml', 60)
        self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Unhandled')

    def run_fixture(self, scenario, timeout):
        with tempfile.TemporaryDirectory(prefix='serpantinum-capri-test-') as directory:
            fixture = Path(directory)
            shutil.copytree(ROOT/'payload/capri', fixture/'capri')
            shutil.copytree(SCRIPTS, fixture/'data/serpantinum-addons-v2/scripts/capri')
            # No layer-shell offscreen: her engine in a plain window instead (the layer surface is checked live).
            (fixture/'capri/CapriOverlay.qml').write_text('''import QtQuick
import Quickshell
import "../"
FloatingWindow {
    id: surface
    property var screen
    required property var world
    readonly property var engine: world.engine
    implicitWidth: 1280; implicitHeight: 720
    color: "transparent"
    Component.onCompleted: { Capri.mounted(); world.registerSurface(screen.name, surface); }
    Component.onDestruction: { world.unregisterSurface(screen.name); Capri.unmounted(); }
}
''')
            (fixture/'Shell.qml').write_text((ROOT/'tests/qml'/scenario).read_text())
            (fixture/'qmldir').write_text(capri.patch_qmldir('singleton Config 1.0 Config.qml\nsingleton Scaler 1.0 Scaler.qml\nsingleton SysData 1.0 SysData.qml\nsingleton SysNotif 1.0 SysNotif.qml\nsingleton I18n 1.0 I18n.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\n'))
            (fixture/'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var rawSettings: ({})
    function getSetting(key, fallback) { return rawSettings[key] === undefined ? fallback : rawSettings[key]; }
    function setSetting(key, value) { const next = Object.assign({}, rawSettings); next[key] = value; rawSettings = next; }
}
''')
            (fixture/'Scaler.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }\n')
            (fixture/'SysData.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int cpu: 0; property int subscribers: 0; function subscribe() { subscribers++; } function unsubscribe() { subscribers--; } }\n')
            (fixture/'SysNotif.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool hasBattery: false; property int batteryPercentage: 100; property bool isCharging: false }\n')
            (fixture/'I18n.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string currentLang: \"en\" }\n')
            (fixture/'ThemeBackend.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string fontFamily: \"DejaVu Sans Mono\"; property color base: \"#120c1c\" }\n')
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            runtime = fixture/'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1',
                       XDG_DATA_HOME=str(fixture/'data'), CAPRI_PORT=str(port))
            process = subprocess.Popen(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                # A failed fixture must not leave its native device watcher behind.
                os.killpg(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                self.fail('Capri fixture timed out:\n' + stdout + stderr)
            output = stdout + stderr
            self.assertEqual(process.returncode, 0, output)
            self.assertIn('CAPRI_PASS', output)
            self.assertNotIn('CAPRI_FAIL', output)
            return output


if __name__ == '__main__':
    unittest.main()
