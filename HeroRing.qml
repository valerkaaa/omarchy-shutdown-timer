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
  property int scrubMax: 720
  // While a timer runs a drag is a delta from the current remainder, not an
  // absolute angle: pulling past the head adds time instead of restarting the
  // countdown from a new absolute value.
  property bool reducedMotion: false
  property bool focused: false
  property bool deltaMode: false
  property real baseMinutes: 30

  signal clicked()
  signal scrubStarted()
  signal scrubbed(int minutes)
  signal scrubFinished(int minutes)

  readonly property real s: Style.fontScale
  function px(n) { return Math.max(1, Math.round(n * s)) }

  readonly property real stroke: px(thickness)
  readonly property real tickBand: px(11)
  readonly property real radius: Math.max(1, Math.min(width, height) / 2 - stroke / 2 - tickBand)
  // A change of the time moves the arc with a 400 ms ease instead of a jump:
  // +5 minutes should be visible as a motion, not as a repaint.
  property real sweep: 360 * Math.max(0, Math.min(1, root.fraction))
  Behavior on sweep {
    enabled: !root.reducedMotion
    NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
  }
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

  // The last minute breathes: a 1.2 % scale and a stronger bloom, once per
  // second, and nothing at all in IDLE or on a long timer.
  readonly property bool alarm: root.running && !root.reducedMotion && root.fraction <= 0.02
  SequentialAnimation on scale {
    running: root.alarm
    loops: Animation.Infinite
    onRunningChanged: if (!running) root.scale = 1.0
    NumberAnimation { to: 1.008; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0;   duration: 700; easing.type: Easing.InOutSine }
  }

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
        GradientStop { position: 0.0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.14) }
        GradientStop { position: 0.62; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.05) }
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

  // The leading half of the arc is lighter: a gradient stroke is not available
  // on a ShapePath, so the same read is built from a second, shorter arc.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.rgba(1, 1, 1, 0.14)
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: -90
        sweepAngle: Math.max(0.01, root.sweep * 0.45)
      }
    }
  }

  // ---------- inner lens rings ----------
  Repeater {
    model: [0.78, 0.58]
    Rectangle {
      required property real modelData
      readonly property real d: root.radius * 2 * modelData
      width: d
      height: d
      radius: d / 2
      anchors.centerIn: parent
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
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

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.10)
      strokeWidth: root.stroke * 1.8
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

  // ---------- head: a machined knob, not a dot ----------
  // Dark centre, light rim, one specular: the same three layers the keys use,
  // at 16 px, which is what makes it read as a physical part.
  Item {
    id: knob
    visible: root.sweep > 0.5
    width: root.px(12) + root.kick * root.px(3)
    height: width
    x: root.headX - width / 2
    y: root.headY - height / 2

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.darker(root.ink, 2.4)
      border.width: Math.max(1, root.px(1.6))
      border.color: root.tint
    }
    Rectangle {
      anchors.fill: parent
      anchors.margins: Math.max(1, root.px(1.2))
      radius: width / 2
      color: root.tint
      opacity: 0.9
    }
    Rectangle {
      width: Math.max(2, root.px(2.4))
      height: width
      radius: width / 2
      x: parent.width * 0.26
      y: parent.height * 0.22
      color: Qt.rgba(1, 1, 1, 0.75)
    }
  }

  // The angle under a point, in minutes. Public so a script can prove the
  // gesture without a pointer.
  function angleAt(px, py) {
    var dx = px - width / 2
    var dy = py - height / 2
    var deg = Math.atan2(dy, dx) * 180 / Math.PI + 90
    if (deg < 0) deg += 360
    return deg
  }

  function minutesAt(px, py) {
    return Math.round(angleAt(px, py) / 360 * root.scrubMax)
  }

  // Signed shortest arc between two angles, in minutes.
  function deltaMinutes(fromDeg, toDeg) {
    var d = toDeg - fromDeg
    while (d > 180) d -= 360
    while (d < -180) d += 360
    return d / 360 * root.scrubMax
  }

  // Snap to five minutes: a 720-minute dial is two minutes per degree, which
  // is unusable without a grid.
  function snapped(m) {
    return Math.round(m / 5) * 5
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
    property real pressAngle: 0

    onPressed: function(mouse) {
      pressX = mouse.x; pressY = mouse.y
      pressAngle = root.angleAt(mouse.x, mouse.y)
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
      var raw
      if (root.deltaMode) {
        raw = root.baseMinutes + root.deltaMinutes(pressAngle, root.angleAt(mouse.x, mouse.y))
      } else {
        raw = root.minutesAt(mouse.x, mouse.y)
      }
      var m = Math.max(1, Math.min(root.scrubMax, root.snapped(raw)))
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
