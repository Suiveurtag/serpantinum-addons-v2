import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


control = load('control', ROOT/'scripts/control.py')
installer = load('installer', ROOT/'install.py')


class ChangeTests(unittest.TestCase):
    def test_guide_idempotence_and_about_order(self):
        text = (installer.QS/'guide/GuidePopup.qml').read_text()
        patched = installer.patch_guide(text)
        self.assertEqual(patched, installer.patch_guide(patched))
        model = patched[patched.index('property var tabsModel:'):patched.index('    StackView.onStatusChanged:')]
        self.assertLess(model.index('id: "Keybinds"'), model.index('id: "About"'))
        self.assertEqual(patched.count('id: tabAddonMonitors\n'), 1)
        self.assertIn('tabAddonAddons, tabAddonMonitors, tabAddonKeybinds, tabAbout', patched)

    def test_theme_uses_original_tile_delegate(self):
        text = (installer.QS/'guide/theme/ThemeTab.qml').read_text()
        self.assertEqual(text, installer.patch_theme(text))
        self.assertNotIn('options: ["Matugen", "Vibrant", "Vivid"]', text)
        self.assertIn('{name: "Vibrant", isMatugen: true', text)
        self.assertIn('systemPresets = sys.slice()', text)

    def test_key_edits_preserve_action_flags_and_generated_bindings(self):
        old_config, old_state, old_run = control.CONFIG, control.STATE, control.run
        try:
            with tempfile.TemporaryDirectory() as directory:
                control.CONFIG = Path(directory)
                control.STATE = Path(directory)/'backups'
                control.run = lambda *args: 'ok' if args[-1] == 'configerrors' else ''
                path = control.CONFIG/'hypr/config/keybinds.lua'
                path.parent.mkdir(parents=True)
                original = 'local mainMod = "SUPER"\nhl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty"), { locked = true })\nhl.bind("SUPER + Left", hl.dsp.focus({ direction = "left" }))\nfor i = 1, 10 do\n  hl.bind(mainMod .. " + " .. key, hl.dsp.exec_cmd("workspace " .. i))\nend\n'
                path.write_text(original)
                data = control.keybinds()
                self.assertEqual(len(data['rows']), 2)
                data['rows'][0]['key'] = 'SUPER + Y'
                data['rows'][0]['command'] = 'alacritty'
                control.save_keys(data)
                result = path.read_text()
                self.assertIn('hl.dsp.exec_cmd("alacritty"), { locked = true }', result)
                self.assertIn('hl.dsp.focus({ direction = "left" })', result)
                self.assertIn('hl.bind(mainMod .. " + " .. key,', result)
                with self.assertRaises(ValueError): control.save_keys(data)
        finally:
            control.CONFIG, control.STATE, control.run = old_config, old_state, old_run


if __name__ == '__main__':
    unittest.main()
