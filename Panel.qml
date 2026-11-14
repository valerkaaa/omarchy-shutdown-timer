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
  // Idle takes exactly one icon slot (27 px), like every other bar icon; the
  // extra gutter exists only while the countdown label is on screen, so the
  // widget never sits in a wider slot than its neighbours for no reason.
  implicitWidth: vertical
                 ? button.implicitWidth
                 : button.implicitWidth + (timeLabel.visible ? timeLabel.implicitWidth + Style.space(2) + Style.space(4) : 0)
  implicitHeight: vertical
                  ? button.implicitHeight + (verticalTime.visible ? verticalTime.implicitHeight : 0)
                  : button.implicitHeight

  // ---------- theme ----------
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  // The surface the bar icon is painted on; the state badge cuts itself out
  // of the mark in this colour (black on a light theme looked like dirt).
  readonly property color barBackground: bar ? bar.background : Commons.Color.bar.background
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

  // How much of the timer is left, 0…1, or -1 when nothing runs. The bar
  // mark closes its ring with this: no extra element, one parameter.
  readonly property real remainingFraction: {
    if (service.status === "IDLE") return -1
    var total = Number(service.targetTime) - Number(service.startTime)
    if (!(total > 0)) return -1
    return Math.max(0, Math.min(1, Number(service.timeLeft) / total))
  }

  readonly property bool barDimmed: false
  // Set for a moment after a wheel gesture on the bar icon, so the number the
  // gesture produced is visible without opening the popup.
  property string wheelHint: ""
  Timer {
    id: wheelHintTimer
    interval: 1600
    repeat: false
    onTriggered: root.wheelHint = ""
  }
  readonly property string barTooltip: {
    if (root.wheelHint !== "") return root.wheelHint
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
  // Digits typed on the popup, cleared when the panel closes.
  property string typedMinutes: ""

  // ---------- repeat / schedule state ----------
  property string repeatMode: "once"          // once | daily | weekdays | weekends
  property var scheduleRows: []               // [{id, at, days, action}]
  // "" | "repeat" | "more" | "history" — the rare settings open in place
  // instead of sitting between the user and the launch key.
  property string trayOpen: ""
  // Cancel asks once before it fires: the button is a decision, the hold on
  // the bar icon and Esc in the overlay stay one-action escapes.
  property bool confirmOpen: false

  function askCancel() {
    if (service.status === "IDLE") { root.close(); return }
    root.confirmOpen = true
  }

  function doCancel() {
    root.confirmOpen = false
    service.cancel()
    root.close()
  }

  // True while the dial is being dragged: the hero then shows the value
  // under the finger instead of the running remainder.
  property bool scrubbing: false

  readonly property string targetClock: {
    var t = Number(service.targetTime)
    if (service.status === "IDLE" || !(t > 0)) t = Math.floor(Date.now() / 1000) + Math.round(root.customMinutes) * 60
    return Qt.formatDateTime(new Date(t * 1000), "HH:mm")
  }

  readonly property int heroBaseMinutes: Math.max(1, Math.round(service.timeLeft / 60))
  readonly property int heroTotalMinutes: {
    var t = Number(service.targetTime) - Number(service.startTime)
    return t > 0 ? Math.max(1, Math.round(t / 60)) : 720
  }
  // 0 at the start of the timer, 1 at the deadline: drives the colour of the
  // ring, the way a HUD shifts from calm to alarm.
  readonly property real urgency: {
    if (service.status === "IDLE") return 0
    var f = root.remainingFraction
    if (f < 0) return 0
    return Math.max(0, Math.min(1, 1 - f))
  }
  function mixColor(a, b, t) {
    var k = Math.max(0, Math.min(1, t))
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                    a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
  }
  // The ring is calm accent at the start and urgent at the deadline, with the
  // whole ramp in between instead of two hard states.
  readonly property color dialTint: mixColor(root.popupAccent, root.popupUrgent, root.urgency)

  // What the dial is full of: the dragged value while scrubbing, the whole
  // proposed time in IDLE, the real remainder while a timer runs.
  readonly property real heroFraction: {
    if (root.scrubbing) {
      var span = service.status === "IDLE" ? 720 : root.heroTotalMinutes
      return Math.max(0, Math.min(1, root.customMinutes / Math.max(1, span)))
    }
    if (service.status === "IDLE") return 1
    var f = root.remainingFraction
    return f < 0 ? 1 : f
  }

  // The one figure on the dial. In IDLE it is the time that would be set,
  // not a sentence: the number is the object, the caption explains it.
  readonly property string heroText: {
    if (root.scrubbing || service.status === "IDLE")
      return Model.formatTime(Math.max(1, Math.round(root.customMinutes)) * 60)
    return Model.formatTime(service.timeLeft)
  }

  readonly property string heroCaption: {
    if (root.scrubbing && service.status !== "IDLE") {
      var d = root.customMinutes - root.heroBaseMinutes
      return root.tr("hero.delta", (d >= 0 ? "+" : "") + String(d))
    }
    if (service.status === "IDLE") return root.tr("state.none")
    if (service.status === "PAUSED") return root.tr("state.paused", Model.actionLabel(service.action, language))
    if (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED")
      return root.tr("state.countdown", Model.actionLabel(service.action, language))
    return root.tr("state.active", Model.actionLabel(service.action, language))
  }

  // A snooze past the limit is refused by the daemon without an error on the
  // wire; the panel notices the deadline did not move and says so, instead of
  // looking like nothing was pressed.
  property bool snoozeRefused: false
  property real snoozeBefore: 0
  Timer {
    id: snoozeCheck
    interval: 600
    repeat: false
    onTriggered: {
      if (Number(service.targetTime) <= root.snoozeBefore) {
        root.snoozeRefused = true
        snoozeRefusedTimer.restart()
      }
    }
  }
  Timer {
    id: snoozeRefusedTimer
    interval: 2600
    repeat: false
    onTriggered: root.snoozeRefused = false
  }

  function snoozeNow() {
    root.snoozeBefore = Number(service.targetTime)
    service.snooze(service.snoozeMins)
    snoozeCheck.restart()
  }

  // One line under the dial: what the ring does, or how to get out.
  readonly property string heroHint: {
    if (root.snoozeRefused) return root.tr("hero.snoozeRefused")
    if (service.status === "IDLE") return root.tr("state.noneHint")
    return root.tr("hero.scrub")
  }

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
    out.push("action")
    out.push("dial")
    out.push("tray")
    if (trayOpen === "repeat") {
      out.push("repeat", "addschedule")
      if (scheduleRows.length > 0) out.push("schedules")
    }
    if (trayOpen === "more") out.push("advanced")
    out.push("launch")
    return out
  }

  function sectionCount(section) {
    if (section === "advanced") return 5
    if (section === "schedules") return scheduleRows.length
    if (section === "hero") return 3
    if (section === "tray") return 3
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
      if (focusSection === "hero" || focusSection === "advanced" ||
          focusSection === "schedules" || focusSection === "tray") {
        focusIndex = Math.max(0, Math.min(sectionCount(focusSection) - 1, focusIndex + dx))
      } else if (focusSection === "dial") {
        // Left/right on the dial is a slider: one minute per step, five with
        // the same modifier the wheel uses.
        customMinutes = Math.max(1, Math.min(720, Math.round(customMinutes) + dx * 5))
      } else if (focusSection === "action") {
        selectedAction = cycleIn(actionOptions, selectedAction, dx)
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
      else if (focusIndex === 1) root.snoozeNow()
      else root.askCancel()
    } else if (focusSection === "dial") {
      root.startTimer()
    } else if (focusSection === "tray") {
      var keys = ["repeat", "more", "history"]
      var key = keys[focusIndex]
      if (key) trayOpen = (trayOpen === key ? "" : key)
    } else if (focusSection === "addschedule") {
      addSchedule()
    } else if (focusSection === "schedules") {
      var row = scheduleRows[focusIndex]
      if (row) { service.scheduleRemove(row.id); Qt.callLater(function() { root.loadSchedules() }) }
    } else if (focusSection === "advanced") {
      if (focusIndex === 4) {
        service.setOverride(service.overrideCommand === "" ? "echo" : "off")
      } else {
        var keys = ["batteryGuard", "quiet", "waitForInhibitors", "ambientFade"]
        var ons = [service.batteryGuard, service.quiet, service.waitForInhibitors, service.ambientFade]
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

  function wheelAdjust(delta) {
    var next
    if (service.status === "IDLE") {
      next = Math.max(1, Math.min(720, Math.round(customMinutes) + delta))
      customMinutes = next
    } else if (service.status === "ACTIVE" || service.status === "PAUSED") {
      var left = Math.max(1, Math.round(service.timeLeft / 60))
      next = Math.max(1, Math.min(720, left + delta))
      service.setTimer(next, service.action || selectedAction)
      customMinutes = next
    } else {
      return
    }
    root.wheelHint = root.tr("wheel.pending", String(next))
    wheelHintTimer.restart()
  }

  function quickSet(mins) {
    service.setTimer(mins, selectedAction)
    close()
  }

  function startTimer() {
    var mins = Math.round(customMinutes)
    if (!mins || mins < 1) mins = 1
    if (mins > 720) mins = 720
    service.setTimer(mins, selectedAction)
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
    // The dial's angle math, so the scrub gesture can be proven from a script
    // without a pointer: feed it a point in the ring's coordinates.
    // The confirm sheet, provable from a script.
    function debugConfirm(): string {
      root.askCancel()
      return JSON.stringify({ open: root.confirmOpen, status: service.status })
    }
    function debugConfirmAnswer(answer: string): string {
      if (String(answer) === "yes") root.doCancel()
      else root.confirmOpen = false
      return JSON.stringify({ open: root.confirmOpen, status: service.status })
    }

    // Hold-to-cancel, provable from a script: start the hold, wait, end it.
    function debugHoldStart(): string {
      if (service.status === "IDLE") return JSON.stringify({ started: false, reason: "idle" })
      root.holding = true
      holdFill.restart()
      holdTimer.restart()
      return JSON.stringify({ started: true, status: service.status })
    }
    function debugHoldEnd(): string {
      var fired = holdTimer.fired
      holdTimer.stop(); holdFill.stop()
      root.holding = false; root.holdProgress = 0
      if (fired) service.cancel()
      return JSON.stringify({ fired: fired, status: service.status })
    }

    // The wheel gesture, provable from a script: same code path the handler
    // calls, without a pointer.
    function debugWheel(step: string): string {
      root.wheelAdjust(parseInt(step || "5", 10))
      return JSON.stringify({ minutes: root.customMinutes, status: service.status,
                              hint: root.wheelHint })
    }

    function debugDial(point: string): string {
      var parts = String(point || "").split(",")
      var x = Number(parts[0] || 0)
      var y = Number(parts[1] || 0)
      try {
        var m = dial.minutesAt(x, y)
        return JSON.stringify({ minutes: m, max: dial.scrubMax, x: x, y: y, size: Math.round(dial.width) })
      } catch (e) {
        return JSON.stringify({ error: String(e) })
      }
    }

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
          icon: Math.round(heroAperture.width),
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
          iconWidth: Math.round(heroAperture.width),
          labelsX: Math.round(heroLabels.x),
          labelsWidth: Math.round(heroLabels.width),
          buttonsX: Math.round(heroButtons.x),
          buttonsWidth: Math.round(heroButtons.width),
          // the label column must start after the icon and end before the buttons
          iconClearsLabels: heroLabels.x >= heroAperture.width,
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
        // Match the neighbours by painted ink, not by box size. The stock
        // Nerd Font glyphs beside this one paint 11–12 px of ink inside the
        // 16 px icon canvas; this mark paints ~0.8 × iconSize, so 15 px lands
        // on the same optical size instead of overpowering the bar. (Measured
        // on the live bar at scale 1.25: 24 px → 18 px of ink, 20 px → 16,
        // 16 px → 12.8, 15 px → 12.)
        iconSize: Style.bar.iconCanvas
        reducedMotion: service.reducedMotion
        color: root.barColor
        cutout: root.barBackground
        variant: root.iconVariant
        fraction: root.remainingFraction
        holdProgress: root.holdProgress
      }
    }

    // A wheel over the icon sets the time without opening the popup: ±5
    // minutes, ±15 with Shift. In IDLE it stages the value; while a timer
    // runs it moves the deadline. No other bar widget in Omarchy does this.
    WheelHandler {
      target: button
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var step = (event.modifiers & Qt.ShiftModifier) ? 15 : 5
        root.wheelAdjust(event.angleDelta.y > 0 ? step : -step)
      }
    }

  }

  // Press and hold the icon for half a second to cancel, without opening the
  // popup: the ring fills while the hold lasts, so the gesture is visible
  // before it fires. A short click still opens the menu; right-click opens it
  // too (the old right-click-cancel was invisible and conflicted with the
  // hold).
  property real holdProgress: 0
  property bool holding: false

  MouseArea {
    id: barPress
    anchors.fill: button
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      if (service.status === "IDLE") return
      root.holding = true
      holdFill.restart()
      holdTimer.restart()
    }

    // A click is handled by onClicked, the same path the right button already
    // used: opening the panel from onReleased left the press unclaimed by the
    // popup manager, so the left button silently did nothing.
    property bool holdConsumed: false

    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      var fired = holdTimer.fired
      holdTimer.stop()
      holdFill.stop()
      root.holding = false
      root.holdProgress = 0
      holdConsumed = fired
      if (fired) service.cancel()
    }

    onCanceled: {
      holdTimer.stop(); holdFill.stop(); root.holding = false; root.holdProgress = 0
      holdConsumed = false
    }

    onClicked: function(mouse) {
      if (holdConsumed) { holdConsumed = false; return }
      root.toggle()
    }
  }

  Timer {
    id: holdTimer
    interval: 500
    repeat: false
    property bool fired: false
    onRunningChanged: if (running) fired = false
    onTriggered: fired = true
  }

  NumberAnimation {
    id: holdFill
    target: root
    property: "holdProgress"
    from: 0
    to: 1
    duration: 500
    easing.type: Easing.Linear
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
    // 11 px, not the shell caption (10): TZ sets a floor and the bar is the
    // one place the user reads without leaning in.
    font.pixelSize: Style.font.bodySmall
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
        font.pixelSize: Style.font.bodySmall
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
      blocked: false
      onCloseRequested: if (root.confirmOpen) root.confirmOpen = false; else root.close()
      // Arrows start the cursor; until then Enter keeps its old meaning
      // ("launch the timer now").
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      // Return emits BOTH returnRequested and activateRequested, so the
      // activation lives in one place — wiring the same action to both
      // handlers would run it twice (double-add, toggles cancelling out).
      onActivateRequested: {
        if (root.confirmOpen) { root.doCancel(); return }
        if (root.cursorActive) root.activateCursor(); else root.startTimer()
      }
      onDeleteRequested: {
        if (root.cursorActive && root.focusSection === "schedules" && root.scheduleRows[root.focusIndex]) {
          service.scheduleRemove(root.scheduleRows[root.focusIndex].id)
          Qt.callLater(function() { root.loadSchedules() })
        }
      }
      onTextKey: function(t) {
        // Digits type the minutes directly: "4" "5" is 45, not a preset.
        if (t >= "0" && t <= "9") {
          var typed = root.typedMinutes
          var next = (typed === "" ? t : typed + t)
          if (next.length > 3) next = t
          root.typedMinutes = next
          var n = parseInt(next, 10)
          if (n >= 1) root.customMinutes = Math.min(720, n)
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

        // ---- action: four segments, no dropdown, no section header ----
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: [
              { value: "poweroff",  label: root.tr("action.poweroff") },
              { value: "reboot",    label: root.tr("action.reboot") },
              { value: "suspend",   label: root.tr("action.suspend") },
              { value: "hibernate", label: root.tr("action.hibernate") }
            ]

            delegate: Key {
              required property var modelData
              width: (actionRow.width - Style.space(24) - Style.space(30)) / 4
              text: modelData.label
              role: "tab"
              selected: root.selectedAction === modelData.value
              uppercase: true
              tracking: 0.6
              ink: root.selectedAction === modelData.value ? root.popupAccent : root.popupText
              accentColor: root.popupAccent
              surface: root.popupSurface
              fontSize: Style.font.bodySmall
              hasCursor: root.cursorActive && root.focusSection === "action"
                         && root.actionOptions.indexOf(root.selectedAction) === index
              onClicked: root.selectedAction = modelData.value
            }
          }

          Key {
            width: Style.space(34)
            text: "✕"
            role: "ghost"
            ink: root.popupText
            accentColor: root.popupAccent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            onClicked: root.close()
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
          border.color: Qt.rgba(root.popupAccent.r, root.popupAccent.g, root.popupAccent.b, 0.12)

          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(root.popupSurface, 1.16) }
            GradientStop { position: 0.55; color: root.popupSurface }
            GradientStop { position: 1.0; color: Qt.darker(root.popupSurface, 1.14) }
          }

          // The accent wash: the plate is not grey, it belongs to the state.
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: hero.radius - 1
            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.rgba(root.popupAccent.r, root.popupAccent.g, root.popupAccent.b, 0.20) }
              GradientStop { position: 0.6; color: Qt.rgba(root.popupAccent.r, root.popupAccent.g, root.popupAccent.b, 0.05) }
              GradientStop { position: 1.0; color: Qt.rgba(root.popupAccent.r, root.popupAccent.g, root.popupAccent.b, 0.10) }
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
              color: Qt.rgba(root.popupText.r, root.popupText.g, root.popupText.b, 0.045)
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
              color: Qt.rgba(root.popupText.r, root.popupText.g, root.popupText.b, 0.045)
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
              color: Qt.rgba(root.popupAccent.r, root.popupAccent.g, root.popupAccent.b, 0.13)
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
            color: root.popupText
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
            color: service.ambientFade ? root.popupAccent : root.popupText
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
            text: "T-" + Model.formatTime(service.status === "IDLE" ? root.customMinutes * 60 : service.timeLeft)
            color: root.popupText
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
            text: "TARGET " + root.targetClock
            color: root.popupText
            opacity: 0.68
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1.0
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
                fraction: root.heroFraction
                running: service.status !== "IDLE"
                paused: service.status === "PAUSED"
                tint: root.dialTint
                ink: root.popupText
                scrubbing: root.scrubbing
                scrubMinutes: root.customMinutes
                scrubMax: 720
                reducedMotion: service.reducedMotion
                focused: root.cursorActive && root.focusSection === "dial"
                deltaMode: service.status !== "IDLE"
                baseMinutes: root.heroBaseMinutes
                onScrubbed: function(m) {
                  root.scrubbing = true
                  root.customMinutes = Math.max(1, m)
                }
                onClicked: if (service.status === "IDLE") root.startTimer()
                onScrubFinished: function(m) {
                  var next = Math.max(1, m)
                  if (service.status !== "IDLE") {
                    // A drag while running moves the deadline; it does not
                    // restart the countdown from an absolute angle.
                    service.setTimer(next, service.action || root.selectedAction)
                  }
                  root.customMinutes = next
                  root.scrubbing = false
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
                  text: root.glyphForAction(root.selectedAction)
                  color: root.dialTint
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
                  textFormat: Text.PlainText
                  text: root.heroText
                  color: (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED")
                         ? root.popupUrgent : root.popupText
                  font.family: "monospace"
                  font.pixelSize: Math.max(40, Math.round(dialBox.width * 0.25))
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  id: heroLabels
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: String(root.heroCaption).toUpperCase()
                  color: root.popupText
                  opacity: 0.72
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1.1
                  elide: Text.ElideRight
                }

                // The aperture is the machine's own gesture: open while
                // there is time, closing as the deadline arrives, shut when
                // the action fires. No candle, no flame, no glow.
                ApertureTimer {
                  id: heroAperture
                  anchors.horizontalCenter: parent.horizontalCenter
                  size: Math.round(dialBox.width * 0.30)
                  fraction: service.status === "IDLE" ? 1 : root.heroFraction
                  ink: root.popupText
                  alarmInk: root.popupUrgent
                  alarm: (service.status === "COUNTDOWN" || service.status === "COUNTDOWN_SCHED")
                  reducedMotion: service.reducedMotion
                }
              }
            }

            Text {
              width: hero.width - Style.space(28)
              anchors.horizontalCenter: parent.horizontalCenter
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.heroHint
              color: root.popupText
              opacity: 0.62
              font.family: root.fontFamily
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
            text: service.status === "PAUSED" ? root.tr("btn.resume") : root.tr("btn.pause")
            role: "ghost"
            ink: root.popupText
            accentColor: root.popupAccent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 0
            onClicked: service.status === "PAUSED" ? service.resume() : service.pause()
          }

          Key {
            width: (parent.width - Style.space(12)) / 3
            text: "+" + service.snoozeMins + " " + root.tr("unit.min")
            role: "ghost"
            ink: root.popupText
            accentColor: root.popupAccent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 1
            onClicked: root.snoozeNow()
          }

          Key {
            width: (parent.width - Style.space(12)) / 3
            text: root.tr("btn.cancel")
            role: "danger"
            ink: root.popupText
            accentColor: root.popupAccent
            dangerColor: root.popupUrgent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            hasCursor: root.cursorActive && root.focusSection === "hero" && root.focusIndex === 2
            onClicked: root.askCancel()
          }
        }

        // ---- the dial and the wheel are the input: no presets, no field ----

        // ---- tray: the rare settings, opened in place ----
        Row {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: [
              { key: "repeat",  label: root.tr("tray.schedule") },
              { key: "more",    label: root.tr("tray.more") },
              { key: "history", label: root.tr("tray.history") }
            ]

            delegate: Key {
              required property var modelData
              width: (parent.width - Style.space(12)) / 3
              text: (root.trayOpen === modelData.key ? "▾ " : "▸ ") + modelData.label
              hasCursor: root.cursorActive && root.focusSection === "tray" && root.focusIndex === index
              role: root.trayOpen === modelData.key ? "selected" : "ghost"
              ink: root.popupText
              accentColor: root.popupAccent
              surface: root.popupSurface
              fontSize: Style.font.bodySmall
              onClicked: root.trayOpen = (root.trayOpen === modelData.key ? "" : modelData.key)
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.trayOpen === "repeat"

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
            onChanged: function(v) { root.repeatMode = v }
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
              font.pixelSize: Style.font.bodySmall
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
                  font.pixelSize: Style.font.bodySmall
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
            font.pixelSize: Style.font.bodySmall
          }
        }

        Column {
          id: advancedColumn
          width: parent.width
          spacing: Style.space(6)
          visible: root.trayOpen === "more"

          // Each row writes the setting straight to shell.json through the
          // shell's own CLI — the widget's `settings` are read-only here.
          Repeater {
            model: [
              { key: "batteryGuard",      label: root.tr("adv.battery"), on: service.batteryGuard },
              { key: "quiet",             label: root.tr("adv.quiet"),   on: service.quiet },
              { key: "waitForInhibitors", label: root.tr("adv.wait"),    on: service.waitForInhibitors },
              { key: "ambientFade",       label: root.tr("adv.fade"),    on: service.ambientFade }
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
            readonly property bool hot: root.cursorActive && root.focusSection === "advanced" && root.focusIndex === 4

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
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: service.dnd
            textFormat: Text.PlainText
            text: root.tr("adv.dnd")
            color: root.popupUrgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(3)
          visible: root.trayOpen === "history"

          Repeater {
            model: root.historyRows

            delegate: Text {
              required property string modelData
              width: parent.width
              textFormat: Text.PlainText
              text: modelData
              color: root.popupText
              opacity: 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- launch: always on the first screen, never below the fold ----
        Key {
          id: launchButton
          width: parent.width
          text: service.status === "IDLE"
                ? root.tr("launch.in", String(Math.round(root.customMinutes)))
                : root.tr("launch.update", String(Math.round(root.customMinutes)))
          role: "primary"
          bold: true
          ink: root.popupText
          accentColor: root.popupAccent
          surface: root.popupSurface
          fontSize: Style.font.body
          hasCursor: root.cursorActive && root.focusSection === "launch"
          onClicked: root.startTimer()
        }
      }
    }

    // ---- cancel confirmation ----
    Rectangle {
      id: confirmSheet
      z: 20
      anchors.fill: parent
      anchors.margins: Style.space(2)
      visible: root.confirmOpen
      radius: Math.round(Style.cornerRadius * 1.4)
      color: root.popupSurface
      border.width: 1
      border.color: Qt.rgba(root.popupUrgent.r, root.popupUrgent.g, root.popupUrgent.b, 0.45)

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        spacing: Style.space(10)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.tr("confirm.title")
          color: root.popupText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.letterSpacing: 0.6
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.tr("confirm.body", [Model.formatTime(service.timeLeft),
                        Model.actionLabel(service.action || root.selectedAction, root.language)])
          color: root.popupText
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Key {
            width: Style.space(150)
            text: root.tr("confirm.keep")
            role: "ghost"
            ink: root.popupText
            accentColor: root.popupAccent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            onClicked: root.confirmOpen = false
          }

          Key {
            width: Style.space(150)
            text: root.tr("confirm.yes")
            role: "danger"
            ink: root.popupText
            accentColor: root.popupAccent
            dangerColor: root.popupUrgent
            surface: root.popupSurface
            fontSize: Style.font.bodySmall
            onClicked: root.doCancel()
          }
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
      trayOpen = ""
      confirmOpen = false
      root.loadSchedules()
      root.loadHistory()
      selectedAction = String(service.defaultAction)
      selectedQuick = ""
      typedMinutes = ""
      timeModeAbsolute = false
      if (service.status !== "IDLE" && service.timeLeft > 0) {
        customMinutes = Math.max(1, Math.min(1440, Math.round(service.timeLeft / 60)))
      } else {
        customMinutes = 30
      }
    }
  }
}
