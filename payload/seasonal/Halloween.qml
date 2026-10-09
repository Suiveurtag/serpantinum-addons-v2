pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: night
    readonly property bool activeSeason: Config.getSetting("addonsV2Halloween", false)
    readonly property bool animationEnabled: activeSeason && !Config.getSetting("general.performance", false)
    // Colors are presentation only. The wallpaper/preset palette stays untouched.
    readonly property var colors: ({
        base: "#171216", mantle: "#100d11", crust: "#0c0a0d",
        surface0: "#2b2026", surface1: "#403037", surface2: "#59454a",
        overlay0: "#827078", overlay1: "#a18c94", overlay2: "#bdabb1",
        text: "#efe5dc", subtext0: "#b4a5a9", subtext1: "#d1c0bf",
        mauve: "#ba938a", pink: "#bd8095", maroon: "#bb707b",
        peach: "#d59a68", yellow: "#dec397", red: "#d08480",
        blue: "#a5afc3", sapphire: "#8aacc0", teal: "#98b5b0", green: "#a6b396"
    })
    readonly property color ember: "#cd7745"
    readonly property color candle: "#e9b77c"
    readonly property color moonlight: "#acb3cb"
    readonly property color vapor: "#9d8caa"
    readonly property int enterDuration: 620
    readonly property int leaveDuration: 440
    readonly property real mistIntensity: 0.28
    readonly property real hearthIntensity: 0.48
    readonly property real webIntensity: 0.13
    readonly property int burstCooldown: 1600
    readonly property int hoverBurstInterval: 4200
    // Palette selection belongs to the normal Theme tab, independently of FX.
    function presentColor(key, normalColor) { return normalColor; }
    readonly property url artwork: Qt.resolvedUrl("assets/halloween-moon.png")

    // Lifetime accounting also makes OFF/hidden behavior observable through IPC.
    property int instances: 0
    property int ambientUsers: 0
    property real phase: 0
    property double lastBurst: 0
    property int burstsStarted: 0
    property int hoverLoops: 0
    property bool clockReady: false
    property bool introRunning: false
    property int introsStarted: 0
    function ignite() {
        if (!clockReady || !animationEnabled || introRunning) return;
        introsStarted++; introRunning = true; introLifetime.restart();
    }
    Timer { id: introLifetime; interval: 4050; onTriggered: night.introRunning = false }
    function syncAmbientClock() {
        if (!clockReady) return;
        if (!activeSeason) { ambientClock.stop(); return; }
        if (!ambientClock.running) ambientClock.start();
        if (!animationEnabled || ambientUsers === 0) {
            if (!ambientClock.paused) ambientClock.pause();
        } else if (ambientClock.paused) ambientClock.resume();
    }
    onActiveSeasonChanged: {
        syncAmbientClock();
        if (activeSeason) Qt.callLater(ignite);
        else { introLifetime.stop(); introRunning = false; }
    }
    onAnimationEnabledChanged: {
        syncAmbientClock();
        if (!animationEnabled) { introLifetime.stop(); introRunning = false; }
    }
    onAmbientUsersChanged: syncAmbientClock()
    Component.onCompleted: { clockReady = true; syncAmbientClock(); Qt.callLater(ignite); }
    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }
    function requestClock(active) { ambientUsers = Math.max(0, ambientUsers + (active ? 1 : -1)); }
    function allowBurst() {
        if (!animationEnabled || Date.now() - lastBurst < burstCooldown) return false;
        lastBurst = Date.now();
        burstsStarted++;
        return true;
    }
    NumberAnimation {
        id: ambientClock
        target: night; property: "phase"
        // Linear time drives curved paths/noise; visible motion is eased separately.
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite
    }
    IpcHandler {
        target: "halloween"
        function setEnabled(value: bool): void { Config.setSetting("addonsV2Halloween", value); }
        function status(): string {
            return JSON.stringify({enabled: night.activeSeason, animationEnabled: night.animationEnabled,
                instances: night.instances, ambientUsers: night.ambientUsers,
                clockRunning: ambientClock.running && !ambientClock.paused, paletteTransitionRunning: false,
                selectedTheme: Config.getSetting("theme", {}).activePreset || "",
                burstsStarted: night.burstsStarted, hoverLoops: night.hoverLoops,
                introRunning: night.introRunning, introsStarted: night.introsStarted,
                normalPaletteMatched: Object.keys(night.colors).every(function(key) {
                    return ThemeBackend[key].toString() === ThemeBackend["_normal" + key].toString();
                })});
        }
    }
}
