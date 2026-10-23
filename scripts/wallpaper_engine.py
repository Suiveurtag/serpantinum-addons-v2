#!/usr/bin/env python3
"""Synchronize the scene daemon with Serpantinum after lifecycle events."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib

HOME = Path.home()
QS = Path(os.environ.get('SERPANTINUM_HOME', HOME / '.local/share/serpantinum')) / 'src/quickshell/Shell.qml'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', HOME / '.cache')) / 'serpantinum/wallpaper'


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=15)


def copy_snapshot(source, target):
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.' + target.name)
    os.close(fd)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def running_status():
    if not shutil.which('we-layerd'):
        return None
    result = run('we-layerd', 'ctl', 'status', check=False)
    if result.returncode:
        if 'failed to connect' in result.stderr or 'failed to reach' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return tomllib.loads(result.stdout)


def active_outputs(status):
    if not status:
        return {}
    runtimes = status.get('output_runtime', {})
    if status.get('runtime', {}).get('output_name'):
        runtimes = {status['runtime']['output_name']: status}
    result = {}
    for output, state in runtimes.items():
        if status.get('outputs', {}).get(output, {}).get('disabled'):
            continue
        presentation = state.get('presentation', {})
        runtime = state.get('runtime', {})
        if presentation.get('presented', 0) > 0 and not presentation.get('last_error'):
            source = runtime.get('source', '')
            if source:
                result[output] = source
    return result


def snapshot(source, output, force=False):
    if not output or output in ('.', '..') or '/' in output or '\0' in output:
        raise ValueError('invalid output name')
    source = Path(source)
    project = json.loads((source / 'project.json').read_text())
    target = CACHE / ('we_' + output + '.png')
    stamp = CACHE / ('we_' + output + '.source')
    if force or not target.exists() or not stamp.exists() or stamp.read_text() != str(source):
        probe = HOME / '.local/libexec/we-layerd/glass-frame-probe'
        if probe.is_file():
            fd, temporary = tempfile.mkstemp(suffix='.png', dir=CACHE)
            os.close(fd)
            try:
                captured = run(str(probe), output, temporary, check=False)
                if captured.returncode == 0 and Path(temporary).stat().st_size:
                    os.replace(temporary, target)
                    stamp.write_text(str(source))
                    return {'source': str(source), 'snapshot': str(target), 'title': project.get('title', source.name)}
            finally:
                Path(temporary).unlink(missing_ok=True)
        candidates = [source / name for name in ('preview.jpg', 'preview.jpeg', 'preview.png', 'preview.gif', 'thumbnail.jpg', 'thumbnail.png')]
        preview = next((p for p in candidates if p.is_file()), None)
        if preview:
            fd, temporary = tempfile.mkstemp(suffix='.png', dir=CACHE)
            os.close(fd)
            try:
                run('ffmpeg', '-v', 'error', '-y', '-i', str(preview), '-frames:v', '1', temporary)
                os.replace(temporary, target)
                stamp.write_text(str(source))
            finally:
                Path(temporary).unlink(missing_ok=True)
        else:
            return {'source': str(source), 'snapshot': '', 'title': project.get('title', source.name)}
    return {'source': str(source), 'snapshot': str(target), 'title': project.get('title', source.name)}


def reconcile(status):
    state = {output: snapshot(source, output, force=(os.environ.get('WE_LAYERD_EVENT') == 'wallpaper_applied'
        and os.environ.get('WE_LAYERD_OUTPUT') == output)) for output, source in active_outputs(status).items()}
    for output, metadata in state.items():
        if not metadata['snapshot']:
            continue
        current = CACHE / ('current_wallpaper_' + output + '.png')
        saved = CACHE / ('.we-native_' + output + '.png')
        if current.is_file() and not saved.exists():
            shutil.copy2(current, saved)
        copy_snapshot(metadata['snapshot'], current)
    for saved in CACHE.glob('.we-native_*.png'):
        output = saved.name[len('.we-native_'):-4]
        if output not in state:
            os.replace(saved, CACHE / ('current_wallpaper_' + output + '.png'))
    current = CACHE / 'current_wallpaper.png'
    saved = CACHE / '.we-native.png'
    image = next((v['snapshot'] for v in state.values() if v['snapshot']), None)
    if image:
        if current.is_file() and not saved.exists():
            shutil.copy2(current, saved)
        copy_snapshot(image, current)
    elif saved.exists():
        os.replace(saved, current)
    run('quickshell', '-p', str(QS), 'ipc', 'call', 'wallpaper', 'syncExternal', json.dumps(state))
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('sync', 'release', 'stopped', 'host'))
    parser.add_argument('output', nargs='?', default='all')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / 'we-sync.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        status = running_status()
        if args.action == 'release' and status:
            outputs = list(status.get('outputs', {})) if args.output == 'all' else [args.output]
            for output in outputs:
                run('we-layerd', 'output-clear', output)
            status = running_status()
        if args.action == 'host':
            if status:
                locked = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))) / 'serpantinum/lock/locked'
                run('we-layerd', 'ctl', 'host-pause' if locked.exists() else 'host-resume')
            return
        reconcile(status)


if __name__ == '__main__':
    main()
