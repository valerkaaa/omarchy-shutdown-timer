import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup body: the action row, the dial, the keys, the tray and the
// launch key. It is one component so Panel.qml stays the bar widget and the
// keyboard/IPC surface, and this file owns the layout.
//
// `host` is the Panel root (state, actions, colours); `service` is its
// Service instance. Everything local — the dial, the figure, the sections —
// is an id inside this file.
Column {
  id: content

  property Item host
  property var service

  spacing: Style.space(12)

  // The pieces Panel's IPC and diagnostics need from the layout.
  readonly property Item dialItem: dial
  readonly property Item heroItem: hero
  readonly property int figurePixels: heroFigure.font.pixelSize
  readonly property int aperturePixels: dialBox.width
  readonly property Item labelsItem: heroLabels
  readonly property Item buttonsItem: heroButtons

  function minutesAt(px, py) { return dial.minutesAt(px, py) }

  function wheelOnDial(delta) {
    var step = (delta > 0 ? 1 : -1) * (host.customMinutes >= 1 ? 1 : 0)
    host.customMinutes = Math.max(1, Math.min(720, Math.round(host.customMinutes) + step))
  }

  function focusExact() {
    mmField.forceActiveFocus()
  }

  function bump(field, delta) {
    var v = parseInt(field.text, 10)
    if (isNaN(v)) v = 0
    field.text = String(Math.max(0, v + delta))
  }

  // The two boxes: minutes × 60 + seconds. The colon is printed, never typed.
  function debugBoxes(mm, ss) {
    mmField.text = String(mm)
    ssField.text = String(ss)
    submitBoxes()
  }

  function submitBoxes() {
    var mm = parseInt(mmField.text, 10)
    var ss = parseInt(ssField.text, 10)
    if (isNaN(mm)) mm = Math.round(host.customMinutes)
    if (isNaN(ss)) ss = 0
    var secs = mm * 60 + ss
    if (secs < 5) return
    service.setTimerSeconds(secs, host.selectedAction)
    mmField.text = ""
    ssField.text = ""
  }

  // "1" → 60 s, "1:30" → 90 s, "30s" → 30 s. Anything under five seconds is
  // refused: the overlay would eat it.
  function submitExact(raw) {
    var t = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
    if (t === "") return
    var secs = 0
    if (t.indexOf(":") >= 0) {
      var parts = t.split(":")
      for (var i = 0; i < parts.length; i++) {
        var v = parseInt(parts[i], 10)
        if (isNaN(v)) return
        secs = secs * 60 + v
      }
    } else if (/^[0-9]+s$/.test(t)) {
      secs = parseInt(t, 10)
    } else if (/^[0-9]+$/.test(t)) {
      secs = parseInt(t, 10) * 60
    } else {
      return
    }
    if (secs < 5) return
    service.setTimerSeconds(secs, host.selectedAction)
  }
  function scrubMax() { return dial.scrubMax }

          // ---- action: four segments, no dropdown, no section header ----
          Row {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { value: "poweroff",  label: host.tr("action.poweroff") },
                { value: "reboot",    label: host.tr("action.reboot") },
                { value: "suspend",   label: host.tr("action.suspend") },
                { value: "hibernate", label: host.tr("action.hibernate") }
              ]

              delegate: Key {
                required property var modelData
                width: (actionRow.width - Style.space(24) - Style.space(30)) / 4
                text: modelData.label
                role: "tab"
                selected: host.selectedAction === modelData.value
                uppercase: true
                tracking: 0.6
                ink: host.selectedAction === modelData.value ? host.popupAccent : host.popupText
                accentColor: host.popupAccent
                surface: host.popupSurface
                fontSize: Style.font.bodySmall
                hasCursor: host.cursorActive && host.focusSection === "action"
                           && host.actionOptions.indexOf(host.selectedAction) === index
                onClicked: host.selectedAction = modelData.value
              }
            }

            Key {
              width: Style.space(34)
              text: "✕"
              role: "ghost"
              ink: host.popupText
              accentColor: host.popupAccent
              surface: host.popupSurface
              fontSize: Style.font.bodySmall
              onClicked: host.close()
            }
          }

          // ---- hero: the dial, the figure, the escape hatches ----
          // A lit plate with the accent in it (top light, deep base), a minute
          // scale around the edge and the figure on the dial's own axis. The
          // ring is also the input: drag it to set the minutes.
          Rectangle {
            id: hero
            width: parent.width
            implicitHeight: heroColumn.implicitHeight + Style.space(52)
            radius: Math.round(Style.cornerRadius * 1.8)
            border.width: 1
            border.color: Qt.rgba(host.popupAccent.r, host.popupAccent.g, host.popupAccent.b, 0.12)

            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.lighter(host.popupSurface, 1.16) }
              GradientStop { position: 0.55; color: host.popupSurface }
              GradientStop { position: 1.0; color: Qt.darker(host.popupSurface, 1.14) }
            }

            // The accent wash: the plate is not grey, it belongs to the state.
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: hero.radius - 1
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(host.popupAccent.r, host.popupAccent.g, host.popupAccent.b, 0.20) }
                GradientStop { position: 0.6; color: Qt.rgba(host.popupAccent.r, host.popupAccent.g, host.popupAccent.b, 0.05) }
                GradientStop { position: 1.0; color: Qt.rgba(host.popupAccent.r, host.popupAccent.g, host.popupAccent.b, 0.10) }
              }
            }

            // One-pixel specular along the top edge: the line that makes the
            // plate read as lit rather than filled.
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(3)
              height: 1
              radius: 1
              color: Qt.rgba(1, 1, 1, 0.30)
            }

            // A hairline grid, barely there: the plate is a device surface, not a
            // flat card. Static, so it costs nothing.
            Repeater {
              model: [0.25, 0.5, 0.75]
              Rectangle {
                required property real modelData
                x: Math.round(hero.width * modelData)
                y: 0
                width: 1
                height: hero.height
                color: Qt.rgba(host.popupText.r, host.popupText.g, host.popupText.b, 0.045)
              }
            }
            Repeater {
              model: [0.33, 0.66]
              Rectangle {
                required property real modelData
                x: 0
                y: Math.round(hero.height * modelData)
                width: hero.width
                height: 1
                color: Qt.rgba(host.popupText.r, host.popupText.g, host.popupText.b, 0.045)
              }
            }

            // Dust: a few static specks at low opacity. Static on purpose — a
            // particle field that animates is a battery tax for decoration.
            Repeater {
              model: [[0.10, 0.16, 1], [0.90, 0.14, 1], [0.08, 0.88, 1],
                      [0.92, 0.86, 1], [0.50, 0.06, 1]]
              Rectangle {
                required property var modelData
                x: Math.round(hero.width * modelData[0])
                y: Math.round(hero.height * modelData[1])
                width: modelData[2] + 1
                height: width
                radius: width / 2
                color: Qt.rgba(host.popupAccent.r, host.popupAccent.g, host.popupAccent.b, 0.13)
              }
            }

            // HUD corners: the panel reports its own state the way a device
            // does — small caps, monospace, letterspaced, muted.
            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              textFormat: Text.PlainText
              text: "SYS_STAT: " + service.status
              color: host.popupText
              opacity: 0.68
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1.0
            }
            Text {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              textFormat: Text.PlainText
              text: "AUTO-CALIBRATION: " + (service.ambientFade ? "ON" : "OFF")
              color: service.ambientFade ? host.popupAccent : host.popupText
              opacity: service.ambientFade ? 0.9 : 0.62
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1.0
            }
            Text {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              textFormat: Text.PlainText
              text: "T-" + Model.formatTime(service.status === "IDLE" ? host.customMinutes * 60 : service.timeLeft)
              color: host.popupText
              opacity: 0.68
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1.0
            }
            Text {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              textFormat: Text.PlainText
              text: "TARGET " + host.targetClock
              color: host.popupText
              opacity: 0.68
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1.0
            }

            // Quick times sit around the dial, three on each side, so the
            // ring stays the only thing in the centre.
            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Repeater {
                model: host.quickPresets.slice(0, 3)
                delegate: Key {
                  required property int modelData
                  width: Style.space(52)
                  height: Style.space(26)
                  text: String(modelData)
                  role: host.customMinutes === modelData ? "selected" : "ghost"
                  ink: host.popupText
                  accentColor: host.popupAccent
                  surface: host.popupSurface
                  fontSize: Style.font.bodySmall
                  onClicked: host.customMinutes = modelData
                }
              }
            }

            Column {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Repeater {
                model: host.quickPresets.slice(3, 6)
                delegate: Key {
                  required property int modelData
                  width: Style.space(52)
                  height: Style.space(26)
                  text: String(modelData)
                  role: host.customMinutes === modelData ? "selected" : "ghost"
                  ink: host.popupText
                  accentColor: host.popupAccent
                  surface: host.popupSurface
                  fontSize: Style.font.bodySmall
                  onClicked: host.customMinutes = modelData
                }
              }
            }

            Column {
              id: heroColumn
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(26)
              spacing: Style.space(8)

              Item {
                id: dialBox
                width: Math.min(hero.width - Style.space(24), Style.space(200))
                height: width
                anchors.horizontalCenter: parent.horizontalCenter

                HeroRing {
                  id: dial
                  anchors.fill: parent

                  // A notch is a minute, Shift is five: the keyboard-free
                  // way to nudge without hunting for the exact angle.
                  WheelHandler {
                    acceptedModifiers: Qt.NoModifier
                    onWheel: function(event) { content.wheelOnDial(event.angleDelta.y) }
                  }
                  WheelHandler {
                    acceptedModifiers: Qt.ShiftModifier
                    onWheel: function(event) { content.wheelOnDial(event.angleDelta.y * 5) }
                  }
                  fraction: host.heroFraction
                  running: service.status !== "IDLE"
                  paused: service.status === "PAUSED"
                  tint: host.dialTint
                  ink: host.popupText
                  scrubbing: host.scrubbing
                  scrubMinutes: host.customMinutes
                  scrubMax: 120
                  reducedMotion: service.reducedMotion
                  focused: host.cursorActive && host.focusSection === "dial"
                  deltaMode: service.status !== "IDLE"
                  baseMinutes: host.heroBaseMinutes
                  onScrubbed: function(m) {
                    host.scrubbing = true
                    host.customMinutes = Math.max(1, m)
                  }
                  onClicked: if (service.status === "IDLE") host.startTimer()
                  onScrubFinished: function(m) {
                    var next = Math.max(1, m)
                    if (service.status !== "IDLE") {
                      // A drag while running moves the deadline; it does not
                      // restart the countdown from an absolute angle.
                      service.setTimer(next, service.action || host.selectedAction)
                    }
                    host.customMinutes = next
                    host.scrubbing = false
                  }
                }

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(1)

                  // The action being scheduled, as the system's own glyph: the
                  // ring says "when", this says "what".
                  Text {
                    id: heroActionIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: host.glyphForAction(host.selectedAction)
                    color: host.dialTint
                    font.family: "monospace"
                    font.pixelSize: Style.font.title
                    opacity: 0.9
                    SequentialAnimation on opacity {
                      running: service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED"
                      loops: Animation.Infinite
                      onRunningChanged: if (!running) heroActionIcon.opacity = 0.9
                      NumberAnimation { to: 0.35; duration: 420; easing.type: Easing.InOutQuad }
                      NumberAnimation { to: 0.9;  duration: 420; easing.type: Easing.InOutQuad }
                    }
                  }

                  Text {
                    id: heroFigure
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(dialBox.width * 0.74)
                    horizontalAlignment: Text.AlignHCenter
                    // Fit, never overflow: a five-glyph figure or a long
                    // locale shrinks instead of crossing the ring.
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 18
                    textFormat: Text.PlainText
                    text: host.heroText
                    color: (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED")
                           ? host.popupUrgent : host.popupText
                    font.family: "monospace"
                    font.pixelSize: Math.max(42, Math.round(dialBox.width * 0.26))
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    id: heroLabels
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(dialBox.width * 0.74)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    textFormat: Text.PlainText
                    text: String(host.heroCaption).toUpperCase()
                    color: host.popupText
                    opacity: 0.86
                    font.family: host.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                    elide: Text.ElideRight
                  }


                }
              }

              // Exact input without a colon to type: minutes and seconds are
              // two boxes with the separator printed between them. Tab or a
              // click moves across; Enter or the key starts.
              Row {
                id: exactRow
                width: Math.round(hero.width * 0.62)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(4)

                TextField {
                  id: mmField
                  width: Style.space(52)
                  height: Style.space(30)
                  placeholderText: String(Math.round(host.customMinutes))
                  validator: IntValidator { bottom: 0; top: 720 }
                  inputMethodHints: Qt.ImhDigitsOnly
                  font.family: "monospace"
                  font.pixelSize: Style.font.body
                  color: host.popupText
                  horizontalAlignment: Text.AlignHCenter
                  selectByMouse: true
                  background: BorderSurface {
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", host.popupText, host.popupAccent)
                    radius: Style.cornerRadius
                  }
                  onAccepted: content.submitBoxes()
                  Keys.onDownPressed: content.bump(mmField, -1)
                  Keys.onUpPressed: content.bump(mmField, 1)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: ":"
                  color: host.popupText
                  opacity: 0.6
                  font.family: "monospace"
                  font.pixelSize: Style.font.body
                }

                TextField {
                  id: ssField
                  width: Style.space(44)
                  height: Style.space(30)
                  placeholderText: "00"
                  validator: IntValidator { bottom: 0; top: 59 }
                  inputMethodHints: Qt.ImhDigitsOnly
                  font.family: "monospace"
                  font.pixelSize: Style.font.body
                  color: host.popupText
                  horizontalAlignment: Text.AlignHCenter
                  selectByMouse: true
                  background: BorderSurface {
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", host.popupText, host.popupAccent)
                    radius: Style.cornerRadius
                  }
                  onAccepted: content.submitBoxes()
                  Keys.onDownPressed: content.bump(ssField, -1)
                  Keys.onUpPressed: content.bump(ssField, 1)
                }

                Key {
                  id: startKey
                  width: Style.space(38)
                  text: "▶"
                  role: "ghost"
                  ink: host.popupText
                  accentColor: host.popupAccent
                  surface: host.popupSurface
                  fontSize: Style.font.bodySmall
                  onClicked: content.submitBoxes()
                }
              }

              Text {
                width: hero.width - Style.space(28)
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: host.heroHint
                color: host.popupText
                opacity: 0.62
                font.family: host.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          // The three escape hatches, as full-width keys under the plate: at
          // 11 px a bare glyph is a guess, a word is not.
          Row {
            id: heroButtons
            width: parent.width
            spacing: Style.space(6)
            visible: service.status !== "IDLE"

            Key {
              width: (parent.width - Style.space(12)) / 3
              text: service.status === "PAUSED" ? host.tr("btn.resume") : host.tr("btn.pause")
              role: "ghost"
              ink: host.popupText
              accentColor: host.popupAccent
              surface: host.popupSurface
              fontSize: Style.font.bodySmall
              hasCursor: host.cursorActive && host.focusSection === "hero" && host.focusIndex === 0
              onClicked: service.status === "PAUSED" ? service.resume() : service.pause()
            }

            Key {
              width: (parent.width - Style.space(12)) / 3
              text: "+" + service.snoozeMins + " " + host.tr("unit.min")
              role: "ghost"
              ink: host.popupText
              accentColor: host.popupAccent
              surface: host.popupSurface
              fontSize: Style.font.bodySmall
              hasCursor: host.cursorActive && host.focusSection === "hero" && host.focusIndex === 1
              onClicked: host.snoozeNow()
            }

            Key {
              width: (parent.width - Style.space(12)) / 3
              text: host.tr("btn.cancel")
              role: "danger"
              ink: host.popupText
              accentColor: host.popupAccent
              dangerColor: host.popupUrgent
              surface: host.popupSurface
              fontSize: Style.font.bodySmall
              hasCursor: host.cursorActive && host.focusSection === "hero" && host.focusIndex === 2
              onClicked: host.askCancel()
            }
          }

          // ---- the dial and the wheel are the input: no presets, no field ----

          // ---- tray: the rare settings, opened in place ----
          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { key: "repeat",  label: host.tr("tray.schedule") },
                { key: "more",    label: host.tr("tray.more") },
                { key: "history", label: host.tr("tray.history") }
              ]

              delegate: Key {
                required property var modelData
                width: (parent.width - Style.space(12)) / 3
                text: (host.trayOpen === modelData.key ? "▾ " : "▸ ") + modelData.label
                hasCursor: host.cursorActive && host.focusSection === "tray" && host.focusIndex === index
                role: host.trayOpen === modelData.key ? "selected" : "ghost"
                ink: host.popupText
                accentColor: host.popupAccent
                surface: host.popupSurface
                fontSize: Style.font.bodySmall
                onClicked: host.trayOpen = (host.trayOpen === modelData.key ? "" : modelData.key)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: host.trayOpen === "repeat"

            ButtonGroup {
              id: repeatGroup
              cursorIndex: host.cursorActive && host.focusSection === "repeat"
                           ? Math.max(0, host.repeatOptions.indexOf(host.repeatMode)) : -1
              width: parent.width
              options: [
                { value: "once",     label: host.tr("repeat.once") },
                { value: "daily",    label: host.tr("repeat.daily") },
                { value: "weekdays", label: host.tr("repeat.weekdays") },
                { value: "weekends", label: host.tr("repeat.weekends") }
              ]
              value: host.repeatMode
              foreground: host.popupText
              accent: host.popupAccent
              fontFamily: host.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(v) { host.repeatMode = v }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                id: addScheduleButton
                hasCursor: host.cursorActive && host.focusSection === "addschedule"
                width: parent.width - addScheduleHint.implicitWidth - Style.space(8)
                text: host.tr("repeat.add") + " — " + (host.timeModeAbsolute && host.absoluteTime.trim() !== ""
                      ? host.absoluteTime.trim() : host.minutesToHhmm(host.customMinutes))
                fontSize: Style.font.bodySmall
                foreground: host.popupText
                fontFamily: host.fontFamily
                bordered: true
                onClicked: host.addSchedule()
              }

              Text {
                id: addScheduleHint
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: host.daysLabel(host.daysForRepeat())
                color: host.popupText
                opacity: 0.65
                font.family: host.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              id: schedulesColumn
              width: parent.width
              spacing: Style.space(4)
              visible: host.scheduleRows.length > 0

              Repeater {
                model: host.scheduleRows

                delegate: Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    width: parent.width - removeSchedule.width - Style.space(6)
                    textFormat: Text.PlainText
                    text: "#" + modelData.id + "  " + modelData.at + "  " + modelData.rest
                    color: host.popupText
                    opacity: 0.8
                    font.family: host.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PanelActionButton {
                    id: removeSchedule
                    hasCursor: host.cursorActive && host.focusSection === "schedules" && host.focusIndex === index
                    iconText: host.glyphCancel
                    tooltipText: host.tr("repeat.remove")
                    foreground: host.popupUrgent
                    fontFamily: host.fontFamily
                    onClicked: {
                      service.scheduleRemove(modelData.id)
                      Qt.callLater(function() { host.loadSchedules() })
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: host.scheduleRows.length === 0
              textFormat: Text.PlainText
              text: host.tr("repeat.none")
              color: host.popupText
              opacity: 0.55
              font.family: host.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            id: advancedColumn
            width: parent.width
            spacing: Style.space(6)
            visible: host.trayOpen === "more"

            // Each row writes the setting straight to shell.json through the
            // shell's own CLI — the widget's `settings` are read-only here.
            Repeater {
              model: [
                { key: "batteryGuard",      label: host.tr("adv.battery"), on: service.batteryGuard },
                { key: "quiet",             label: host.tr("adv.quiet"),   on: service.quiet },
                { key: "waitForInhibitors", label: host.tr("adv.wait"),    on: service.waitForInhibitors },
                { key: "ambientFade",       label: host.tr("adv.fade"),    on: service.ambientFade }
              ]

              delegate: Row {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(8)
                readonly property bool hot: host.cursorActive && host.focusSection === "advanced" && host.focusIndex === index

                MouseArea {
                  width: parent.width
                  height: Style.spacing.controlHeight
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: host.toggleSetting(modelData.key, !modelData.on)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: parent.hot ? Style.space(2) : 0
                    textFormat: Text.PlainText
                    text: (modelData.on ? host.glyphCheck + "  " : "     ") + modelData.label
                    color: modelData.on ? host.popupAccent : (parent.hot ? host.popupAccent : host.popupText)
                    font.family: host.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
              }
            }

            // Dry run lives beside the toggles but is not a shell.json setting —
            // it is a file the daemon reads at firing time.
            Row {
              width: parent.width
              spacing: Style.space(8)
              readonly property bool hot: host.cursorActive && host.focusSection === "advanced" && host.focusIndex === 4

              MouseArea {
                width: parent.width
                height: Style.spacing.controlHeight
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: service.setOverride(service.overrideCommand === "" ? "echo" : "off")

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: parent.parent.hot ? Style.space(2) : 0
                  width: parent.width
                  textFormat: Text.PlainText
                  text: (service.overrideCommand !== "" ? host.glyphCheck + "  " : "     ") + host.tr("adv.dryRun")
                  color: service.overrideCommand !== "" ? host.popupAccent : (parent.parent.hot ? host.popupAccent : host.popupText)
                  font.family: host.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            Text {
              width: parent.width
              visible: service.overrideCommand !== ""
              textFormat: Text.PlainText
              text: host.tr("adv.dryRunHint") + " (" + service.overrideCommand + ")"
              color: host.popupText
              opacity: 0.6
              font.family: host.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: service.dnd
              textFormat: Text.PlainText
              text: host.tr("adv.dnd")
              color: host.popupUrgent
              font.family: host.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(3)
            visible: host.trayOpen === "history"

            Repeater {
              model: host.historyRows

              delegate: Text {
                required property string modelData
                width: parent.width
                textFormat: Text.PlainText
                text: modelData
                color: host.popupText
                opacity: 0.72
                font.family: host.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Text {
              width: parent.width
              visible: host.historyRows.length === 0
              textFormat: Text.PlainText
              text: host.tr("history.empty")
              color: host.popupText
              opacity: 0.55
              font.family: host.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- launch: always on the first screen, never below the fold ----
          Key {
            id: launchButton
            width: parent.width
            text: service.status === "IDLE"
                  ? host.tr("launch.in", String(Math.round(host.customMinutes)))
                  : host.tr("launch.update", String(Math.round(host.customMinutes)))
            role: "primary"
            bold: true
            ink: host.popupText
            accentColor: host.popupAccent
            surface: host.popupSurface
            fontSize: Style.font.body
            hasCursor: host.cursorActive && host.focusSection === "launch"
            onClicked: host.startTimer()
          }
}
