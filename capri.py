"""Capri desktop pet hooks. Owns its mark so --without-halloween never strips it."""
import json
import re
import shlex

MARK = 'serpantinum-capri-v2'
TYPES = ['singleton Capri 1.0 capri/Capri.qml'] + [f'{name} 1.0 capri/{name}.qml' for name in
         ('AddonCapri', 'CapriOverlay', 'CapriEngine', 'CapriPet', 'CapriSettings')]
CHORD = 'SUPER + SHIFT + K'


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text += '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # IpcHandler "capri" must be a direct ShellRoot child. Anchored away from
    # "    Main {}", which install.patch_shell re-flows on every run.
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Capri shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonCapri {{}}\n    // END {MARK} host\n' + anchor, 1)


def patch_keybind(text, shell_qml):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = f'-- BEGIN {MARK} keybind'
    if marker in text: return text
    if f'"{CHORD}"' in text: raise ValueError('Capri shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(shell_qml)) + ' ipc call capri toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + f'hl.bind("{CHORD}", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n' + f'-- END {MARK} keybind\n'


def remove_blocks(text):
    text = re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)
    return re.sub(r'\n*^-- BEGIN ' + MARK + r' ([^\n]+)\n.*?^-- END ' + MARK + r' \1\n', '\n', text, flags=re.S | re.M)


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 capri/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}
