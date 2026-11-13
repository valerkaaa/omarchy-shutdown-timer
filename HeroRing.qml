import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The dial: a progress ring with a minute scale, a lit head and a bloom.
//
// The language is taken from the focus (pomodoro) plugin — sixty ticks, every
// fifth one long, a gradient sweep and a head that pips outward when the state
// changes. Two differences: every colour is a theme token, and the ring is
// also the input — dragging it sets the minutes, which no timer in this
// ecosystem does.
Item {
  id: root

  property real fraction: 1.0        // 1..0, share of the time left
  property bool paused: false
  property bool running: false
  property color tint: Commons.Color.accent
  property color ink: Commons.Color.popups.text
  property real thickness: 7
  // Set by the owner while a drag is in progress: the ring then shows the
  // dragged value instead of the running one.
  property bool scrubbing: false
  property int scrubMinutes: 30
  property int scrubMax: 1440

  signal clicked()
  signal scrubStarted()
  signal scrubbed(int minutes)
  signal scrubFinished(int minutes)

  readonly property real s: Style.fontScale
  function px(n) { return Math.max(1, Math.round(n * s)) }

  readonly property real stroke: px(thickness)
  readonly property real tickBand: px(11)
  readonly property real radius: Math.max(1, Math.min(width, height) / 2 - stroke / 2 - tickBand)
  readonly property real sweep: 360 * Math.max(0, Math.min(1, root.fraction))
  readonly property real headAngle: (-90 + root.sweep) * Math.PI / 180
  readonly property real headX: width / 2 + radius * Math.cos(headAngle)
  readonly property real headY: height / 2 + radius * Math.sin(headAngle)

  // 0..1, driven by the spring: a start or a pause kicks the head outward.
  property real kick: 0
  property int kicks: 0

  SequentialAnimation {
    id: kickAnim
    NumberAnimation {
      target: root; property: "kick"; to: 1.0
      duration: 130; easing.type: Easing.OutBack; easing.overshoot: 2.6
    }
    NumberAnimation {
      target: root; property: "kick"; to: 0.0
      duration: 320; easing.type: Easing.OutCubic
    }
  }
  onRunningChanged: { kicks += 1; kickAnim.restart() }
  onPausedChanged: if (root.paused) { kicks += 1; kickAnim.restart() }

  opacity: root.paused ? 0.6 : 1.0
  Behavior on opacity { NumberAnimation { duration: 180 } }

  // ---------- bloom: the ring sits in light, not on a flat fill ----------
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: root.width / 2
        centerY: root.height / 2
        centerRadius: root.width * 0.52
        focalX: root.width / 2
        focalY: root.height / 2
        focalRadius: 0
        GradientStop { position: 0.0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.16) }
        GradientStop { position: 0.62; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.07) }
        GradientStop { position: 1.0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.0) }
      }
      startX: root.width / 2
      startY: root.height / 2 - root.width * 0.52
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.width * 0.52
        radiusY: root.width * 0.52
        startAngle: -90
        sweepAngle: 359.99
      }
    }
  }

  // ---------- minute scale ----------
  Repeater {
    id: ticks
    model: 60

    Rectangle {
      required property int index
      readonly property bool major: index % 5 === 0
      readonly property real pos: index * 6
      readonly property bool spent: pos > root.sweep + 0.5
      width: root.px(major ? 1.6 : 1.1)
      height: root.px(major ? 6.5 : 3.4)
      radius: width / 2
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, (major ? 0.34 : 0.16) * (spent ? 0.34 : 1.0))
      x: root.width / 2 - width / 2
      y: root.width / 2 - root.radius - root.stroke / 2 - root.tickBand + root.px(1)
      transform: Rotation {
        origin.x: width / 2
        origin.y: root.radius + root.stroke / 2 + root.tickBand - root.px(1)
        angle: index * 6
      }
    }
  }

  // ---------- track ----------
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: 0
        sweepAngle: 359.99
      }
    }
  }

  // ---------- sweep ----------
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: root.tint
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: -90
        sweepAngle: Math.max(0.01, root.sweep)
      }
    }
  }

  // ---------- head: the lit pip that says "here is now" ----------
  Rectangle {
    visible: root.sweep > 0.5
    width: root.px(9) + root.kick * root.px(3)
    height: width
    radius: width / 2
    x: root.headX - width / 2
    y: root.headY - height / 2
    color: root.tint
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.55)
  }

  // The angle under a point, in minutes. Public so a script can prove the
  // gesture without a pointer.
  function minutesAt(px, py) {
    var dx = px - width / 2
    var dy = py - height / 2
    var deg = Math.atan2(dy, dx) * 180 / Math.PI + 90
    if (deg < 0) deg += 360
    return Math.round(deg / 360 * root.scrubMax)
  }

  // ---------- the ring as an input ----------
  // Dragging around the dial sets the minutes: the angle under the cursor is
  // the share of the maximum. A drag that starts on the ring is a scrub; a
  // click is left to the owner (start/pause).
  MouseArea {
    id: dial
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    preventStealing: true
    property bool active: false
    property bool wasDrag: false
    property real pressX: 0
    property real pressY: 0

    onPressed: function(mouse) {
      pressX = mouse.x; pressY = mouse.y
      active = false
      wasDrag = false
    }

    onPositionChanged: function(mouse) {
      if (!pressed) return
      if (!active) {
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (Math.sqrt(dx * dx + dy * dy) < root.px(6)) return
        active = true
        wasDrag = true
        root.scrubbing = true
        root.scrubStarted()
      }
      var m = root.minutesAt(mouse.x, mouse.y)
      root.scrubMinutes = m
      root.scrubbed(m)
    }

    onClicked: if (!wasDrag) root.clicked()

    onReleased: {
      if (active) {
        root.scrubbing = false
        root.scrubFinished(root.scrubMinutes)
      }
      active = false
    }
  }
}
