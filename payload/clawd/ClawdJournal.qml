import QtQuick
import Quickshell
import "../"

// Left click on Clawd: his agent sessions as a terminal box, newest first (context % when the status line relays it).
// A row raises that session's terminal.
Item {
    id: journal
    required property var pet
    property Item anchor: null
    property real now: Date.now()
    readonly property int cols: 42
    readonly property var rows: Object.entries(Clawd.sessions).map(([key, s]) => Object.assign({ key }, s)).sort((a, b) => b.last - a.last)
    readonly property color accent: ThemeBackend.primary
    width: box.implicitWidth
    height: box.implicitHeight
    x: anchor && parent ? Math.max(8, Math.min(parent.width - width - 8, anchor.x + (anchor.width - width) / 2)) : 0
    y: anchor ? (anchor.y - height - 8 >= 8 ? anchor.y - height - 8 : anchor.y + anchor.height + 8) : 0

    function cell(text, n) { text = String(text || "—"); return text.length > n ? text.slice(0, n - 1) + "…" : text + " ".repeat(n - text.length); }
    function ago(since) {
        const s = Math.max(0, Math.round((now - since) / 1000));
        return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h";
    }
    function line(s) {
        const time = ago(s.since);
        return ({ alert: "⚠", work: "✻", idle: "✓" })[s.phase] + " " + cell(s.agent, 6) + " " + cell(s.dir, 12) + " "
            + cell(s.tool, 10) + " " + " ".repeat(Math.max(0, 4 - time.length)) + time
            + (Number.isFinite(s.ctx) ? " ".repeat(Math.max(0, 5 - String(Math.round(s.ctx)).length - 1)) + Math.round(s.ctx) + "%" : "     ");
    }

    Timer { interval: 1000; repeat: true; running: journal.visible; triggeredOnStart: true; onTriggered: journal.now = Date.now() }
    FontMetrics { id: metrics; font.family: ThemeBackend.fontFamily; font.pixelSize: 14 }
    Rectangle {
        anchors { fill: parent; leftMargin: metrics.averageCharacterWidth / 2; rightMargin: metrics.averageCharacterWidth / 2
            topMargin: metrics.height / 2; bottomMargin: metrics.height / 2 }
        color: ThemeBackend.base
        radius: 3
    }
    Column {
        id: box
        Text {
            text: "╭─ ✻ sessions " + "─".repeat(journal.cols - 11) + "╮"
            color: journal.accent
            font: metrics.font
        }
        Text {
            visible: journal.rows.length === 0
            text: "│ " + journal.cell("no sessions", journal.cols) + " │"
            color: ThemeBackend.subtext0
            font: metrics.font
        }
        Repeater {
            model: journal.rows
            Text {
                required property var modelData
                text: "│ " + journal.line(modelData) + " │"
                color: modelData.phase === "alert" ? ThemeBackend.peach : hover.containsMouse ? journal.accent : ThemeBackend.subtext0
                font: metrics.font
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Clawd.focus(parent.modelData.key); journal.pet.journalOpen = false; }
                }
            }
        }
        Text {
            text: "╰" + "─".repeat(journal.cols + 2) + "╯"
            color: journal.accent
            font: metrics.font
        }
    }
}
