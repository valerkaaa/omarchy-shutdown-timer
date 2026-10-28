import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar widget: icon + remaining-time in the bar, and a popup menu to schedule
// a power action. The full-screen overlay lives in Overlay.qml (same plugin).
Panel {
  id: root
  moduleName: "honor.shutdown-timer"
  ipcTarget: "honor.shutdown-timer"
  manageIpc: false

  // The bar host sizes a widget slot from its implicit size only: without
  // these the widget occupies zero pixels and never shows up on the bar.
  implicitWidth: vertical
                 ? button.implicitWidth
                 : button.implicitWidth + (timeLabel.visible ? timeLabel.implicitWidth + Style.space(2) : 0) + Style.space(4)
  implicitHeight: vertical
                  ? button.implicitHeight + (verticalTime.visible ? verticalTime.implicitHeight : 0)
                  : button.implicitHeight

  // ---------- theme ----------
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  // The bar API has no `accent` in this shell build (`bar.accent` is
  // undefined), so a fallback on it lands on `foreground` and the ≤5 min
  // "warning" step of the ladder becomes invisible. Fall back to the theme
  // accent instead.
  readonly property color accent: (bar && bar.accent) ? bar.accent : Commons.Color.accent

  // Popup surface + text, contrast-checked (TZ 12). A theme may pair a warm
  // red with a warm light surface and land just under 4.5:1; readableOn()
  // nudges the text toward black/white in that case and returns it unchanged
  // otherwise, so urgent text stays red on every theme.
  readonly property color popupSurface: Commons.Color.popups.background
  readonly property color popupText: Model.readableOn(String(Commons.Color.popups.text), String(popupSurface), 4.5)
  readonly property color popupUrgent: Model.readableOn(String(urgent), String(popupSurface), 4.5)
  readonly property color popupAccent: Model.readableOn(String(accent), String(popupSurface), 4.5)

  // ---------- localization ----------
  readonly property string language: service.language
  function tr(key, args) { return Model.t(key, language, args) }

  // ---------- glyphs (Nerd Font escapes) ----------
  readonly property string glyphPower:  "\uf011"  // nf-fa-power_off
  readonly property string glyphReboot: "\uf021"  // nf-fa-refresh
  readonly property string glyphSuspend: "\uf0a1" // nf-fa-moon
  readonly property string glyphBolt:   "\uf0e7"  // nf-fa-bolt
  readonly property string glyphCancel: "\uf00d"  // nf-fa-close
  readonly property string glyphClock:  "\uf017"  // nf-fa-clock_o
  readonly property string glyphPause:  "\uf04c"  // nf-fa-pause
  readonly property string glyphPlay:   "\uf04b"  // nf-fa-play
  readonly property string glyphPlus:   "\uf067"  // nf-fa-plus
  readonly property string glyphCheck:  "\uf00c"  // nf-fa-check

  function glyphForAction(action) {
    if (action === "reboot") return glyphReboot
    if (action === "suspend") return glyphSuspend
    if (action === "hibernate") return glyphSuspend
    return glyphPower
  }

  // Bar colour ladder per TZ 6.2: normal → accent in the last 5 minutes →
  // urgent in the last minute and during the overlay countdown. A scheduled
  // firing counts as urgent from the start — it was not asked for just now.
  readonly property color barColor: {
    if (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED") return urgent
    if (service.status === "ACTIVE" && service.timeLeft <= 60) return urgent
    if (service.status === "ACTIVE" && service.timeLeft <= 300) return accent
    if (service.status === "PAUSED") return foreground
    return foreground
  }

  // Vertical bar: "MM:SS" is split at the colon so the slot stays narrow.
  readonly property var verticalLines: {
    if (!vertical) return []
    var txt = barText
    if (txt === "") return []
    return String(txt).split(":")
  }

  readonly property string barText: {
    if (service.status === "IDLE") {
      // a pending schedule shows a dot instead of a figure
      return root.scheduleDot
    }
    root.tick // force re-eval on tick
    return Model.formatTime(service.timeLeft)
  }

  // "•" marks "schedules exist" while idle (TZ 9.5)
  readonly property string scheduleDot: service.scheduleCount > 0 ? "•" : ""

  readonly property bool barDimmed: false
  readonly property string barTooltip: {
    if (service.status === "IDLE") return tr("tooltip.idle")
    if (service.status === "PAUSED") return Model.actionLabel(service.action, language) + " — " + tr("btn.pause").toLowerCase() + " · " + Model.formatTime(service.timeLeft) + " · " + tr("tooltip.cancelHint")
    if (service.status === "ACTIVE") return Model.actionLabel(service.action, language) + " " + tr("time.in") + " " + Model.formatTime(service.timeLeft) + " · " + tr("tooltip.cancelHint")
    return tr("tooltip.countdown", Model.formatTime(service.timeLeft))
  }

  // ---------- menu state ----------
  property string selectedAction: String(service.defaultAction)
  property bool timeModeAbsolute: false
  property string absoluteTime: ""
  property int customMinutes: 30

  // Presets come from the setting (TZ 9.8), not a literal in the panel.
  readonly property var quickPresets: service.presetList
  property string selectedQuick: ""

  // ---------- repeat / schedule state ----------
  property string repeatMode: "once"          // once | daily | weekdays | weekends
  property var scheduleRows: []               // [{id, at, days, action}]

  // ---------- keyboard cursor (TZ 12: everything reachable by keyboard) ----------
  // Same model as the stock panels: arrow keys walk a section cursor, Enter
  // activates, and the mouse never has to be touched. The cursor stays off
  // until the first arrow press so plain Enter keeps its old meaning
  // ("launch the timer") for mouse users.
  property bool cursorActive: false
  property string focusSection: "action"
  property int focusIndex: 0

  readonly property var actionOptions: ["poweroff", "reboot", "suspend", "hibernate"]
  readonly property var repeatOptions: ["once", "daily", "weekdays", "weekends"]

  // Sections in visual order, visibility-aware.
  function cursorSections() {
    var out = []
    if (service.status !== "IDLE") out.push("hero")
    out.push("action", "presets", "mode")
    out.push(timeModeAbsolute ? "abs" : "minutes")
    out.push("repeat", "addschedule")
    if (scheduleRows.length > 0) out.push("schedules")
    out.push("advanced", "launch")
    if (service.status !== "IDLE") out.push("reset")
    return out
  }

  function sectionCount(section) {
    if (section === "presets") return quickPresets.length
    if (section === "advanced") return 4
    if (section === "schedules") return scheduleRows.length
    if (section === "hero") return 3
    return 1
  }

  function ensureCursor() {
    var list = cursorSections()
    if (list.indexOf(focusSection) < 0) { focusSection = "action"; focusIndex = 0; return }
    var max = sectionCount(focusSection) - 1
    if (focusIndex > max) focusIndex = Math.max(0, max)
    if (focusIndex < 0) focusIndex = 0
  }

  function cycleIn(list, value, dx) {
    var i = list.indexOf(value)
    if (i < 0) i = 0
    i = (i + dx + list.length) % list.length
    return list[i]
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    var list = cursorSections()
    if (dy !== 0) {
      var at = list.indexOf(focusSection)
      at = Math.max(0, Math.min(list.length - 1, at + dy))
      focusSection = list[at]
      focusIndex = Math.min(focusIndex, Math.max(0, sectionCount(focusSection) - 1))
    } else if (dx !== 0) {
      if (focusSection === "hero" || focusSection === "presets" ||
          focusSection === "advanced" || focusSection === "schedules") {
        focusIndex = Math.max(0, Math.min(sectionCount(focusSection) - 1, focusIndex + dx))
      } else if (focusSection === "action") {
        selectedAction = cycleIn(actionOptions, selectedAction, dx)
      } else if (focusSection === "minutes") {
        customMinutes = Math.max(1, Math.min(1440, customMinutes + dx * 5))
      } else if (focusSection === "mode") {
        timeModeAbsolute = !timeModeAbsolute
      } else if (focusSection === "repeat") {
        repeatMode = cycleIn(repeatOptions, repeatMode, dx)
      }
    }
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "hero") {
      if (focusIndex === 0) service.status === "PAUSED" ? service.resume() : service.pause()
      else if (focusIndex === 1) service.snooze(5)
      else service.cancel()
    } else if (focusSection === "presets") {
      var p = quickPresets[focusIndex]
      if (p !== undefined) { selectedQuick = String(p); customMinutes = p; quickSet(p) }
    } else if (focusSection === "mode") {
      timeModeAbsolute = !timeModeAbsolute
    } else if (focusSection === "minutes") {
      customField.forceActiveFocus()
    } else if (focusSection === "abs") {
      absTimeField.forceActiveFocus()
    } else if (focusSection === "addschedule") {
      addSchedule()
    } else if (focusSection === "schedules") {
      var row = scheduleRows[focusIndex]
      if (row) { service.scheduleRemove(row.id); Qt.callLater(function() { root.loadSchedules() }) }
    } else if (focusSection === "advanced") {
      if (focusIndex === 3) {
        service.setOverride(service.overrideCommand === "" ? "echo" : "off")
      } else {
        var keys = ["batteryGuard", "quiet", "waitForInhibitors"]
        var ons = [service.batteryGuard, service.quiet, service.waitForInhibitors]
        if (keys[focusIndex]) toggleSetting(keys[focusIndex], !ons[focusIndex])
      }
    } else if (focusSection === "launch") {
      startTimer()
    } else if (focusSection === "reset") {
      resetTimer()
    }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top <= panelFlick.height * 0.1 + viewTop) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom >= viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    var item = null
    if (focusSection === "hero" || focusSection === "launch" || focusSection === "reset") item = launchButton
    else if (focusSection === "presets") item = presetGrid
    else if (focusSection === "action") item = actionDropdown
    else if (focusSection === "mode") item = modeGroup
    else if (focusSection === "minutes") item = minutesSlider
    else if (focusSection === "abs") item = absTimeField
    else if (focusSection === "repeat") item = repeatGroup
    else if (focusSection === "addschedule") item = addScheduleButton
    else if (focusSection === "schedules") item = schedulesColumn
    else if (focusSection === "advanced") item = advancedColumn
    scrollItemIntoView(item)
  }

  // repeat mode → the day spec the daemon stores ("-", daily, 1..5, 6,7)
  function daysForRepeat() {
    if (repeatMode === "daily") return "1,2,3,4,5,6,7"
    if (repeatMode === "weekdays") return "1,2,3,4,5"
    if (repeatMode === "weekends") return "6,7"
    return String(new Date().getDay() === 0 ? 7 : new Date().getDay())
  }

  function addSchedule() {
    var hhmm = timeModeAbsolute && absoluteTime.trim() !== "" ? absoluteTime.trim() : minutesToHhmm(customMinutes)
    if (!/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/.test(hhmm)) hhmm = minutesToHhmm(customMinutes)
    service.scheduleAdd(hhmm, daysForRepeat(), selectedAction)
    Qt.callLater(function() { root.loadSchedules() })
  }

  function minutesToHhmm(mins) {
    var d = new Date(Date.now() + Math.round(mins) * 60000)
    var h = d.getHours(), m = d.getMinutes()
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
  }

  function daysLabel(spec) {
    if (spec === "1,2,3,4,5,6,7") return tr("repeat.daily")
    if (spec === "1,2,3,4,5") return tr("repeat.weekdays")
    if (spec === "6,7") return tr("repeat.weekends")
    var out = []
    var parts = String(spec).split(",")
    for (var i = 0; i < parts.length; i++) {
      var k = "week." + parts[i]
      var lbl = Model.t(k, language, [])
      if (lbl !== k) out.push(lbl)
    }
    return out.join(" ")
  }

  function loadSchedules() {
    schedulesProc.command = ["bash", service.controlPath, "schedule", "list"]
    schedulesProc.running = true
  }

  function loadHistory() {
    historyProc.command = ["bash", service.controlPath, "history"]
    historyProc.running = true
  }

  Process {
    id: schedulesProc
    running: false
    stdout: StdioCollector { id: schedulesOut; waitForEnd: true }
    onExited: {
      var rows = []
      var lines = String(schedulesOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "" || line.indexOf("#") !== 0) continue
        // "#<id>  at HH:MM  <days label>  <action label>  (last: ...)"
        var m = line.match(/^#(\S+)\s+at\s+(\S+)\s+(.*)$/)
        if (!m) m = line.match(/^#(\S+)\s+[\u0432]\s+(\S+)\s+(.*)$/);
        if (m) rows.push({ id: m[1], at: m[2], rest: m[3] })
      }
      root.scheduleRows = rows
    }
  }

  Process {
    id: historyProc
    running: false
    stdout: StdioCollector { id: historyOut; waitForEnd: true }
    onExited: {
      root.historyRows = String(historyOut.text || "").trim().split("\n").slice(0, 5)
    }
  }

  property var historyRows: []

  // TZ 9.1: a bad time is an inline urgent line under the field, not a toast.
  readonly property bool absTimeValid: absoluteTime.trim() === "" || /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/.test(absoluteTime.trim())
  readonly property string absTimeError: timeModeAbsolute && !absTimeValid ? tr("error.badTime") : ""

  function quickSet(mins) {
    service.setTimer(mins, selectedAction)
    close()
  }

  function startTimer() {
    if (timeModeAbsolute) {
      if (absoluteTime.trim() === "") {
        absTimeField.forceActiveFocus()
        return
      }
      if (!/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/.test(absoluteTime.trim())) {
        absTimeField.forceActiveFocus()
        return
      }
      service.setTimerAbsolute(absoluteTime, selectedAction)
    } else {
      var mins = Math.round(customMinutes)
      if (!mins || mins < 1) mins = 1
      if (mins > 1440) mins = 1440
      service.setTimer(mins, selectedAction)
    }
    close()
  }

  function cancelTimer() {
    service.cancel()
  }

  function resetTimer() {
    service.reset()
  }

  // Write a boolean setting back to shell.json through the shell CLI. The
  // widget's own `settings` object is read-only, and the CLI is the supported
  // write path — it also re-renders the widget, so the new value applies live.
  function toggleSetting(key, value) {
    Quickshell.execDetached(["bash", "-c",
      "omarchy bar set " + root.moduleName + " " + key + " " + (value ? "true" : "false")])
  }

  // ---------- service ----------
  Service {
    id: service
    settings: root.settings
    notifyInstance: true
  }

  // Summon the fullscreen overlay when a countdown begins.
  Connections {
    target: service
    function onStatusChanged() {
      if (service.status === "COUNTDOWN") {
        Quickshell.execDetached(["omarchy-shell", "-q", "honor.shutdown-timer:overlay", "show"])
      }
    }
  }

  // Tick every second so the remaining time re-renders between daemon polls
  property int tick: 0
  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: root.opened || (service.loaded && service.status !== "IDLE")
    triggeredOnStart: true
    onTriggered: { root.tick++ }
  }

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  // ---------- IPC handler ----------
  IpcHandler {
    target: root.ipcTarget

    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function refresh(): string { service.refresh(); return "ok" }

    function status(): string {
      if (!service.loaded) return "loading"
      return service.status + " " + (service.action || "none") + " " + String(service.timeLeft)
    }

    function set(payloadJson: string): string {
      var p = ({}); try { p = JSON.parse(payloadJson || "{}") } catch(e) {}
      if (p.minutes !== undefined) service.setTimer(p.minutes, p.action || "")
      else if (p.seconds !== undefined) service.setTimer(Math.round(p.seconds / 60), p.action || "")
      else if (p.hours !== undefined) service.setTimer(p.hours * 60, p.action || "")
      else if (p.absolute !== undefined) service.setTimerAbsolute(p.absolute, p.action || "")
      return "ok"
    }

    function cancel(): string { service.cancel(); return "ok" }
    function snooze(mins: string): string { service.snooze(parseInt(mins || "5", 10)); return "ok" }
    function pause(): string { service.pause(); return "ok" }
    function resume(): string { service.resume(); return "ok" }
    function reset(): string { service.reset(); return "ok" }

    function scheduleAdd(payloadJson: string): string {
      var p = ({}); try { p = JSON.parse(payloadJson || "{}") } catch(e) {}
      if (p.at) service.scheduleAdd(p.at, p.days || "1,2,3,4,5,6,7", p.action || "")
      return "ok"
    }
    function scheduleRemove(id: string): string { service.scheduleRemove(id); return "ok" }
    function show(): string { root.open(); return "ok" }
    function hide(): string { root.close(); return "ok" }

    // Walk the popup tree and report every visible child that pokes out of its
    // parent. This is the "icons must not spill over the frame" rule as a
    // test: a screenshot only shows the states someone thought to capture,
    // this catches the ones nobody looks at.
    function debugOverflow(): string {
      var out = []
      function nameOf(item, index) {
        if (item.id) return String(item.id)
        var s = String(item)
        var m = s.match(/^([A-Za-z_][A-Za-z0-9_]*)/)
        return (m ? m[1] : "item") + "#" + index
      }
      // Bounds of `item` mapped into `column`, which is what the eye actually
      // sees: an icon scaled inside a 24-unit box can have children that stick
      // out of that box on paper while staying well inside the popup column.
      function boundsIn(item, target) {
        var p = item.mapToItem(target, 0, 0)
        return { x: p.x, y: p.y, w: item.width * (item.scale || 1), h: item.height * (item.scale || 1) }
      }
      var frame = { w: column.width, h: column.implicitHeight }
      function walk(item, path) {
        var kids = item.children
        for (var i = 0; i < kids.length; i++) {
          var c = kids[i]
          var label = path + "/" + nameOf(c, i)
          if (c.visible && c.width > 0 && c.height > 0) {
            var b = boundsIn(c, column)
            var overRight = b.x + b.w > frame.w + 1
            var overLeft = b.x < -1
            var overBottom = b.y + b.h > frame.h + 1
            var overTop = b.y < -1
            if (overRight || overLeft || overBottom || overTop) {
              out.push({
                path: label,
                at: Math.round(b.x) + "," + Math.round(b.y),
                size: Math.round(b.w) + "x" + Math.round(b.h),
                frame: Math.round(frame.w) + "x" + Math.round(frame.h),
                sides: (overLeft ? "L" : "") + (overRight ? "R" : "") +
                       (overTop ? "T" : "") + (overBottom ? "B" : "")
              })
            }
          }
          walk(c, label)
        }
      }
      walk(column, "column")
      return JSON.stringify({ count: out.length, items: out.slice(0, 15) })
    }

    // Layout probe: every number a future bug report would need, and the two
    // overflow checks the eye does on a screenshot. Text can only be trusted
    // once these come back clean.
    // Keyboard-cursor state, so a wtype-driven test can assert navigation
    // without relying on pixels.
    function debugCursor(): string {
      return JSON.stringify({
        cursorActive: root.cursorActive,
        focusSection: root.focusSection,
        focusIndex: root.focusIndex,
        sections: root.cursorSections(),
        selectedAction: root.selectedAction,
        customMinutes: root.customMinutes,
        timeModeAbsolute: root.timeModeAbsolute,
        repeatMode: root.repeatMode,
        overrideCommand: service.overrideCommand
      })
    }

    function debugLayout(): string {
      return JSON.stringify({
        language: root.language,
        bar: {
          implicitWidth: Math.round(root.implicitWidth),
          implicitHeight: Math.round(root.implicitHeight),
          button: Math.round(button.implicitWidth) + "x" + Math.round(button.implicitHeight),
          icon: Math.round(heroIcon.iconSize),
          labelVisible: timeLabel.visible,
          labelWidth: Math.round(timeLabel.implicitWidth),
          barColor: String(root.barColor),
          urgentColor: String(root.urgent),
          accentColor: String(root.accent)
        },
        popup: {
          open: root.opened,
          width: Math.round(panel.width),
          height: Math.round(panel.height),
          contentWidth: Math.round(panel.contentWidth),
          contentHeight: Math.round(panel.contentHeight),
          columnHeight: Math.round(column.implicitHeight),
          scrolls: column.implicitHeight > panelFlick.height
        },
        hero: {
          height: Math.round(hero.height),
          iconWidth: Math.round(heroIcon.width),
          labelsX: Math.round(heroLabels.x),
          labelsWidth: Math.round(heroLabels.width),
          buttonsX: Math.round(heroButtons.x),
          buttonsWidth: Math.round(heroButtons.width),
          // the label column must start after the icon and end before the buttons
          iconClearsLabels: heroLabels.x >= heroIcon.width,
          labelsClearButtons: !heroButtons.visible || (heroLabels.x + heroLabels.width) <= heroButtons.x
        }
      })
    }
  }

  // ---------- bar button ----------
  // Icon and remaining time are separate items: the vector mark never has to
  // be redrawn per state, and the label can collapse to nothing in IDLE so the
  // widget takes a single icon slot when idle.
  readonly property string iconVariant: {
    if (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED") return "countdown"
    if (service.status === "PAUSED") return "paused"
    if (service.status === "ACTIVE") return "active"
    return "idle"
  }

  BarIconButton {
    id: button
    anchors.left: vertical ? undefined : parent.left
    anchors.horizontalCenter: vertical ? parent.horizontalCenter : undefined
    anchors.top: vertical ? parent.top : undefined
    anchors.verticalCenter: vertical ? undefined : parent.verticalCenter
    bar: root.bar
    text: "timer"
    foreground: root.barColor
    active: root.barColor === root.urgent
    dimmed: root.barDimmed
    tooltipText: root.barTooltip

    iconComponent: Component {
      TimerIcon {
        anchors.centerIn: parent
        // Same optical size as the neighbouring balance glyph: a thin ring
        // needs the height to keep its counter open, and at 13 px the mark
        // collapses into a star.
        iconSize: Style.font.display
        reducedMotion: service.reducedMotion
        color: root.barColor
        variant: root.iconVariant
      }
    }

    onPressed: function(code) {
      if (code === Qt.LeftButton) root.toggle()
      else if (code === Qt.RightButton) {
        // Right-click is the fastest escape hatch: cancel a running timer,
        // refresh when there is nothing to cancel.
        if (service.status === "ACTIVE" || service.status === "COUNTDOWN" || service.status === "PAUSED") service.cancel()
        else service.refresh()
      }
    }
  }

  // Remaining time, monospaced so the digits do not jitter as they change.
  Text {
    id: timeLabel
    anchors.left: button.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(2)
    visible: !root.vertical && root.barText !== ""
    text: root.barText
    textFormat: Text.PlainText
    color: root.barColor
    font.family: "monospace"
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }

  // Vertical bar: the same reading, one line per colon-separated chunk.
  Column {
    id: verticalTime
    anchors.top: button.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.vertical && root.verticalLines.length > 0

    Repeater {
      model: root.verticalLines

      delegate: Text {
        required property string modelData
        width: button.width
        textFormat: Text.PlainText
        text: modelData
        horizontalAlignment: Text.AlignHCenter
        color: root.barColor
        font.family: "monospace"
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }

  // ---------- popup ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: customField.activeFocus || absTimeField.activeFocus
      onCloseRequested: root.close()
      // Arrows start the cursor; until then Enter keeps its old meaning
      // ("launch the timer now").
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      // Return emits BOTH returnRequested and activateRequested, so the
      // activation lives in one place — wiring the same action to both
      // handlers would run it twice (double-add, toggles cancelling out).
      onActivateRequested: if (root.cursorActive) root.activateCursor(); else root.startTimer()
      onDeleteRequested: {
        if (root.cursorActive && root.focusSection === "schedules" && root.scheduleRows[root.focusIndex]) {
          service.scheduleRemove(root.scheduleRows[root.focusIndex].id)
          Qt.callLater(function() { root.loadSchedules() })
        }
      }
      onTextKey: function(t) {
        // TZ 6.3: digits are the fastest way to a preset.
        if (t >= "1" && t <= "9") {
          var i = parseInt(t, 10) - 1
          var p = root.quickPresets[i]
          if (p !== undefined) { root.selectedQuick = String(p); root.customMinutes = p; root.quickSet(p) }
          return
        }
        if (t === "c" || t === "C") service.cancel()
        else if (t === "p" || t === "P") service.status === "PAUSED" ? service.resume() : service.pause()
        else if (t === "s" || t === "S") service.snooze(5)
        else if (t === "r" || t === "R") root.resetTimer()
      }
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        // ---- hero: state, live countdown, escape hatches ----
        Item {
          id: hero
          width: parent.width
          implicitHeight: Math.max(heroIcon.height, heroLabels.implicitHeight, heroButtons.implicitHeight)

          TimerIcon {
            id: heroIcon
            reducedMotion: service.reducedMotion
            // iconSize drives the mark's own size; anchors only place the box
            iconSize: Style.font.displayLarge + Style.space(6)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: service.status === "IDLE" ? root.foreground : root.barColor
            variant: root.iconVariant
          }

          Row {
            id: heroButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            visible: service.status !== "IDLE"

            PanelActionButton {
              hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 0
              iconText: service.status === "PAUSED" ? root.glyphPlay : root.glyphPause
              tooltipText: service.status === "PAUSED" ? root.tr("btn.resume") : root.tr("btn.pause")
              foreground: root.popupText
              fontFamily: root.fontFamily
              onClicked: service.status === "PAUSED" ? service.resume() : service.pause()
            }

            PanelActionButton {
              hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 1
              iconText: root.glyphPlus
              tooltipText: root.tr("btn.snooze")
              foreground: root.popupText
              fontFamily: root.fontFamily
              onClicked: service.snooze(5)
            }

            PanelActionButton {
              hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 2
              iconText: root.glyphCancel
              tooltipText: root.tr("btn.cancel")
              foreground: root.popupUrgent
              fontFamily: root.fontFamily
              onClicked: service.cancel()
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: heroButtons.visible ? heroButtons.left : parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                if (service.status === "IDLE") return tr("state.none")
                if (service.status === "PAUSED") return tr("state.paused", Model.actionLabel(service.action, language))
                if (service.status === "COUNTDOWN") return tr("state.countdown", Model.actionLabel(service.action, language))
                return tr("state.active", Model.actionLabel(service.action, language))
              }
              color: root.popupText
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                root.tick
                if (service.status === "IDLE") return tr("state.noneHint")
                return Model.formatTime(service.timeLeft)
              }
              color: service.status === "COUNTDOWN" ? root.popupUrgent : root.popupText
              font.family: service.status === "IDLE" ? root.fontFamily : "monospace"
              font.pixelSize: service.status === "IDLE" ? Style.font.bodySmall : Style.font.display
              font.bold: service.status !== "IDLE"
              elide: Text.ElideRight
            }
          }
        }

        // ---- action ----
        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.action")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Dropdown {
          id: actionDropdown
          hasCursor: root.cursorActive && root.focusSection === "action"
          width: parent.width
          label: ""
          foreground: root.popupText
          fontFamily: root.fontFamily
          value: root.selectedAction
          options: [
            { value: "poweroff", label: root.tr("action.poweroff") },
            { value: "reboot",   label: root.tr("action.reboot") },
            { value: "suspend",  label: root.tr("action.suspend") },
            { value: "hibernate", label: root.tr("action.hibernate") }
          ]
          onValueChanged: root.selectedAction = value
        }

        // ---- presets ----
        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.presets")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Grid {
          id: presetGrid
          width: parent.width
          columns: 3
          spacing: Style.space(8)

          Repeater {
            model: root.quickPresets

            delegate: Button {
              required property int modelData
              width: (parent.width - Style.space(16)) / 3
              text: String(modelData) + " " + root.tr("unit.min")
              fontSize: Style.font.body
              foreground: root.popupText
              fontFamily: root.fontFamily
              bordered: true
              selected: root.selectedQuick === String(modelData)
              hasCursor: root.cursorActive && root.focusSection === "presets" && root.focusIndex === index
              onClicked: {
                root.selectedQuick = String(modelData)
                root.customMinutes = modelData
                root.quickSet(modelData)
              }
            }
          }
        }

        // ---- exact time ----
        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.exact")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ButtonGroup {
          id: modeGroup
          // ButtonGroup highlights by index, not by a boolean.
          cursorIndex: root.cursorActive && root.focusSection === "mode"
                       ? (root.timeModeAbsolute ? 1 : 0) : -1
          width: parent.width
          options: [
            { value: "relative", label: root.tr("mode.relative") },
            { value: "absolute", label: root.tr("mode.absolute") }
          ]
          value: root.timeModeAbsolute ? "absolute" : "relative"
          foreground: root.popupText
          accent: root.popupAccent
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onChanged: root.timeModeAbsolute = (value === "absolute")
        }

        Row {
          id: minutesRow
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.space(10)
          visible: !root.timeModeAbsolute

          PanelSlider {
            id: minutesSlider
            width: parent.width - customField.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            minimum: 1
            maximum: 1440
            step: 5
            integer: true
            tickCount: 7
            value: root.customMinutes
            onMoved: root.customMinutes = Math.round(minutesSlider.liveValue)
            onReleased: root.customMinutes = Math.round(minutesSlider.liveValue)
          }

          NumberField {
            id: customField
            hasCursor: root.cursorActive && root.focusSection === "minutes"
            // NumberField sizes its inner SpinBox from `fieldWidth`, not from
            // the component's own width: setting width alone left the field
            // nine pixels wider than the column it sits in.
            fieldWidth: Style.space(110)
            from: 1
            to: 1440
            value: root.customMinutes
            foreground: root.popupText
            fontFamily: root.fontFamily
            onModified: root.customMinutes = value
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.timeModeAbsolute

          TextField {
          id: absTimeField
          hasCursor: root.cursorActive && root.focusSection === "abs"
          width: parent.width
          placeholderText: "14:30"
          text: root.absoluteTime
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          color: root.popupText
          background: BorderSurface {
            color: "transparent"
            borderSpec: Border.controlSpec("normal", root.popupText, root.accent)
            radius: Style.cornerRadius
          }
          onTextChanged: root.absoluteTime = text
          onAccepted: root.startTimer()
          }

          Text {
            width: parent.width
            visible: root.absTimeError !== ""
            textFormat: Text.PlainText
            text: root.absTimeError
            color: root.popupUrgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- repeat / schedule ----
        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.repeat")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ButtonGroup {
          id: repeatGroup
          cursorIndex: root.cursorActive && root.focusSection === "repeat"
                       ? Math.max(0, root.repeatOptions.indexOf(root.repeatMode)) : -1
          width: parent.width
          options: [
            { value: "once",     label: root.tr("repeat.once") },
            { value: "daily",    label: root.tr("repeat.daily") },
            { value: "weekdays", label: root.tr("repeat.weekdays") },
            { value: "weekends", label: root.tr("repeat.weekends") }
          ]
          value: root.repeatMode
          foreground: root.popupText
          accent: root.popupAccent
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onChanged: root.repeatMode = value
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: addScheduleButton
            hasCursor: root.cursorActive && root.focusSection === "addschedule"
            width: parent.width - addScheduleHint.implicitWidth - Style.space(8)
            text: root.tr("repeat.add") + " — " + (root.timeModeAbsolute && root.absoluteTime.trim() !== ""
                  ? root.absoluteTime.trim() : root.minutesToHhmm(root.customMinutes))
            fontSize: Style.font.bodySmall
            foreground: root.popupText
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.addSchedule()
          }

          Text {
            id: addScheduleHint
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.daysLabel(root.daysForRepeat())
            color: root.popupText
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          id: schedulesColumn
          width: parent.width
          spacing: Style.space(4)
          visible: root.scheduleRows.length > 0

          Repeater {
            model: root.scheduleRows

            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width - removeSchedule.width - Style.space(6)
                textFormat: Text.PlainText
                text: "#" + modelData.id + "  " + modelData.at + "  " + modelData.rest
                color: root.popupText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelActionButton {
                id: removeSchedule
                hasCursor: root.cursorActive && root.focusSection === "schedules" && root.focusIndex === index
                iconText: root.glyphCancel
                tooltipText: root.tr("repeat.remove")
                foreground: root.popupUrgent
                fontFamily: root.fontFamily
                onClicked: {
                  service.scheduleRemove(modelData.id)
                  Qt.callLater(function() { root.loadSchedules() })
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.scheduleRows.length === 0
          textFormat: Text.PlainText
          text: root.tr("repeat.none")
          color: root.popupText
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ---- advanced (TZ 9.4, 9.6) ----
        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.advanced")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          id: advancedColumn
          width: parent.width
          spacing: Style.space(6)

          // Each row writes the setting straight to shell.json through the
          // shell's own CLI — the widget's `settings` are read-only here.
          Repeater {
            model: [
              { key: "batteryGuard",      label: root.tr("adv.battery"), on: service.batteryGuard },
              { key: "quiet",             label: root.tr("adv.quiet"),   on: service.quiet },
              { key: "waitForInhibitors", label: root.tr("adv.wait"),    on: service.waitForInhibitors }
            ]

            delegate: Row {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(8)
              readonly property bool hot: root.cursorActive && root.focusSection === "advanced" && root.focusIndex === index

              MouseArea {
                width: parent.width
                height: Style.spacing.controlHeight
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSetting(modelData.key, !modelData.on)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: parent.hot ? Style.space(2) : 0
                  textFormat: Text.PlainText
                  text: (modelData.on ? root.glyphCheck + "  " : "     ") + modelData.label
                  color: modelData.on ? root.popupAccent : (parent.hot ? root.popupAccent : root.popupText)
                  font.family: root.fontFamily
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
            readonly property bool hot: root.cursorActive && root.focusSection === "advanced" && root.focusIndex === 3

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
                text: (service.overrideCommand !== "" ? root.glyphCheck + "  " : "     ") + root.tr("adv.dryRun")
                color: service.overrideCommand !== "" ? root.popupAccent : (parent.parent.hot ? root.popupAccent : root.popupText)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Text {
            width: parent.width
            visible: service.overrideCommand !== ""
            textFormat: Text.PlainText
            text: root.tr("adv.dryRunHint") + " (" + service.overrideCommand + ")"
            color: root.popupText
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: service.dnd
            textFormat: Text.PlainText
            text: root.tr("adv.dnd")
            color: root.popupUrgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- history (TZ 6.3) ----
        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          width: parent.width
          text: root.tr("section.history")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.historyRows

            delegate: Text {
              required property string modelData
              width: parent.width
              textFormat: Text.PlainText
              text: modelData
              color: root.popupText
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            width: parent.width
            visible: root.historyRows.length === 0
            textFormat: Text.PlainText
            text: root.tr("history.empty")
            color: root.popupText
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- launch ----
        Button {
          id: launchButton
          hasCursor: root.cursorActive && root.focusSection === "launch"
          width: parent.width
          text: {
            if (root.timeModeAbsolute)
              return root.absoluteTime.trim() === "" ? root.tr("launch.enterTime") : root.tr("launch.at", root.absoluteTime)
            return root.tr("launch.in", String(Math.round(root.customMinutes)))
          }
          fontSize: Style.font.body
          foreground: root.popupAccent
          fontFamily: root.fontFamily
          selected: true
          onClicked: root.startTimer()
        }

        // ---- active timer: reset ----
        PanelSeparator {
          visible: service.status !== "IDLE"
          foreground: root.foreground
        }

        Button {
          id: resetButton
          hasCursor: root.cursorActive && root.focusSection === "reset"
          width: parent.width
          visible: service.status !== "IDLE"
          text: root.tr("launch.reset")
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.resetTimer()
        }
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      panelFlick.contentY = 0
      service.refresh()
      cursorActive = false
      focusSection = "action"
      focusIndex = 0
      root.loadSchedules()
      root.loadHistory()
      selectedAction = String(service.defaultAction)
      selectedQuick = ""
      timeModeAbsolute = false
      if (service.status !== "IDLE" && service.timeLeft > 0) {
        customMinutes = Math.max(1, Math.min(1440, Math.round(service.timeLeft / 60)))
      } else {
        customMinutes = 30
      }
    }
  }
}
