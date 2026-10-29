import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The shutdown mark: the canonical power symbol, drawn as one stroked path.
//
// Two earlier attempts are worth remembering:
//   * Four stacked Shape copies (shadow + two bevels + gradient body) for fake
//     depth — at a 14 px slot the copies blur into each other, the ring's
//     counter fills in and the mark reads as a smudge next to crisp text.
//   * A font glyph — hinted and cheap, but every power glyph in the Nerd Font
//     set is a *solid* mark (nf-md-power, nf-fa-power_off); at bar size the
//     stroke closes up into a filled blob and the ring is gone.
//
// So: a stroked path with round caps and round joins. The stroke weight is
// derived from `iconSize` (never hairline, never fat), the caps give the soft
// corners, and there is exactly one draw per state instead of four copies.
//
// Geometry is the canonical power symbol: a ring open at twelve o'clock (70°)
// with a stem through the opening. A short stem or a wide opening stops reading
// as "power", so neither is trimmed.
//
// State is carried by the mark itself, never by swapping it for a warning icon:
//   idle      — plain mark
//   active    — a dot at the lower right ("a timer is running")
//   countdown — the mark pulses (scale 1.0 ↔ 1.08, 600 ms) and turns urgent
//   paused    — two bars instead of the dot ("held")
// The caller sets `variant`; colour follows the theme (`color`).
Item {
  id: root

  // Painted ink ≈ 0.8 × iconSize. The bar passes 16 (the shell's icon
  // canvas), which lands on the same optical size as the Nerd Font glyphs.
  property real iconSize: Style.bar.iconCanvas
  property color color: Commons.Color.foreground
  // What the state badge cuts out of the mark. It has to be the surface the
  // mark is drawn on (the bar or the popup), not a fixed black: a black ring
  // on a light bar reads as dirt around the badge instead of a clean notch.
  property color cutout: Commons.Color.bar.background
  property string variant: "idle"
  // "reduce motion" honouring: the shell exposes it; a static mark otherwise
  property bool animate: true
  property bool reducedMotion: false

  readonly property real unit: iconSize / 24                 // drawn in a 24-unit box
  readonly property real ring: 8.0 * unit
  // A hairline disappears on a 1x screen, a fat stroke closes the ring's
  // counter: the band is 1.4 units, clamped so it never drops under a pixel.
  readonly property real stroke: Math.max(1.35, 1.55 * unit)

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Item {
    id: mark
    anchors.centerIn: parent
    width: 24 * root.unit
    height: 24 * root.unit
    transformOrigin: Item.Center

    // countdown pulse — only in that state, so an idle bar costs nothing.
    // `Animation on scale` takes the property over while it runs and leaves it
    // wherever it stopped, so reset the scale when the pulse ends.
    SequentialAnimation on scale {
      running: root.variant === "countdown" && root.animate && !root.reducedMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) mark.scale = 1.0
      NumberAnimation { to: 1.08; duration: 300; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1.0;  duration: 300; easing.type: Easing.InOutQuad }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      // ring, open across the top: -55° to +235° leaves the canonical 70° gap
      ShapePath {
        strokeColor: root.color
        strokeWidth: root.stroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        PathAngleArc {
          centerX: 12 * root.unit
          centerY: 12 * root.unit
          radiusX: root.ring
          radiusY: root.ring
          startAngle: -55
          sweepAngle: 290
        }
      }

      // stem: from one ring-radius above the ring's top edge to just past the
      // centre, exactly as the canonical 24-unit power path has it (3 → 13)
      ShapePath {
        strokeColor: root.color
        strokeWidth: root.stroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 12 * root.unit
        startY: 3 * root.unit
        PathLine { x: 12 * root.unit; y: 13.2 * root.unit }
      }
    }

    // ---- state badge, lower right: dot for running, two bars for paused ----
    // Sits on the ring's lower-right shoulder and is outlined in the surface
    // colour so it cuts the mark instead of blending into it.
    Rectangle {
      readonly property real d: Math.max(5, root.iconSize * 0.30)
      visible: root.variant === "active" || root.variant === "countdown"
      width: d
      height: d
      radius: d / 2
      x: root.iconSize * 0.70
      y: root.iconSize * 0.68
      color: root.color
      border.width: Math.max(1, root.iconSize * 0.07)
      border.color: root.cutout
    }

    Row {
      readonly property real barW: Math.max(2, root.iconSize * 0.13)
      readonly property real barH: Math.max(6, root.iconSize * 0.36)
      visible: root.variant === "paused"
      x: root.iconSize * 0.60
      y: root.iconSize * 0.66
      spacing: Math.max(1, root.iconSize * 0.06)

      Repeater {
        model: 2
        Rectangle {
          width: parent.barW
          height: parent.barH
          radius: width / 2
          color: root.color
          border.width: Math.max(1, root.iconSize * 0.06)
          border.color: root.cutout
        }
      }
    }
  }
}
