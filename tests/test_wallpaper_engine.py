import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import tempfile
from unittest.mock import patch as mock_patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

patch = load('we_patch', ROOT / 'wallpaper_engine.py')
bridge = load('we_bridge', ROOT / 'scripts/wallpaper_engine.py')

class SceneBridgeTests(unittest.TestCase):
    def test_only_presented_healthy_enabled_outputs_are_adopted(self):
        def state(source, **values):
            return {'runtime': {'source': source}, 'presentation': {'presented': 1, **values}}
        status = {'outputs': {'DP-1': {'disabled': True}}, 'output_runtime': {
            'DP-1': state('/disabled'), 'DP-2': state('/starting', presented=0),
            'DP-3': state('/failed', last_error='GPU failure'), 'HDMI-A-1': state('/healthy', paused=True)}}
        self.assertEqual(bridge.active_outputs(status), {'HDMI-A-1': '/healthy'})
        self.assertEqual(bridge.active_outputs(None), {})

    def test_single_output_status(self):
        self.assertEqual(bridge.active_outputs({'runtime': {'output_name': 'DP-1', 'source': '/scene'},
            'presentation': {'presented': 2}}), {'DP-1': '/scene'})

    def test_changed_shell_is_rejected_before_writing(self):
        with self.assertRaises(ValueError):
            patch.singleton('incompatible upstream', Path('/deploy'))

    def test_native_selection_and_clear_wait_for_output_release(self):
        base = ('    property var engines: ({})\n'
            '    function getWallpaper(screenName: string): string {\n}\n'
            '    function getWallpaperPath(screenName: string): string {\n}\n'
            '        target: "wallpaper"\n'
            '        root.wallpaperChanged(screenName, path, transition ? transition : "fade");\n'
            '        root.wallpaperCleared(screenName);\n')
        deployed = patch.singleton(base, Path('/deploy'))
        self.assertEqual(deployed, patch.singleton(deployed, Path('/deploy')))
        self.assertIn('clear: true', deployed)
        self.assertIn('if (request.clear) root.wallpaperCleared', deployed)

    def test_engine_handoff_uses_the_stable_monitor_and_defers_mutations(self):
        base = '                id: barWindow\n'
        deployed = patch.engine(base)
        self.assertEqual(deployed, patch.engine(deployed))
        self.assertIn('barWindow.modelData.name', deployed)
        self.assertIn('onExternalSceneChanged: engineSceneSync.restart()', deployed)

    def test_gpu_stream_is_captured_before_the_shader_samples_it(self):
        source = ('import QtQuick\n    property bool useSnapshot: false\n'
            '    property int revision: 0\n            source: root.newSource\n'
            'property variant newTex: newLayer\n')
        deployed = patch.blur(source, Path('/local'))
        self.assertEqual(deployed, patch.blur(deployed, Path('/local')))
        self.assertIn('hideSource: true', deployed)
        self.assertIn('root.externalScene ? sceneSource : newLayer', deployed)

    def test_blur_preserves_snapshot_mode_and_survives_missing_bridge_state(self):
        source = ('import QtQuick\n    property bool useSnapshot: false\n'
            '    property int revision: 0\n'
            '    readonly property bool snapshotMode: useSnapshot || inheritedOwner !== null\n'
            '    readonly property var engine: snapshotMode ? null : (Wallpaper.engines[screenName] || null)\n')
        deployed = patch.blur(source, Path('/local'))
        self.assertEqual(deployed, patch.blur(deployed, Path('/local')))
        self.assertIn('engine: snapshotMode || externalScene ? null :', deployed)
        self.assertIn('externalScene: !snapshotMode && !!Wallpaper.externalScreens &&', deployed)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
    def test_settings_startup_does_not_regenerate_wallpaper_colors(self):
        import install
        with tempfile.TemporaryDirectory(prefix='serpantinum-settings-colors-') as directory:
            fixture = Path(directory)
            (fixture/'scripts').mkdir()
            (fixture/'scripts/wallpaper_engine.py').write_text('pass\n')
            (fixture/'locked').touch()
            source = (install.QS/'singletons/theme/Wallpaper.qml').read_text()
            (fixture/'Wallpaper.qml').write_text(patch.singleton(source, fixture).replace('import "../../"', 'import "./"'))
            (fixture/'qmldir').write_text('singleton Wallpaper 1.0 Wallpaper.qml\nsingleton Caching 1.0 Caching.qml\nsingleton Matugen 1.0 Matugen.qml\n')
            (fixture/'Caching.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool isStandalone: true
    function getRunDir(name) { return DIRECTORY; }
    function getCacheDir(name) { return "/wallpaper"; }
}
'''.replace('DIRECTORY', json.dumps(directory)))
            (fixture/'Matugen.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property int calls: 0
    property string image: ""
    function generate(path) { calls++; image = path; }
}
''')
            (fixture/'Shell.qml').write_text('''import QtQuick
import Quickshell
import "./"
ShellRoot {
    property var wallpaper: Wallpaper
    Timer {
        interval: 100; running: true; repeat: true
        property int step: 0
        function expect(value, message) { if (!value) { console.error("COLORS_FAIL", message); Qt.exit(1); } }
        onTriggered: {
            switch (step++) {
            case 0:
                expect(Matugen.calls === 0, "opening Settings must not generate a palette");
                Wallpaper.externalScreens = {"DP-1": {snapshot: "/settings-snapshot.png"}};
                break;
            case 1:
                expect(Matugen.calls === 0, "Settings must not own wallpaper generation");
                Caching.isStandalone = false;
                Wallpaper.externalScreens = {"DP-1": {snapshot: "/scene-snapshot.png"}};
                break;
            case 2:
                expect(Matugen.calls === 1 && Matugen.image === "/scene-snapshot.png", "the shell must still generate scene colors");
                Wallpaper.externalScreens = {};
                break;
            case 3:
                expect(Matugen.calls === 2 && Matugen.image === "/wallpaper/current_wallpaper.png", "native wallpaper fallback must still work");
                console.log("COLORS_PASS"); Qt.quit();
            }
        }
    }
}
''')
            runtime = fixture/'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1')
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('COLORS_PASS', output)

    def test_snapshot_captures_once_and_reuses_the_frozen_image(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            cache = home / 'cache'; cache.mkdir()
            source = home / 'scene'; source.mkdir()
            (source / 'project.json').write_text('{"title":"Frame test"}')
            probe = home / '.local/libexec/we-layerd/glass-frame-probe'
            probe.parent.mkdir(parents=True); probe.touch()
            def capture(*args, **kwargs):
                Path(args[2]).write_bytes(b'captured-frame')
                return SimpleNamespace(returncode=0)
            with mock_patch.object(bridge, 'HOME', home), mock_patch.object(bridge, 'CACHE', cache), mock_patch.object(bridge, 'run', side_effect=capture) as command:
                result = bridge.snapshot(source, 'DP-1', force=True)
                self.assertEqual(Path(result['snapshot']).read_bytes(), b'captured-frame')
                bridge.snapshot(source, 'DP-1')
                self.assertEqual(command.call_count, 1)

    def test_invalid_screen_cannot_write_outside_cache(self):
        for screen in ('../oops', '..', '/', ''):
            with self.assertRaises(ValueError):
                bridge.snapshot('/unused', screen)

if __name__ == '__main__':
    unittest.main()
