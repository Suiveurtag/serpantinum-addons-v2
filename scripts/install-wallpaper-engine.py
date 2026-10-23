#!/usr/bin/env python3
"""Install the pinned local scene runtime and bridge without system package changes."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import wallpaper_engine


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=Path.home() / 'Projects/we-layerd-serpantinum')
    args = parser.parse_args()
    home = Path.home()
    prefix = home / '.local'
    engine = args.engine.resolve()
    runtime = prefix / 'libexec/we-layerd'
    libraries = prefix / 'lib/we-layerd'
    artifacts = {
        engine / 'target/release/we-layerd': runtime / 'we-layerd',
        engine / 'target/release/we-gui': runtime / 'we-gui',
        engine / 'target/we-renderer-upstream/install/lib/libwallpaper-engine-renderer.so': prefix / 'lib/libwallpaper-engine-renderer.so',
        engine / '.deps/dxc/lib/libdxcompiler.so': libraries / 'libdxcompiler.so',
        engine / '.deps/dxc/lib/libdxil.so': libraries / 'libdxil.so',
        engine / '.deps/xdo/usr/lib/libxdo.so.4': libraries / 'libxdo.so.4',
    }
    for plugin in ('isomp4', 'matroska', 'avi', 'wavparse', 'audioparsers'):
        source = engine / '.deps/gstreamer/usr/lib/gstreamer-1.0' / ('libgst' + plugin + '.so')
        if source.is_file():
            artifacts[source] = libraries / 'gstreamer-1.0' / source.name
    for source in artifacts:
        if not source.is_file():
            raise SystemExit('Missing built dependency: ' + str(source))
    nodes = []
    for status in Path('/sys/class/drm').glob('card*-*/status'):
        if status.read_text().strip() != 'connected':
            continue
        card = status.parent.name.split('-')[0]
        data = (Path('/sys/class/drm') / card / 'device/uevent').read_text()
        slot = next((line.split('=', 1)[1] for line in data.splitlines() if line.startswith('PCI_SLOT_NAME=')), '')
        node = Path('/dev/dri/by-path') / ('pci-' + slot + '-render')
        if node.exists():
            nodes.append(str(node))
    if not nodes or len(set(nodes)) != 1:
        raise SystemExit('Cannot select a single rendering GPU for the connected outputs')
    native = ROOT / 'native/wallpaper-bridge'
    build = native / 'build'
    subprocess.run(['cmake', '-S', str(native), '-B', str(build), '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], check=True)
    subprocess.run(['cmake', '--build', str(build), '--parallel', '3'], check=True)
    subprocess.run(['ctest', '--test-dir', str(build), '--output-on-failure'], check=True)
    stage = build / 'install'
    subprocess.run(['cmake', '--install', str(build), '--prefix', str(stage)], check=True)
    for native_file in stage.rglob('*'):
        if native_file.is_file():
            artifacts[native_file] = prefix / native_file.relative_to(stage)
    artifacts[build / 'glass-frame-probe'] = runtime / 'glass-frame-probe'
    backup = home / '.local/share/serpantinum-addons-v2/backups' / datetime.now().strftime('%Y%m%d-%H%M%S-wallpaper-runtime')
    for source, target in artifacts.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and source.read_bytes() == target.read_bytes():
            continue
        if target.exists():
            saved = backup / target.relative_to(home)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
        temporary = target.with_name('.' + target.name + '.new')
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
    for name in ('we-layerd', 'we-gui'):
        command = '#!/bin/sh\n# serpantinum-wallpaper-engine\n'
        command += 'export LD_LIBRARY_PATH=' + shlex.quote(str(libraries)) + '${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\n'
        command += 'export GST_PLUGIN_PATH_1_0=' + shlex.quote(str(libraries / 'gstreamer-1.0')) + '${GST_PLUGIN_PATH_1_0:+:$GST_PLUGIN_PATH_1_0}\n'
        if name == 'we-layerd':
            command += 'export SERPANTINUM_GPU_BRIDGE=' + shlex.quote(str(prefix / 'lib/libwe-glass-export.so')) + '\n'
            command += 'export SERPANTINUM_DRM_DEVICE=' + shlex.quote(nodes[0]) + '\n'
        if name == 'we-gui':
            command += 'export SERPANTINUM_SCENES_ONLY=1\n'
        command += 'exec ' + shlex.quote(str(runtime / name)) + ' "$@"\n'
        target = prefix / 'bin' / name
        if target.exists() and 'serpantinum-wallpaper-engine' not in target.read_text(errors='replace'):
            raise SystemExit('Existing launcher is not owned by this integration: ' + str(target))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(command)
        target.chmod(0o755)
    script = home / '.local/share/serpantinum-addons-v2/scripts/wallpaper_engine.py'
    config = home / '.config/we-layerd/config.toml'
    if not config.exists():
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text('''[renderer]
fps = 60
max_fps = 60
muted = false
prefer_dmabuf = true
allow_shm_fallback = false
[integrations]
media = true
audio_spectrum = true
[rules]
fullscreen = "pause"
maximized = "pause"
[hooks.wallpaper_applied]
command = "python3"
args = [SCRIPT, "sync"]
[hooks.wallpaper_released]
command = "python3"
args = [SCRIPT, "sync"]
[outputs."DP-1"]
disabled = true
[outputs."HDMI-A-1"]
disabled = true
'''.replace('SCRIPT', json.dumps(str(script))))
    unit = home / '.config/systemd/user/we-layerd.service'
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text('''[Unit]
Description=Wallpaper Engine scenes for Serpantinum
PartOf=graphical-session.target
After=graphical-session-pre.target
ConditionPathExists=%h/.config/we-layerd/config.toml
[Service]
Type=simple
ExecStart=%h/.local/bin/we-layerd run --config %h/.config/we-layerd/config.toml
ExecStopPost=-/usr/bin/python3 %h/.local/share/serpantinum-addons-v2/scripts/wallpaper_engine.py stopped
Restart=on-failure
RestartSec=2
[Install]
WantedBy=graphical-session.target
''')
    desktop = prefix / 'share/applications/serpantinum-wallpaper-engine.desktop'
    desktop.parent.mkdir(parents=True, exist_ok=True)
    desktop.write_text('[Desktop Entry]\nType=Application\nName=Wallpaper Engine Scenes\nComment=Wallpaper Engine scenes for Serpantinum\nExec=' + str(prefix / 'bin/we-gui') + '\nIcon=preferences-desktop-wallpaper\nCategories=Settings;DesktopSettings;\nTerminal=false\n')
    qs = home / '.local/share/serpantinum/src/quickshell'
    changed, shell_backup = wallpaper_engine.deploy(qs, home / '.local/share/serpantinum-addons-v2', prefix)
    print('Bridge shell files:', len(changed), 'Backup:', shell_backup)
    subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    subprocess.run(['systemctl', '--user', 'enable', 'we-layerd.service'], check=True)
    # The caller restarts the shell and starts the daemon after validating deployment.

if __name__ == '__main__':
    main()
