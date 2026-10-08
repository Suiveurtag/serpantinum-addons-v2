import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import trackpad
import control
sys.path.pop(0)


class TrackpadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        base = Path(self.directory.name)
        for name, path in [('MAIN', base / 'hyprland.lua'),
                           ('LUA', base / 'config/serpantinum_trackpad.lua'),
                           ('SETTINGS', base / 'config/serpantinum_trackpad.json')]:
            p = patch.object(trackpad, name, path)
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(control, 'STATE', base / 'backups')
        p.start()
        self.addCleanup(p.stop)
        p = patch.object(trackpad, 'touchpads', return_value=[{'name': 'test-touchpad'}])
        p.start()
        self.addCleanup(p.stop)
        p = patch.object(trackpad, 'run', side_effect=self.backend_run)
        self.runner = p.start()
        self.addCleanup(p.stop)
        self.config_error = False
        self.original = 'require("config/settings")\nrequire("config/keybinds")\n'
        trackpad.MAIN.write_text(self.original)

    def backend_run(self, *args):
        if 'getoption' in args:
            return json.dumps({'bool': False, 'float': 0.2})
        if args[-1] == 'configerrors':
            return 'bad config' if self.config_error else 'ok'
        return 'ok'

    def payload(self):
        data = trackpad.status()
        data['settings'] = dict(speed=-0.35, disableWhileTyping=True,
                                disableClicksWhileTyping=True)
        return data

    def test_save_persists_only_trackpad_settings_and_is_idempotent(self):
        result = trackpad.save(self.payload())
        source = trackpad.LUA.read_text()
        self.assertIn('hl.device({ name = "test-touchpad", sensitivity = -0.35', source)
        self.assertIn('disable_while_typing = true', source)
        self.assertIn('guard({"test-touchpad"})', source)
        self.assertTrue(trackpad.MAIN.read_text().startswith(self.original))
        self.assertEqual(result['settings']['speed'], -0.35)
        trackpad.save(result)
        self.assertEqual(trackpad.MAIN.read_text().count('require("config/serpantinum_trackpad")'), 1)

    def test_reload_error_restores_files_and_removes_new_files(self):
        self.config_error = True
        with self.assertRaisesRegex(ValueError, 'bad config'):
            trackpad.save(self.payload())
        self.assertEqual(trackpad.MAIN.read_text(), self.original)
        self.assertFalse(trackpad.LUA.exists())
        self.assertFalse(trackpad.SETTINGS.exists())
        self.assertEqual(self.runner.call_args.args, ('hyprctl', 'reload'))

    def test_external_change_is_preserved(self):
        data = self.payload()
        trackpad.MAIN.write_text(self.original + '-- external edit\n')
        with self.assertRaisesRegex(ValueError, 'outside this editor'):
            trackpad.save(data)
        self.assertIn('-- external edit', trackpad.MAIN.read_text())
        self.assertFalse(trackpad.LUA.exists())

    def test_invalid_speed_and_disconnected_trackpad_do_not_write(self):
        for speed in (float('nan'), float('inf'), 1.1, -1.1, True):
            data = self.payload()
            data['settings']['speed'] = speed
            with self.assertRaisesRegex(ValueError, 'speed'):
                trackpad.save(data)
        with patch.object(trackpad, 'touchpads', return_value=[]):
            with self.assertRaisesRegex(ValueError, 'No touchpad'):
                trackpad.save(self.payload())
        self.assertEqual(trackpad.MAIN.read_text(), self.original)
        self.assertFalse(trackpad.LUA.exists())

    def test_disabling_click_guard_removes_its_loading_code(self):
        data = self.payload()
        data['settings']['disableClicksWhileTyping'] = False
        trackpad.save(data)
        self.assertNotIn('dofile', trackpad.LUA.read_text())


if __name__ == '__main__':
    unittest.main()
