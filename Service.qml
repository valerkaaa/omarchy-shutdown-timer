import QtQuick 6.11
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Background service for the shutdown-timer bar widget. Owns the daemon
// lifecycle, polls state.json, and sends commands to the daemon via control.sh.
Item {
  id: root

  property var settings: ({})
  property bool notifyInstance: true

  // ---------- state ----------
  property bool loaded: false
  property bool ok: true
  property string error: ""
  property string status: "IDLE"       // IDLE | ACTIVE | COUNTDOWN | COUNTDOWN_SCHED | PAUSED
  property string action: ""
  property int timeLeft: 0
  property var targetTime: 0
  property string mode: ""
  property var startTime: 0
  property int snoozeCount: 0
  property string reason: ""
  property int scheduleCount: 0
  property bool dnd: false

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  // Overlay summonsing is handled by Panel.qml via Connections so the
  // Service itself stays stateless about which surface owns it.

  // ---------- settings ----------
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 1, 1, 60)
  readonly property int notifyEarlyMins: intSetting("notifyEarlyMins", 5, 0, 60)
  readonly property int overlaySeconds: intSetting("overlaySeconds", 30, 5, 120)
  readonly property string defaultAction: String(setting("defaultAction", "poweroff"))
  readonly property int snoozeMins: intSetting("snoozeMins", 5, 1, 60)
  readonly property int presetsRaw: 0
  readonly property string presets: String(setting("presets", "15,30,45,60,90,120"))
  // `omarchy bar set <id> <key> true` stores the STRING "true", so a strict
  // === true comparison silently reports every toggle as off.
  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (v === true || v === false) return v
    return String(v).toLowerCase() === "true"
  }

  readonly property bool quiet: boolSetting("quiet", false)
  readonly property bool batteryGuard: boolSetting("batteryGuard", false)
  readonly property int batteryThreshold: intSetting("batteryThreshold", 20, 5, 50)
  readonly property bool waitForInhibitors: boolSetting("waitForInhibitors", false)
  readonly property bool tickSound: boolSetting("tickSound", false)
  readonly property bool reducedMotion: boolSetting("reducedMotion", false)

  readonly property var presetList: {
    var out = []
    var parts = presets.split(",")
    for (var i = 0; i < parts.length && i < 6; i++) {
      var n = parseInt(String(parts[i]).trim(), 10)
      if (isFinite(n) && n >= 1 && n <= 1440) out.push(n)
    }
    return out.length > 0 ? out : [15, 30, 45, 60, 90, 120]
  }

  // ---------- language ----------
  // "auto" follows the session locale; anything else is taken literally and
  // resolved through Model.resolveLang, so a stale value cannot blank the UI.
  readonly property string systemLang: Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en"
  readonly property string language: {
    var configured = String(setting("language", "auto"))
    if (configured === "auto" || configured === "") return Model.resolveLang(systemLang, "en")
    return Model.resolveLang(configured, Model.resolveLang(systemLang, "en"))
  }

  function tr(key, args) {
    return Model.t(key, language, args)
  }

  // ---------- dry run (live) ----------
  // The daemon reads <state>/action-override on every firing; surface the same
  // file here so the UI can say "the PC will not actually power off".
  property string overrideCommand: ""
  FileView {
    path: root.stateDir + "/action-override"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.overrideCommand = String(text() || "").trim()
    onLoadFailed: root.overrideCommand = ""
  }

  // ---------- paths ----------
  readonly property string pluginDir: String(Qt.resolvedUrl("control.sh")).replace(/^file:\/\//, "").replace(/\/control\.sh$/, "")
  readonly property string controlPath: pluginDir + "/control.sh"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/plugins/shutdown-timer"

  // ---------- settings helpers ----------
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function numSetting(name, fallback, min, max) {
    var value = parseFloat(String(setting(name, fallback)))
    if (!isFinite(value)) value = fallback
    return Model.clamp(value, min, max)
  }

  function intSetting(name, fallback, min, max) {
    return Math.round(numSetting(name, fallback, min, max))
  }

  // ---------- write settings for daemon ----------
  Process {
    id: writeSettingsProc
    running: false
    command: ["bash", "-c",
      "mkdir -p '" + stateDir + "' && cat > '" + stateDir + "/settings.json' <<'SETTINGSEOF'\n" +
      JSON.stringify({
        notifyEarlyMins: notifyEarlyMins,
        overlaySeconds: overlaySeconds,
        language: language,
        snoozeMins: snoozeMins,
        quiet: quiet,
        batteryGuard: batteryGuard,
        batteryThreshold: batteryThreshold,
        waitForInhibitors: waitForInhibitors,
        reducedMotion: reducedMotion
      }) +
      "\nSETTINGSEOF"]
  }

  function writeSettings() {
    writeSettingsProc.command = ["bash", "-c",
      "mkdir -p '" + stateDir + "' && cat > '" + stateDir + "/settings.json' <<'SETTINGSEOF'\n" +
      JSON.stringify({
        notifyEarlyMins: notifyEarlyMins,
        overlaySeconds: overlaySeconds,
        language: language,
        snoozeMins: snoozeMins,
        quiet: quiet,
        batteryGuard: batteryGuard,
        batteryThreshold: batteryThreshold,
        waitForInhibitors: waitForInhibitors,
        reducedMotion: reducedMotion
      }) +
      "\nSETTINGSEOF"]
    writeSettingsProc.running = true
  }

  // ---------- daemon lifecycle ----------
  function ensureDaemon() {
    if (controlPath === "") return
    ensureProc.command = ["bash", controlPath, "ensure"]
    ensureProc.running = true
  }

  Process {
    id: ensureProc
    running: false
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {}
  }

  // ---------- polling state.json ----------
  function refresh() {
    if (proc.running || controlPath === "") return
    proc.command = ["bash", controlPath, "get-state"]
    proc.running = true
  }

  function sendCommand(cmd) {
    if (controlPath === "") return
    cmdProc.command = ["bash", controlPath, "send", cmd]
    cmdProc.running = true
  }

  function setTimer(mins, act) {
    if (act === undefined || act === "") act = defaultAction
    sendCommand("set:" + String(mins) + ":" + act)
  }

  function setTimerAbsolute(hhmm, act) {
    if (act === undefined || act === "") act = defaultAction
    sendCommand("set-abs:" + hhmm + ":" + act)
  }

  function cancel() {
    sendCommand("cancel")
  }

  function snooze(mins) {
    sendCommand("snooze:" + String(mins === undefined ? 5 : mins))
  }

  function pause() {
    sendCommand("pause")
  }

  function resume() {
    sendCommand("resume")
  }

  function reset() {
    sendCommand("reset")
  }

  function setOverride(cmd) {
    overrideProc.command = ["bash", controlPath, "override", cmd]
    overrideProc.running = true
  }

  Process {
    id: overrideProc
    running: false
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  function scheduleAdd(hhmm, days, act) {
    sendCommand("schedule-add:" + String(Date.now()).slice(-6) + ":" + hhmm + ":" + days + ":" + (act || defaultAction))
  }

  function scheduleRemove(id) {
    sendCommand("schedule-remove:" + String(id))
  }

  Process {
    id: proc
    running: false
    stdout: StdioCollector { id: stateOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        applyState(stateOut.text)
      } else {
        loaded = true
        ok = false
        error = "Could not read shutdown-timer state"
      }
    }
  }

  Process {
    id: cmdProc
    running: false
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      // Force a refresh so the bar reflects the new state quickly
      root.refresh()
    }
  }

  function applyState(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      parsed = null
    }
    loaded = true
    if (!parsed || typeof parsed !== "object") {
      ok = false
      error = "Could not read shutdown-timer state"
      return
    }
    ok = true
    error = ""
    status = String(parsed.status || "IDLE")
    action = String(parsed.action || "")
    timeLeft = Model.known(parsed.timeLeft) ? parsed.timeLeft : 0
    targetTime = parsed.targetTime || 0
    mode = String(parsed.mode || "")
    startTime = parsed.startTime || 0
    snoozeCount = Model.known(parsed.snoozeCount) ? parsed.snoozeCount : 0
    reason = String(parsed.reason || "")
    scheduleCount = Model.known(parsed.scheduleCount) ? parsed.scheduleCount : 0
    dnd = parsed.dnd === true
  }

  // ---------- periodic poll ----------
  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---------- startup ----------
  Component.onCompleted: {
    writeSettings()
    // Give it a moment then ensure daemon
    Qt.callLater(function() { root.ensureDaemon() })
  }

  // The daemon reads settings.json for its notification language and timings;
  // a settings change must reach that file, or a language switch would only
  // apply to the QML surfaces and the alerts would stay in the old language.
  onLanguageChanged: writeSettings()
  onNotifyEarlyMinsChanged: writeSettings()
  onOverlaySecondsChanged: writeSettings()
  onSnoozeMinsChanged: writeSettings()
  onQuietChanged: writeSettings()
  onBatteryGuardChanged: writeSettings()
  onBatteryThresholdChanged: writeSettings()
  onWaitForInhibitorsChanged: writeSettings()
}
