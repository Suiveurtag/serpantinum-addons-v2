import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"
import "js/world.mjs" as World

// What Clawd knows of the desktop, in global logical px; the only owner of his Hyprland sockets (windows, cursor).
// Windows come from the raw socket (j/clients): Hyprland.toplevels keeps closed windows. Polled every 240 ms (60 ms
// while he rides a window), plus filtered raw events; low motion: events + a 3 s heartbeat; asleep: events only.
// Without Hyprland (fixtures) inject({clients, monitors, screens, pointer}) feeds the same path.
Scope {
    id: world
    property var pet: null
    readonly property bool hypr: Hyprland.requestSocketPath !== ""
    readonly property bool live: Clawd.world
    readonly property bool asleep: !!pet && pet.mode === "sleep"
    property var fake: null            // injected {clients, monitors, screens}
    property var clients: []           // last j/clients
    property bool fed: false           // clients arrived at least once since the world was turned on
    property var wins: []              // World.windows: on screen, front first
    property var ledges: []            // World.ledges: window tops + one floor per display
    property var pointer: null         // global cursor
    property int refreshes: 0          // snapshots taken (IPC state, debugging)
    property var shown: ({})           // id -> rect of the windows on screen at the last snapshot
    property var mapped: ({})          // id -> rect of every mapped window (open/close, whatever the workspace)
    property string focused: ""
    property var spaces: ({})          // display -> active workspace
    property bool primed: false        // first snapshot taken: later differences are events
    property string clientBuffer: ""
    property string cursorBuffer: ""
    // events that never move a window (the Claude Code spinner rewrites the kitty title all the time)
    readonly property var ignored: ["windowtitle", "windowtitlev2", "activelayout", "submap", "bell", "screencast", "screencastv2"]
    readonly property var displays: {
        const native = fake && fake.monitors ? fake.monitors : hypr ? Hyprland.monitors.values.map(m => ({ name: m.name, x: m.x, y: m.y,
            activeWorkspace: m.activeWorkspace ? { id: m.activeWorkspace.id } : null, lastIpcObject: m.lastIpcObject })) : [];
        const screens = fake && fake.screens ? fake.screens : Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height }));
        return World.monitors(screens, native);
    }
    signal windowOpened(string id, var rect)
    signal windowClosed(string id, var rect)
    signal focusMoved(string id)
    signal workspaceSwitched(string monitor)
    signal updated()

    function win(id) { return wins.find(w => w.id === id) || null; }
    function ledge(id) { return ledges.find(l => l.id === id) || null; }

    // One j/clients request at a time; readClients() takes the snapshot.
    function fetch() { if (hypr && live && !clientSocket.connected) clientSocket.connected = true; }
    function kick() { if (live && !debounce.running) debounce.start(); }

    function snapshot() {
        refreshes++;
        const ds = displays;
        let next = [];
        if (live) {
            const minimized = {};
            if (hypr) for (const t of Hyprland.toplevels.values) if (t.wayland && t.wayland.minimized) minimized["0x" + t.address.replace(/^0x/, "")] = true;
            next = World.windows(clients, ds, minimized);
        }
        const byId = {}, all = {};
        for (const w of next) byId[w.id] = { x: w.x, y: w.y, w: w.w, h: w.h, display: w.display };
        if (live) for (const c of clients) if (c && c.address && c.at && c.size && c.mapped !== false) all[c.address] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] };
        const front = live ? clients.find(c => c && c.focusHistoryID === 0) : null;
        const focus = front ? front.address : "";
        const ws = {};
        for (const d of ds) ws[d.id] = d.workspace;
        if (JSON.stringify(next) !== JSON.stringify(wins)) wins = next;
        const flat = World.ledges({ wins: next, widgets: [], displays: ds, petW: pet ? pet.width : 0, petH: pet ? pet.height : 0 });
        if (JSON.stringify(flat) !== JSON.stringify(ledges)) ledges = flat;
        const was = { shown, mapped, focused, spaces, primed };
        shown = byId; mapped = all; focused = focus; spaces = ws;
        primed = live && fed;
        if (was.primed && primed) {
            // a window really opened or closed (not just another workspace showing up), and only the visible ones
            const change = World.diff(was.mapped, all);
            for (const id of change.opened) if (byId[id]) windowOpened(id, byId[id]);
            for (const c of change.closed) if (was.shown[c.id]) windowClosed(c.id, was.shown[c.id]);
            if (focus && focus !== was.focused && byId[focus]) focusMoved(focus);
            for (const d of ds) if (was.spaces[d.id] !== undefined && was.spaces[d.id] !== d.workspace) workspaceSwitched(d.id);
        }
        updated();
    }

    // Fixtures only: plays Hyprland. Returns false when the real one is there.
    function inject(data) {
        if (hypr || !data) return false;
        const next = Object.assign({}, fake || {});
        for (const k of ["monitors", "screens"]) if (data[k] !== undefined) next[k] = data[k];
        fake = next;
        if (data.pointer !== undefined) pointer = data.pointer;
        if (Array.isArray(data.clients)) { clients = data.clients; fed = true; }
        snapshot();
        return true;
    }

    onLiveChanged: {
        primed = false;
        fed = !hypr && clients.length > 0;
        Qt.callLater(snapshot);
        fetch();
    }
    onDisplaysChanged: Qt.callLater(snapshot)
    Component.onCompleted: { snapshot(); fetch(); }

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event && world.ignored.indexOf(event.name) < 0) world.kick(); }
    }
    Connections {
        target: world.pet
        function onHeightChanged() { Qt.callLater(world.snapshot); }
    }
    // a burst of events -> one fetch
    Timer { id: debounce; interval: 40; onTriggered: world.fetch() }
    Timer {
        interval: world.pet && world.pet.riding ? 60 : 240; repeat: true
        running: world.hypr && world.live && !!world.pet && !Clawd.lowMotion && !world.asleep
        onTriggered: world.fetch()
    }
    // low motion; or asleep on a window, so he still falls if it is dragged away
    Timer {
        interval: 3000; repeat: true
        running: world.hypr && world.live && !!world.pet && (Clawd.lowMotion || world.asleep && !!world.pet.support)
        onTriggered: world.fetch()
    }

    function readClients() {
        try {
            const list = JSON.parse(clientBuffer);
            clientBuffer = "";
            clientSocket.connected = false;
            if (!Array.isArray(list)) return;
            clients = list;
            fed = true;
            snapshot();
        } catch (error) { if (clientBuffer.length > 8388608) { clientBuffer = ""; clientSocket.connected = false; } } // The JSON may be split across reads.
    }
    Socket {
        id: clientSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { world.clientBuffer += data; world.readClients(); } }
        onConnectedChanged: {
            if (connected) { world.clientBuffer = ""; write("j/clients"); flush(); }
            else if (world.clientBuffer) world.readClients();
        }
    }

    function readCursor() {
        try {
            const p = JSON.parse(cursorBuffer);
            if (Number.isFinite(p.x) && Number.isFinite(p.y)) pointer = { x: p.x, y: p.y };
            cursorBuffer = "";
            cursorSocket.connected = false;
        } catch (error) { if (cursorBuffer.length > 4096) cursorBuffer = ""; } // The JSON may be split across reads.
    }
    Socket {
        id: cursorSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { world.cursorBuffer += data; world.readCursor(); } }
        onConnectedChanged: {
            if (connected) { world.cursorBuffer = ""; write("j/cursorpos"); flush(); }
            else if (world.cursorBuffer) world.readCursor();
        }
    }
    Timer {
        interval: 200; repeat: true
        running: world.hypr && !Clawd.lowMotion && !!world.pet && !world.asleep
        onTriggered: if (!cursorSocket.connected) cursorSocket.connected = true
    }
}
