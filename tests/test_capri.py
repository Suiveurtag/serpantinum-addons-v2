import json
import os
import shutil
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

    def test_settings_option_is_owned_by_capri_only(self):
        tab = (ROOT/'payload/AddonsTab.qml').read_text()
        self.assertIn('CapriSettings', tab)
        self.assertIn('CapriSettings', seasonal.remove(tab))
        stripped = capri.remove(tab)
        self.assertNotIn('Capri', stripped)
        self.assertIn('HalloweenCard', stripped)


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class CapriSidecarTests(unittest.TestCase):
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
            sidecar.stdin.close()
            self.assertEqual(sidecar.wait(timeout=5), 0)
        finally:
            sidecar.kill()
            sidecar.wait()
            sidecar.stdout.close()
            sidecar.stderr.close()

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
        with tempfile.TemporaryDirectory(prefix='serpantinum-capri-test-') as directory:
            fixture = Path(directory)
            shutil.copytree(ROOT/'payload/capri', fixture/'capri')
            shutil.copytree(SCRIPTS, fixture/'data/serpantinum-addons-v2/scripts/capri')
            # No PanelWindow backend offscreen: keep the pet, drop the layer surface (checked live instead).
            (fixture/'capri/CapriOverlay.qml').write_text('import QtQuick\nimport "../"\nItem { property var screen; CapriPet {} }\n')
            (fixture/'Shell.qml').write_text((ROOT/'tests/qml/capri_lifecycle.qml').read_text())
            (fixture/'qmldir').write_text(capri.patch_qmldir('singleton Config 1.0 Config.qml\nsingleton Scaler 1.0 Scaler.qml\n'))
            (fixture/'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool capri: false
    property bool performance: false
    function getSetting(key, fallback) { return key === "addonsV2Capri" ? capri : (key === "general.performance" ? performance : fallback); }
    function setSetting(key, value) { if (key === "addonsV2Capri") capri = value; else if (key === "general.performance") performance = value; }
}
''')
            (fixture/'Scaler.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }\n')
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            runtime = fixture/'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1',
                       XDG_DATA_HOME=str(fixture/'data'), CAPRI_PORT=str(port))
            result = subprocess.run(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('CAPRI_PASS', output)
            self.assertNotIn('CAPRI_FAIL', output)


if __name__ == '__main__':
    unittest.main()
