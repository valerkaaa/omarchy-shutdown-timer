import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The shutdown mark: the canonical power symbol, raised off the bar.
//
// Geometry is the Material Design "power" path — the same glyph Omarchy itself
// uses for shutdown (OsdModel.js maps the "shutdown" icon to U+F0425, nf-md-power).
// That shape is a ring with a 70° opening at twelve o'clock and a stem that runs
// through the opening down to the centre of the ring; leaving the stem short or
// the opening wide is what stops a hand-drawn attempt from reading as "power".
//
// Depth is built from offset copies of the same path — light above-left, shadow
// below, dark edge below-right, body on top with a vertical gradient. Deliberately
// no MultiEffect/layer: a drop-shadow shader makes Qt render the icon into an
// 88×88 offscreen texture, which bleeds over the neighbouring bar widgets and
// costs a shader for a 16-pixel mark. Four shapes are exact, stay inside the
// item's own bounds, and cost nothing.
//
// State is carried by the mark itself, never by swapping it for a warning icon:
//   idle      — plain mark
//   active    — a small dot at the lower right ("a timer is running")
//   countdown — the whole mark pulses (scale 1.0 ↔ 1.08, 600 ms)
//   paused    — two bars instead of the dot ("held")
// The caller sets `variant`; colour follows the theme (`color`), so the mark
// greys out with the bar and turns urgent during the countdown.
Item {
  id: root

  property real iconSize: Style.bar.iconFont
  property color color: Commons.Color.foreground
  property string variant: "idle"
  // "reduce motion" honouring: the shell exposes it; a static mark otherwise
  property bool animate: true
  property bool reducedMotion: false

  // 26, not 24: the bevel and shadow copies sit up to ~1.2 glyph units outside
  // the path's own 24-unit box, and dividing by 26 keeps those copies inside
  // the item instead of painting over whatever sits next to the icon.
  readonly property real s: iconSize / 26

  // Material Design "power" (U+F0425), 24×24 box
  readonly property string powerPath: "M16.56,5.44L15.11,6.89C16.84,7.94 18,9.83 18,12A6,6 0 0,1 12,18A6,6 0 0,1 6,12C6,9.83 7.16,7.94 8.88,6.88L7.44,5.44C5.36,6.88 4,9.28 4,12A8,8 0 0,0 12,20A8,8 0 0,0 20,12C20,9.28 18.64,6.88 16.56,5.44M13,3H11V13H13"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // the glyph is authored in a 24-unit box and scaled to the bar slot
  Item {
    id: mark
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: root.s

    // countdown pulse — only in that state, so an idle bar costs nothing.
    // `Animation on scale` takes the property over while it runs and leaves it
    // wherever it stopped, so reset the scale when the pulse ends.
    SequentialAnimation on scale {
      id: pulse
      running: root.variant === "countdown" && root.animate && !root.reducedMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) mark.scale = root.s
      NumberAnimation { to: root.s * 1.08; duration: 300; easing.type: Easing.InOutQuad }
      NumberAnimation { to: root.s;        duration: 300; easing.type: Easing.InOutQuad }
    }

    // ---- shadow, straight down ----
    Shape {
      x: 0
      y: 1.15
      width: 24
      height: 24
      antialiasing: true

      ShapePath {
        fillColor: Qt.rgba(0, 0, 0, 0.34)
        strokeWidth: 0
        PathSvg { path: root.powerPath }
      }
    }

    // ---- light edge, up-left ----
    Shape {
      x: -0.55
      y: -0.55
      width: 24
      height: 24
      antialiasing: true

      ShapePath {
        fillColor: Qt.rgba(1, 1, 1, 0.34)
        strokeWidth: 0
        PathSvg { path: root.powerPath }
      }
    }

    // ---- dark edge, down-right ----
    Shape {
      x: 0.55
      y: 0.55
      width: 24
      height: 24
      antialiasing: true

      ShapePath {
        fillColor: Qt.rgba(0, 0, 0, 0.55)
        strokeWidth: 0
        PathSvg { path: root.powerPath }
      }
    }

    // ---- body: vertical gradient face ----
    Shape {
      anchors.fill: parent
      antialiasing: true

      ShapePath {
        strokeWidth: 0
        fillGradient: LinearGradient {
          x1: 0
          y1: 2
          x2: 0
          y2: 22
          GradientStop { position: 0.0; color: Qt.lighter(root.color, 1.42) }
          GradientStop { position: 0.5; color: root.color }
          GradientStop { position: 1.0; color: Qt.darker(root.color, 1.28) }
        }
        PathSvg { path: root.powerPath }
      }
    }

    // ---- state badge, lower right: dot for running, two bars for paused ----
    // Drawn in the mark's own colour, slightly darkened so it reads as an
    // overlay on the ring rather than a hole in it.
    Rectangle {
      visible: root.variant === "active" || root.variant === "countdown"
      width: 6.5
      height: 6.5
      radius: width / 2
      x: 17.5
      y: 17.5
      color: Qt.darker(root.color, 1.15)
      border.width: 1.1
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
      visible: root.variant === "paused"
      width: 2.6
      height: 7.5
      radius: 1.1
      x: 15.7
      y: 16.6
      color: Qt.darker(root.color, 1.15)
      border.width: 0.9
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
      visible: root.variant === "paused"
      width: 2.6
      height: 7.5
      radius: 1.1
      x: 19.6
      y: 16.6
      color: Qt.darker(root.color, 1.15)
      border.width: 0.9
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }
  }
}
