import QtQuick
import qs.Commons
import qs.Commons as Commons

// A machined key: the one control the whole popup is built from.
//
// The point is that every key carries its role in its material, not only in
// its label — a filled primary, a lit selected chip, a ghost secondary and a
// warm danger key are four different surfaces, not four identical rectangles
// with different words. Depth comes from two one-pixel edges (light on top,
// shade below) and a gradient inside the plate, all derived from theme tokens.
Item {
  id: root

  property string text: ""
  property string subText: ""
  // primary — filled with the accent, the single strongest object on screen
  // selected — lit but not filled (a chosen chip or segment)
  // ghost    — secondary, reads as a plate
  // danger   — the cancel key
  property string role: "ghost"
  property color ink: Commons.Color.popups.text
  property color accentColor: Commons.Color.accent
  property color surface: Commons.Color.popups.background
  property color dangerColor: Commons.Color.urgent
  property int fontSize: Style.font.bodySmall
  property bool hasCursor: false
  property bool bold: false

  signal clicked()

  readonly property bool primary: role === "primary"
  readonly property bool selected: role === "selected"
  readonly property bool danger: role === "danger"

  // Text colour per role, contrast-checked against the surface it sits on.
  readonly property color labelColor: {
    if (primary) return Commons.Color.popups.background
    if (danger) return dangerColor
    if (selected) return accentColor
    return ink
  }

  implicitHeight: primary ? Style.space(40) : Style.space(28)
  implicitWidth: label.implicitWidth + Style.space(16)
  height: implicitHeight

  Rectangle {
    id: plate
    anchors.fill: parent
    radius: Math.round(Style.cornerRadius * 0.85)
    border.width: 1
    border.color: {
      if (primary) return Qt.lighter(root.accentColor, 1.25)
      if (root.selected) return root.accentColor
      if (root.danger) return Qt.rgba(root.dangerColor.r, root.dangerColor.g, root.dangerColor.b, 0.55)
      return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, mouse.containsMouse ? 0.26 : 0.13)
    }

    gradient: Gradient {
      orientation: Gradient.Vertical
      // Primary: three stops, light at the top and deep at the base, the
      // gradient face the focus plugin uses for its one action.
      GradientStop {
        position: 0.0
        color: {
          if (root.primary) return Qt.lighter(root.accentColor, 1.32)
          if (root.selected) return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
          return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.075)
        }
      }
      GradientStop {
        position: 0.45
        color: {
          if (root.primary) return root.accentColor
          if (root.selected) return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
          return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.055)
        }
      }
      GradientStop {
        position: 1.0
        color: {
          if (root.primary) return Qt.darker(root.accentColor, 1.12)
          if (root.selected) return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
          return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04)
        }
      }
    }
  }

  // Top light edge: the whole trick. One pixel of lifted colour makes the
  // plate read as a raised key instead of a filled rectangle.
  Rectangle {
    anchors.left: plate.left
    anchors.right: plate.right
    anchors.top: plate.top
    anchors.margins: 1
    height: 1
    radius: 1
    color: root.primary
           ? Qt.rgba(1, 1, 1, 0.28)
           : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
  }

  // Bottom shade, same idea in reverse.
  Rectangle {
    anchors.left: plate.left
    anchors.right: plate.right
    anchors.bottom: plate.bottom
    anchors.margins: 1
    height: 1
    radius: 1
    color: root.primary
           ? Qt.rgba(0, 0, 0, 0.18)
           : Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 0.9)
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.labelColor
    font.family: Style.font.family
    font.pixelSize: root.fontSize
    font.bold: root.bold || root.primary || root.selected
    elide: Text.ElideRight
    width: Math.min(implicitWidth, root.width - Style.space(8))
    horizontalAlignment: Text.AlignHCenter
  }

  // Keyboard cursor: an outline, never a colour change, so the role of the
  // key stays readable while the cursor walks over it.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -2
    radius: plate.radius + 2
    color: "transparent"
    border.width: 1
    border.color: root.hasCursor ? root.accentColor : "transparent"
    visible: root.hasCursor
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: pressAnimation.restart()
    onClicked: root.clicked()
  }

  SequentialAnimation {
    id: pressAnimation
    NumberAnimation { target: plate; property: "scale"; to: 0.965; duration: 70; easing.type: Easing.OutCubic }
    NumberAnimation { target: plate; property: "scale"; to: 1.0; duration: 110; easing.type: Easing.OutCubic }
  }
}
