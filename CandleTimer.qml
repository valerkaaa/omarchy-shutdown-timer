import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The countdown as a candle.
//
// The metaphor is literal: turning a machine off means putting a light out.
// Wax shrinks with the time left, the flame shortens as the deadline nears and
// dies at zero. Cancel does not burn the candle down — it blows it out, which
// is the one gesture the user will remember.
//
// Everything is drawn from theme tokens (no literal colour), the wax height is
// a binding on `fraction` so a tick costs no layout, and in IDLE there is no
// animation at all.
Item {
  id: root

  property real candleHeight: Style.space(96)
  // 1 — full candle, 0 — burnt out.
  property real fraction: 1.0
  property color wax: Commons.Color.foreground
  property color flame: Commons.Color.accent
  property bool reducedMotion: false
  property bool animate: true
  // A whole candle that is not burning (IDLE): wax is full, no flame.
  property bool lit: true

  readonly property real waxLevel: Math.max(0, Math.min(1, fraction))
  readonly property real width_: Math.round(candleHeight * 0.34)
  readonly property real bodyW: Math.max(6, Math.round(width_ * 0.62))
  // Never fully gone: a burnt-out candle still shows a stump, so the shape
  // does not jump to nothing at the last second.
  readonly property real bodyH: Math.round(candleHeight * (0.22 + 0.56 * waxLevel))
  readonly property real flameH: Math.round(candleHeight * (0.14 + 0.06 * waxLevel))
  readonly property real flameW: Math.round(flameH * 0.52)

  implicitWidth: width_
  implicitHeight: candleHeight

  // 0 — upright flame, 1 — blown flat. Driven by blowOut().
  property real stretch: 0
  property bool blowing: false

  function blowOut() {
    if (reducedMotion || !animate) { stretch = 1; blowing = true; return }
    blowAnimation.restart()
  }

  function relight() {
    blowAnimation.stop()
    stretch = 0
    blowing = false
    smoke.opacity = 0
  }

  onFractionChanged: if (fraction > 0.02 && blowing) relight()

  // ---------- wax ----------
  Rectangle {
    id: body
    width: root.bodyW
    height: root.bodyH
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    radius: Math.max(2, Math.round(width * 0.16))
    opacity: 0.94

    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.lighter(root.wax, 1.30) }
      GradientStop { position: 0.30; color: root.wax }
      GradientStop { position: 1.0; color: Qt.darker(root.wax, 1.30) }
    }
  }

  // Molten rim on top of the wax — the one highlight that makes the body read
  // as a solid object rather than a filled rectangle.
  Rectangle {
    width: body.width
    height: Math.max(2, Math.round(body.width * 0.14))
    x: body.x
    y: body.y - Math.round(height / 2)
    radius: Math.round(height / 2)
    color: Qt.lighter(root.wax, 1.55)
    opacity: 0.5
  }

  // ---------- wick ----------
  Rectangle {
    width: Math.max(1, Math.round(root.width_ * 0.045))
    height: Math.max(3, Math.round(root.candleHeight * 0.05))
    anchors.horizontalCenter: parent.horizontalCenter
    y: body.y - height
    color: Qt.darker(root.wax, 2.2)
    opacity: 0.85
  }

  // ---------- flame ----------
  // The halo is what makes the flame read as a light source on a dark plate
  // instead of a coloured blob: a radial gradient of the accent, no effects
  // module required.
  Rectangle {
    id: halo
    width: Math.round(root.flameW * 3.2)
    height: width
    radius: width / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: flameBox.verticalCenter
    opacity: root.lit ? 0.35 : 0
    visible: root.lit
    gradient: Gradient {
      orientation: Gradient.Vertical
      GradientStop { position: 0.0; color: Qt.rgba(root.flame.r, root.flame.g, root.flame.b, 0.55) }
      GradientStop { position: 1.0; color: Qt.rgba(root.flame.r, root.flame.g, root.flame.b, 0.0) }
    }
  }

  Item {
    id: flameBox
    width: root.flameW
    height: root.flameH
    anchors.horizontalCenter: parent.horizontalCenter
    y: body.y - root.flameH - Math.max(1, Math.round(root.candleHeight * 0.02))
    transformOrigin: Item.Bottom
    visible: root.lit && root.waxLevel > 0.001
    opacity: Math.max(0, 1 - root.stretch)
    scale: 1 + 0.9 * root.stretch
    rotation: 0

    // A slow flicker, only while the deadline is close: a 120-minute timer
    // must not animate, and IDLE must not animate at all.
    SequentialAnimation on rotation {
      running: root.animate && !root.reducedMotion && !root.blowing
               && root.waxLevel > 0.001 && root.fraction <= 0.12
      loops: Animation.Infinite
      onRunningChanged: if (!running) flameBox.rotation = 0
      NumberAnimation { to: -2.2; duration: 450; easing.type: Easing.InOutSine }
      NumberAnimation { to: 2.2;  duration: 450; easing.type: Easing.InOutSine }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      // Outer flame: a teardrop with the point at the top.
      ShapePath {
        strokeColor: "transparent"
        fillColor: Qt.rgba(root.flame.r, root.flame.g, root.flame.b, 0.55)
        startX: flameBox.width / 2
        startY: 0
        PathCubic {
          control1X: flameBox.width;        control1Y: flameBox.height * 0.45
          control2X: flameBox.width * 0.92; control2Y: flameBox.height
          x: flameBox.width / 2;            y: flameBox.height
        }
        PathCubic {
          control1X: flameBox.width * 0.08; control1Y: flameBox.height
          control2X: 0;                     control2Y: flameBox.height * 0.45
          x: flameBox.width / 2;            y: 0
        }
      }
    }

    // Inner core: smaller, brighter, the part that reads at 40 px.
    Shape {
      id: core
      anchors.fill: parent
      anchors.margins: Math.max(1, Math.round(parent.width * 0.22))
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: "transparent"
        fillColor: Qt.lighter(root.flame, 1.45)
        startX: core.width / 2
        startY: 0
        PathCubic {
          control1X: core.width;        control1Y: core.height * 0.45
          control2X: core.width * 0.92; control2Y: core.height
          x: core.width / 2;            y: core.height
        }
        PathCubic {
          control1X: core.width * 0.08; control1Y: core.height
          control2X: 0;                 control2Y: core.height * 0.45
          x: core.width / 2;            y: 0
        }
      }
    }
  }

  // ---------- smoke: only after a blow-out ----------
  Rectangle {
    id: smoke
    width: Math.max(3, Math.round(root.width_ * 0.22))
    height: width
    radius: width / 2
    anchors.horizontalCenter: parent.horizontalCenter
    y: body.y - root.flameH
    color: root.wax
    opacity: 0
    visible: opacity > 0.01
  }

  ParallelAnimation {
    id: blowAnimation
    onStarted: root.blowing = true
    NumberAnimation {
      target: root; property: "stretch"; to: 1
      duration: 200; easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: smoke; property: "opacity"; to: 0.35
      duration: 90; easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: smoke; property: "y"; to: smoke.y - root.candleHeight * 0.18
      duration: 260; easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: smoke; property: "opacity"; to: 0.0
      duration: 260; easing.type: Easing.OutCubic
    }
    onFinished: {
      root.stretch = 0
      root.blowing = false
    }
  }
}
