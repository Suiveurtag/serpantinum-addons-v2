import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../"

// Full-screen transparent surface; input reaches only Clawd and his menu, the rest of the desktop stays clickable.
PanelWindow {
    id: overlay
    required property var pet
    readonly property var here: pet.display(screen.name)
    readonly property bool menuHere: pet.menuOpen && Clawd.screenName === screen.name
    readonly property bool journalHere: pet.journalOpen && Clawd.screenName === screen.name && !menuHere
    readonly property bool petHere: !!here && pet.width > 0 && pet.x < here.x + here.w && pet.x + pet.width > here.x
        && pet.y < here.y + here.h && pet.y + pet.height > here.y
    readonly property bool exploding: pet.blasting && petHere   // ClawdSingularity draws him meanwhile
    readonly property bool reviving: pet.mode === "revive" && Clawd.screenName === screen.name
    readonly property alias thought: thought
    readonly property alias frameBox: frameBox
    readonly property alias viewport: viewport
    readonly property alias hitBox: hitBox
    readonly property alias revival: revival
    readonly property alias menu: menu
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: menuHere
    WlrLayershell.namespace: "qs-addon-clawd"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: menuHere ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        Region { item: hitBox.visible ? hitBox : null }
        Region { item: menu.visible ? menu : null }
        Region { item: bubble.visible ? bubble : null }
        Region { item: journal.visible ? journal : null }
    }

    // frameBox = his whole frame, the anchor of everything around him; viewport = the part of it you see: minus what
    // pet.cover hides while he peeks from behind a window (a fake z-order: his layer is above every window).
    Item {
        id: frameBox
        // the press keeps its surface (Wayland implicit grab): stay mapped here while dragged onto another screen
        visible: (overlay.petHere || hit.pressed) && !overlay.pet.blastHidden
        x: overlay.here ? Math.round(overlay.pet.x - overlay.here.x) : 0
        y: overlay.here ? Math.round(overlay.pet.y - overlay.here.y) : 0
        width: body.implicitWidth
        height: body.implicitHeight
    }
    Item {
        id: viewport
        readonly property int hideL: Math.round(Math.max(0, Math.min(frameBox.width, overlay.pet.cut.l)))
        readonly property int hideR: Math.round(Math.max(0, Math.min(frameBox.width - hideL, overlay.pet.cut.r)))
        visible: frameBox.visible && width > 0
        x: frameBox.x + hideL
        y: frameBox.y
        width: frameBox.width - hideL - hideR
        height: frameBox.height
        clip: hideL > 0 || hideR > 0

        ClawdSprite {
            id: body
            x: -viewport.hideL
            width: implicitWidth
            height: implicitHeight
            visible: !overlay.reviving   // ClawdRevive draws him meanwhile
            animation: overlay.pet.animation
            mirrored: overlay.pet.mirrored
            reverse: overlay.pet.reverse
            running: false
            frame: overlay.pet.frame
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            preventStealing: true
            cursorShape: overlay.pet.dead ? Qt.ArrowCursor : pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            function at(mouse) {
                const p = mapToItem(overlay.contentItem, mouse.x, mouse.y);
                return Qt.point(p.x + overlay.here.x, p.y + overlay.here.y);
            }
            onPressed: mouse => { const p = at(mouse); overlay.pet.press(mouse.button, p.x, p.y); }
            onPositionChanged: mouse => { const p = at(mouse); overlay.pet.move(p.x, p.y); }
            onReleased: mouse => { if (mouse.button === Qt.LeftButton) { const p = at(mouse); overlay.pet.release(p.x, p.y); } }
            onCanceled: overlay.pet.release()
        }
    }

    // The petpet hand: a photo strip over Clawd, frame-locked to his petpet strips (same frame count, sprites.py).
    Image {
        readonly property var strip: Clawd.manifest && Clawd.manifest.hand || null
        visible: !!strip && viewport.visible && overlay.pet.animation.startsWith("petpet")
        x: frameBox.x - 3 * Clawd.scale
        y: frameBox.y - 6 * Clawd.scale
        width: 16 * Clawd.scale
        height: strip ? Math.round(width * strip.h / strip.w) : 0
        source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
        sourceClipRect: strip ? Qt.rect(overlay.pet.frame % strip.frames * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
    }

    // Smoke rising from his corpse, drawn above it on his pixel grid.
    Image {
        id: smoke
        readonly property var strip: Clawd.manifest && Clawd.manifest.smoke || null
        property int frame: 0
        visible: !!strip && viewport.visible && overlay.pet.mode === "dead"
        x: frameBox.x + Math.round((frameBox.width - width) / 2)
        y: frameBox.y + 9 * Clawd.scale - height
        width: strip ? strip.w * Clawd.scale : 0
        height: strip ? strip.h * Clawd.scale : 0
        source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
        sourceClipRect: strip ? Qt.rect(frame % strip.frames * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
        smooth: false
        Timer { interval: smoke.strip ? 1000 / smoke.strip.fps : 166; repeat: true; running: smoke.visible; onTriggered: smoke.frame++ }
    }

    // His revival over the live desktop: click-through (not in the mask); its end brings him back.
    ClawdRevive {
        id: revival
        anchors.fill: parent
        visible: overlay.reviving && !!overlay.here
        manifest: Clawd.manifest
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        FrameAnimation {
            running: revival.visible
            onTriggered: {
                revival.t = (Date.now() - overlay.pet.reviveAt) / 1000;
                if (revival.t >= revival.at.end) overlay.pet.revived();
            }
        }
    }

    // Region tracks only its item's own geometry, never a moving parent's, so mirror the viewport here.
    Item { id: hitBox; x: viewport.x; y: viewport.y; width: viewport.width; height: viewport.height; visible: viewport.visible }

    ClawdBubble {
        id: bubble
        anchor: frameBox
        visible: !!Clawd.bubble && overlay.petHere && !overlay.menuHere && !overlay.journalHere && !overlay.exploding
    }

    // Above his head while an agent works; deliberately not in the mask: clicks go through it.
    ClawdThought {
        id: thought
        anchor: frameBox
        visible: Clawd.thinking && overlay.petHere && !bubble.visible && !overlay.menuHere && !overlay.journalHere && !overlay.exploding && !overlay.pet.dead
    }

    ClawdJournal {
        id: journal
        pet: overlay.pet
        anchor: frameBox
        visible: overlay.journalHere && !overlay.exploding
    }

    // Several agents busy at once: how many, beside his head.
    Text {
        visible: frameBox.visible && Clawd.busyCount >= 2 && !overlay.exploding && !overlay.pet.dead
        x: frameBox.x + frameBox.width - width
        y: frameBox.y + 2 * Clawd.scale - height / 2
        text: "[" + Clawd.busyCount + "]"
        color: ThemeBackend.peach
        font.family: ThemeBackend.fontFamily; font.pixelSize: Math.round(Scaler.s(12)); font.bold: true
    }

    ClawdMenu {
        id: menu
        pet: overlay.pet
        anchor: frameBox
        visible: overlay.menuHere
    }

    HyprlandFocusGrab { windows: [overlay]; active: overlay.menuHere; onCleared: overlay.pet.menuOpen = false }
    Component.onCompleted: Clawd.mounted()
    Component.onDestruction: Clawd.unmounted()
}
