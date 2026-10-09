import QtQuick
import "../"

Item {
    id: candle
    enabled: false
    property real strength: 0.95
    // Flame is bounded and premultiplied; the ivory wick is never a text glyph.
    FogLayer {
        x: -parent.width * 0.35; y: -parent.height * 0.08
        width: parent.width * 1.7; height: parent.height * 0.83
        mode: 10; intensity: candle.strength; warmth: 1
    }
    Rectangle {
        x: parent.width * 0.46; y: parent.height * 0.63
        width: Math.max(1, parent.width * 0.08); height: parent.height * 0.13
        radius: 1; color: "#312019"; rotation: 8
    }
    Rectangle {
        x: parent.width * 0.29; y: parent.height * 0.75
        width: parent.width * 0.42; height: parent.height * 0.25; radius: width * 0.15
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#80624a" }
            GradientStop { position: 0.55; color: "#dfbd8b" }
            GradientStop { position: 1; color: "#785036" }
        }
        Rectangle { x: parent.width * 0.65; y: 1; width: 2; height: parent.height * 0.5; radius: 1; color: "#eacf9e" }
    }
}
