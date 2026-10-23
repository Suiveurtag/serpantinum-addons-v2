"""Idempotent shell hooks for the optional native scene bridge."""
import json
import re
from pathlib import Path


def insert(text, anchor, addition):
    if addition in text:
        return text
    if text.count(anchor) != 1:
        raise ValueError('Wallpaper Engine integration anchor changed: ' + anchor[:70])
    return text.replace(anchor, anchor + addition, 1)


def singleton(text, deploy):
    script = json.dumps(str(deploy / 'scripts/wallpaper_engine.py'))
    block = '''
    // BEGIN serpantinum-wallpaper-engine
    property var externalScreens: ({})
    property var nativeRequests: []
    function syncExternal(serialized: string): void {
        try {
            const incoming = JSON.parse(serialized);
            if (!incoming || Array.isArray(incoming) || typeof incoming !== "object") return;
            const next = {};
            for (const screen of Quickshell.screens) {
                const value = incoming[screen.name];
                if (value && typeof value.source === "string" && typeof value.snapshot === "string") next[screen.name] = value;
            }
            if (JSON.stringify(root.externalScreens) !== JSON.stringify(next)) root.externalScreens = next;
        } catch (error) { console.warn("Scene synchronization failed:", error); }
    }
    function applyNextNative(): void {
        if (!root.nativeRequests.length || nativeRelease.running) return;
        nativeRelease.command = ["python3", SCRIPT, "release", root.nativeRequests[0].screen];
        nativeRelease.running = true;
    }
    Process {
        id: nativeRelease
        onExited: (code, status) => {
            const requests = root.nativeRequests.slice();
            const request = requests.shift();
            root.nativeRequests = requests;
            if (code === 0 && request) {
                if (request.clear) root.wallpaperCleared(request.screen);
                else root.wallpaperChanged(request.screen, request.path, request.transition);
            }
            else console.warn("Could not release scene output; retaining current wallpaper");
            Qt.callLater(root.applyNextNative);
        }
    }
    Process { id: sceneSync; command: ["python3", SCRIPT, "sync"]; running: true }
    FileView {
        path: Caching.getRunDir("lock") + "/locked"
        watchChanges: true
        onFileChanged: hostSync.restart()
    }
    Timer { id: hostSync; interval: 30; onTriggered: hostProcess.running = true }
    Process { id: hostProcess; command: ["python3", SCRIPT, "host"] }
    onExternalScreensChanged: {
        if (Caching.isStandalone) return;
        const screens = Object.keys(root.externalScreens);
        if (screens.length) {
            const image = root.externalScreens[screens[0]].snapshot;
            if (image) Matugen.generate(image);
        } else Matugen.generate(Caching.getCacheDir("wallpaper") + "/current_wallpaper.png");
        hostSync.restart();
    }
    // END serpantinum-wallpaper-engine
'''.replace('SCRIPT', script)
    text = re.sub(r'\n    // BEGIN serpantinum-wallpaper-engine.*?    // END serpantinum-wallpaper-engine\n', '', text, flags=re.S)
    text = insert(text, '    property var engines: ({})\n', block)
    old = '        root.wallpaperChanged(screenName, path, transition ? transition : "fade");'
    new = '''        root.nativeRequests = root.nativeRequests.concat([{screen: screenName, path: path, transition: transition || "fade"}]);
        root.applyNextNative();'''
    if new not in text:
        if text.count(old) != 1:
            raise ValueError('Wallpaper selection anchor changed')
        text = text.replace(old, new)
    clear = '        root.wallpaperCleared(screenName);'
    queued_clear = '        root.nativeRequests = root.nativeRequests.concat([{screen: screenName, clear: true}]);\n        root.applyNextNative();'
    if queued_clear not in text:
        if text.count(clear) != 1:
            raise ValueError('Wallpaper clear anchor changed')
        text = text.replace(clear, queued_clear)
    for method, field in [('getWallpaper', 'title'), ('getWallpaperPath', 'snapshot')]:
        anchor = f'\n    function {method}(screenName: string): string {{\n'
        text = insert(text, anchor, f'        if (root.externalScreens[screenName]) return root.externalScreens[screenName].{field} || "";\n')
    text = insert(text, '        target: "wallpaper"\n', '\n        function syncExternal(serialized: string): void { root.syncExternal(serialized); }\n')
    return text


def engine(text):
    text = re.sub(r'\n                // BEGIN serpantinum-wallpaper-engine.*?                // END serpantinum-wallpaper-engine\n', '', text, flags=re.S)
    text = insert(text, '                id: barWindow\n', '''
                // BEGIN serpantinum-wallpaper-engine
                readonly property bool externalScene: !!Wallpaper.externalScreens[barWindow.modelData ? barWindow.modelData.name : ""]
                visible: !externalScene
                onExternalSceneChanged: engineSceneSync.restart()
                Timer {
                    id: engineSceneSync
                    interval: 0
                    onTriggered: {
                    if (barWindow.externalScene) {
                        barWindow.stopA(); barWindow.stopB();
                        videoWarmUpTimer.stop(); transitionAnim.stop();
                        layerSnapshotA.running = false; layerSnapshotB.running = false;
                        videoSnapshotProcess.running = false;
                        Wallpaper.unregisterEngine(barWindow.modelData.name, barWindow);
                    } else {
                        Wallpaper.registerEngine(barWindow.modelData.name, barWindow);
                        if (!barWindow.playbackPaused) {
                            if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                            if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                        }
                    }
                }
                }
                // END serpantinum-wallpaper-engine
''')
    old = 'Wallpaper.registerEngine(barWindow.screen ? barWindow.screen.name : "", barWindow);'
    new = 'if (!barWindow.externalScene) ' + old
    if new not in text:
        text = text.replace(old, new)
    text = text.replace('if (barWindow.isVideo(savedPath)) {', 'if (barWindow.isVideo(savedPath) && !barWindow.externalScene) {')
    text = text.replace('if (exitCode === 0 && typeof Matugen', 'if (!barWindow.externalScene && exitCode === 0 && typeof Matugen')
    text = insert(text, '                function snapshotLayer(slot, path) {\n', '                    if (barWindow.externalScene) return;\n') if '                function snapshotLayer(slot, path) {\n' in text else text
    for layer in ('A', 'B'):
        old = f'active: barWindow.isVideo{layer}'
        text = text.replace(old, f'active: !barWindow.externalScene && barWindow.isVideo{layer}')
    return text


