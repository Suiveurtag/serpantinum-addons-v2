"""Clawd desktop pet hooks. Owns its mark so --without-capri never strips it."""
import json
import re
import shlex

MARK = 'serpantinum-clawd-v2'
TYPES = ['singleton Clawd 1.0 clawd/Clawd.qml'] + [f'{name} 1.0 clawd/{name}.qml' for name in
         ('AddonClawd', 'ClawdOverlay', 'ClawdPet', 'ClawdSprite', 'ClawdMenu', 'ClawdSettings', 'ClawdCard')]
CHORD = 'SUPER + SHIFT + L'


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # IpcHandler "clawd" must be a direct ShellRoot child; same anchor as Capri.
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Clawd shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonClawd {{}}\n    // END {MARK} host\n' + anchor, 1)


def patch_keybind(text, shell_qml):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = f'-- BEGIN {MARK} keybind'
    if marker in text: return text
    if f'"{CHORD}"' in text: raise ValueError(f'Clawd shortcut {CHORD} already in use')
    command = 'quickshell -p ' + shlex.quote(str(shell_qml)) + ' ipc call clawd toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + f'hl.bind("{CHORD}", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n' + f'-- END {MARK} keybind\n'


def remove_blocks(text):
    text = re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)
    lua = re.compile(r'\n*^-- BEGIN ' + MARK + r' ([^\n]+)\n.*?^-- END ' + MARK + r' \1\n', re.S | re.M)
    while lua.search(text):
        text = lua.sub('\n', text, count=1)
    return text


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 clawd/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def resources(payload, qs):
    return [(qs/'clawd'/source.relative_to(payload), source.read_bytes()) for source in sorted(payload.rglob('*')) if source.is_file()]


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}
