#!/usr/bin/env python3
"""Connect Clawd to Claude Code / Codex hooks.
Usage: hooks.py <status|install|uninstall> <claude|codex>  ->  {"ok": true, "data": {...}} | {"ok": false, "error": "..."}
Adds one hook group per event next to whatever is already there (Capri...), backs the file up before every write,
and only ever removes commands that run clawd-hook.js."""
import json
import os
import shlex
import shutil
import sys
from datetime import datetime
from pathlib import Path

MARK = 'clawd-hook.js'
SCRIPT = Path(__file__).resolve().parent/'hooks'/MARK
AGENTS = {
    'claude': {
        'file': lambda: Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home()/'.claude')/'settings.json',
        'events': ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'Stop', 'SessionEnd'],
        'hook': {'async': True, 'timeout': 3},
        'args': '',
    },
    'codex': {
        'file': lambda: Path(os.environ.get('CODEX_HOME') or Path.home()/'.codex')/'hooks.json',
        'events': ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd', 'Interrupt'],
        'hook': {'timeout': 3},  # Codex runs hooks synchronously; the script gives up after 500 ms
        'args': ' --agent codex',
    },
}


def ours(hook):
    return isinstance(hook, dict) and MARK in str(hook.get('command', ''))


def read(file):
    text = file.read_text() if file.is_file() else ''
    try:
        settings = json.loads(text) if text.strip() else {}
    except ValueError as error:
        raise ValueError(f'{file} is not valid JSON ({error}); nothing changed') from None
    hooks = settings.get('hooks', {}) if isinstance(settings, dict) else None
    # Never rewrite a file we do not fully understand.
    if not isinstance(hooks, dict) or any(not isinstance(groups, list) or any(not isinstance(g, dict) or not isinstance(g.get('hooks'), list) for g in groups)
                                          for groups in hooks.values()):
        raise ValueError(f'{file} has an unexpected hooks layout; nothing changed')
    return settings


def status(agent):
    spec = AGENTS[agent]
    file = spec['file']()
    settings = read(file)
    events = [event for event, groups in settings.get('hooks', {}).items() if any(ours(h) for g in groups for h in g['hooks'])]
    return {'file': str(file), 'installed': all(e in events for e in spec['events']), 'events': events}


def configure(agent, install):
    spec = AGENTS[agent]
    file = spec['file']()
    settings = read(file)
    before = json.dumps(settings, sort_keys=True)
    hooks = settings.setdefault('hooks', {})
    for event in list(hooks):
        # Drop only our command, even inside a group shared with another hook.
        kept = []
        for group in hooks[event]:
            mine = [h for h in group['hooks'] if not ours(h)]
            if len(mine) == len(group['hooks']): kept.append(group)
            elif mine: kept.append({**group, 'hooks': mine})
        if kept: hooks[event] = kept
        else: del hooks[event]
    if install:
        command = 'node ' + shlex.quote(str(SCRIPT)) + spec['args']
        for event in spec['events']:
            hooks.setdefault(event, []).append({'hooks': [{'type': 'command', 'command': command, **spec['hook']}]})
    if not hooks: del settings['hooks']
    changed = json.dumps(settings, sort_keys=True) != before
    if changed and (install or file.is_file()):
        file.parent.mkdir(parents=True, exist_ok=True)
        if file.is_file():
            shutil.copy2(file, file.with_name(f'{file.name}.clawd-backup-{datetime.now().strftime("%Y-%m-%dT%H-%M-%S-%f")}'))
        tmp = file.with_name(file.name + '.clawd-tmp')
        tmp.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + '\n')
        if file.is_file(): shutil.copymode(file, tmp)
        os.replace(tmp, file)
    return {**status(agent), 'changed': changed}


def main(argv):
    try:
        if len(argv) != 2 or argv[0] not in ('status', 'install', 'uninstall') or argv[1] not in AGENTS:
            raise ValueError('usage: hooks.py <status|install|uninstall> <claude|codex>')
        action, agent = argv
        data = status(agent) if action == 'status' else configure(agent, action == 'install')
        print(json.dumps({'ok': True, 'data': data}))
        return 0
    except (OSError, ValueError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