def blur(text, prefix):
    imported = 'import ' + json.dumps('file://' + str(prefix / 'lib/qt6/qml/Serpantinum/Wallpaper')) + ' as SceneGpu\n'
    text = insert(text, 'import QtQuick\n', imported)
    external_scene = '    readonly property bool externalScene: !snapshotMode && !!Wallpaper.externalScreens && !!Wallpaper.externalScreens[screenName]\n'
    if re.search(r'(?m)^    readonly property bool externalScene:', text):
        text = re.sub(r'(?m)^    readonly property bool externalScene: [^\n]*\n', lambda match: external_scene, text)
    else:
        text = insert(text, '    property bool useSnapshot: false\n', '\n' + external_scene)
    text = text.replace('readonly property var engine: useSnapshot ? null :', 'readonly property var engine: useSnapshot || externalScene ? null :')
    text = text.replace('readonly property var engine: snapshotMode ? null :', 'readonly property var engine: snapshotMode || externalScene ? null :')
    old = 'if (!root.engine) return slot === 0 ? root.snapshotUrl : "";'
    new = 'if (root.externalScene) return slot === 0 ? "file://" + Wallpaper.externalScreens[root.screenName].snapshot : "";\n        ' + old
    if new not in text:
        text = text.replace(old, new)
    text = text.replace('live: root.liquid && root.consumers > 0 && root.transitioning', 'live: root.liquid && root.consumers > 0 && (root.transitioning || root.externalScene)')
    text = text.replace('            visible: !sceneTexture.ready\n', '')
    source = """
    // BEGIN serpantinum-scene-texture
    readonly property bool sceneVisible: {
        for (let item = root; item; item = item.parent) {
            if (!item.visible || item.opacity <= 0.001) return false;
        }
        return true;
    }
    Item {
        id: sceneLayer
        width: root.screenWidth
        height: root.screenHeight
        Image {
            anchors.fill: parent
            source: root.externalScene ? root.newSource : ""
            sourceSize: root.textureSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        SceneGpu.GlassTexture {
            id: sceneTexture
            anchors.fill: parent
            outputName: root.screenName
            active: root.active && root.externalScene && root.sceneVisible
            visible: active
        }
    }
    ShaderEffectSource {
        id: sceneSource
        sourceItem: root.active && root.externalScene && root.sceneVisible ? sceneLayer : null
        hideSource: true
        visible: false
        live: root.active && root.externalScene && root.sceneVisible
        textureSize: root.textureSize
        smooth: true
    }
    // END serpantinum-scene-texture
"""
    text = re.sub(r'\n    // BEGIN serpantinum-scene-texture.*?    // END serpantinum-scene-texture\n', '', text, flags=re.S)
    unmarked = source.replace('    // BEGIN serpantinum-scene-texture\n', '').replace('    // END serpantinum-scene-texture\n', '')
    text = text.replace(unmarked, '')
    text = insert(text, '    property int revision: 0\n', source)
    text = text.replace('property variant newTex: root.externalScene && sceneTexture.ready ? sceneSource : newLayer', 'property variant newTex: root.externalScene ? sceneSource : newLayer')
    text = text.replace('property variant newTex: newLayer', 'property variant newTex: root.externalScene ? sceneSource : newLayer')
    return text


def prepare(pending, qs, deploy, prefix):
    transformations = {
        qs / 'singletons/theme/Wallpaper.qml': lambda text: singleton(text, deploy),
        qs / 'wallpaper/WallpaperEngine.qml': engine,
        qs / 'reusables/display/WallpaperBlur.qml': lambda text: blur(text, prefix),
    }
    for path, transform in transformations.items():
        pending[path] = transform(pending.get(path, path.read_text()))


def deploy(qs, deploy_dir, prefix):
    """Deploy only this bridge, using the addon's dated backup convention."""
    from datetime import datetime
    import os
    import shutil
    import tempfile
    pending = {}
    prepare(pending, qs, deploy_dir, prefix)
    source = Path(__file__).resolve().parent
    pending[deploy_dir / 'scripts/wallpaper_engine.py'] = (source / 'scripts/wallpaper_engine.py').read_text()
    backup = deploy_dir / 'backups' / datetime.now().strftime('%Y%m%d-%H%M%S-wallpaper')
    changed = []
    for path, text in pending.items():
        if path.exists() and path.read_text() == text:
            continue
        if path.exists():
            relative = path.relative_to(qs) if path.is_relative_to(qs) else path.relative_to(deploy_dir)
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
        try:
            with os.fdopen(fd, 'w') as stream:
                stream.write(text)
            os.chmod(temporary, 0o644)
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)
        changed.append(str(path))
    return changed, backup
