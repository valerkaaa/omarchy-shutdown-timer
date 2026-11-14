import QtQuick
import qs.Commons
import qs.Commons as Commons

// The countdown as a camera aperture.
//
// Six blades close as the deadline approaches and meet at the centre when the
// action fires; a cancel opens them again. It is the machine's own gesture —
// an iris closing — so it reads as "shutting down" without a candle, a flame
// or any glow. Ink only: the blades take the urgent colour for the last
// minute, nothing else in the widget changes.
//
// Painted on a Canvas rather than as six Shapes: the blades are six polygons
// whose vertices all follow `open`, and a Canvas repaints once per second for
// a 64 px figure at no measurable cost.
Item {
  id: root

  property real size: Style.space(64)
  // 1 — wide open, 0 — shut.
  property real fraction: 1.0
  property color ink: Commons.Color.popups.text
  property color alarmInk: Commons.Color.urgent
  property bool alarm: false
  property bool reducedMotion: false

  // Animated separately from `fraction` so a tick eases instead of jumping.
  property real open: Math.max(0, Math.min(1, fraction))
  Behavior on open {
    enabled: !root.reducedMotion
    NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
  }
  onOpenChanged: canvas.requestPaint()
  onAlarmChanged: canvas.requestPaint()

  readonly property color blade: root.alarm ? root.alarmInk : root.ink
  readonly property real outer: size / 2 - 1

  implicitWidth: size
  implicitHeight: size

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      var c = root.size / 2
      var R = root.outer
      var r = Math.max(0.6, R * 0.80 * root.open)
      ctx.reset()
      ctx.lineWidth = 1
      ctx.strokeStyle = Qt.rgba(root.blade.r, root.blade.g, root.blade.b, 0.45)
      ctx.fillStyle = Qt.rgba(root.blade.r, root.blade.g, root.blade.b, 0.42)

      for (var i = 0; i < 6; i++) {
        var a0 = (i * 60 - 90) * Math.PI / 180
        var a1 = ((i + 1) * 60 - 90) * Math.PI / 180
        var am = ((i * 60 + 30) - 90) * Math.PI / 180
        // The blades rotate a little as they close: an iris turns, it does
        // not just shrink.
        var turn = (1 - root.open) * 0.35
        a0 += turn; a1 += turn; am += turn
        ctx.beginPath()
        ctx.arc(c, c, R, a0, a1, false)
        ctx.lineTo(c + r * Math.cos(am), c + r * Math.sin(am))
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
      }
    }
  }

  // A hairline bezel: the aperture sits in a machined rim, not on bare glass.
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(root.blade.r, root.blade.g, root.blade.b, 0.38)
  }
}
