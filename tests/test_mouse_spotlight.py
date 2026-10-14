import importlib.util
import os
import shutil
import subprocess
import socket
import tempfile
import threading
import unittest
from pathlib import Path

from test_changes import installer, control

spec = importlib.util.spec_from_file_location('spotlight', Path(__file__).resolve().parents[1] / 'scripts/mouse_spotlight.py')
spotlight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spotlight)


class SpotlightTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
    def test_qt_recording_of_accents_navigation_and_ctrl_letters(self):
        source = (Path(__file__).resolve().parents[1] / 'payload/AddonKeybindsTab.qml').read_text()
        function = source[source.index('    function recordedKey(event) {'):source.index('    function loadData(data) {')]
        fixture = '''import QtQuick
import Quickshell
Scope {
    id: root
''' + function + '''
    Timer { interval: 100; running: true; onTriggered: {
        let checks = [
            [Qt.Key_Dead_Circumflex, "", "dead_circumflex"],
            [Qt.Key_Dead_Diaeresis, "", "dead_diaeresis"],
            [Qt.Key_A, String.fromCharCode(1), "A"],
            [Qt.Key_F9, "", "F9"],
            [Qt.Key_Home, "", "Home"],
            [0, "", ""]
        ];
        for (let check of checks) {
            if (root.recordedKey({key: check[0], text: check[1]}) !== check[2]) {
                console.error("Recording failed: " + check[2]); Qt.exit(1); return;
            }
        }
        Qt.quit();
    }}
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Shell.qml'
            path.write_text(fixture)
            runtime = Path(directory) / 'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(['quickshell', '-p', str(path)], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cursor_ipc_handles_fragmented_reply_and_negative_coordinates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'cursor.sock'
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(str(path))
                server.listen(1)
                def reply():
                    with server.accept()[0] as client:
                        self.assertEqual(client.recv(128), b'j/cursorpos')
                        client.sendall(b'{"x": -1920,')
                        client.sendall(b'"y": 360.5}')
                worker = threading.Thread(target=reply)
                worker.start()
                self.assertEqual(spotlight.query_cursor(path), {'x': -1920.0, 'y': 360.5})
                worker.join(2)
                self.assertFalse(worker.is_alive())

    def test_reinstall_preserves_recorded_shortcut_and_editor_reads_it(self):
        original = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"))\n'
        patched = installer.patch_spotlight_keybind(original)
        self.assertEqual(installer.patch_spotlight_keybind(patched), patched)
        custom = patched.replace('SUPER + SHIFT + M', 'CTRL + ALT + F9')
        self.assertEqual(installer.patch_spotlight_keybind(custom), custom)
        old_config = control.CONFIG
        try:
            with tempfile.TemporaryDirectory() as directory:
                control.CONFIG = Path(directory)
                path = control.CONFIG / 'hypr/config/keybinds.lua'
                path.parent.mkdir(parents=True)
                path.write_text(custom)
                rows = control.keybinds()['rows']
                matches = [row for row in rows if 'addonMouseSpotlight' in (row['command'] or '')]
                self.assertEqual(len(matches), 1)
                self.assertEqual(matches[0]['key'], 'CTRL + ALT + F9')
        finally:
            control.CONFIG = old_config

    def test_default_chord_conflict_leaves_configuration_untouched(self):
        original = 'hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("custom-command"))\n'
        with self.assertRaises(ValueError):
            installer.patch_spotlight_keybind(original)
