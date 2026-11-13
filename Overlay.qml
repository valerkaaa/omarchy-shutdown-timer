import QtQuick 6.11
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Fullscreen countdown overlay, summoned by the daemon when the configured
// action is about to fire. Escape or «Cancel» aborts; Enter or «+5 minutes»
// postpones. Both go through the same control-file path as the bar menu, so a
// cancel can never be swallowed by this surface alone.
Item {
  id: root

  // ---------- input from shell ----------
  property var settings: ({})

  // ---------- theme ----------
  // Every text in the overlay sits on the CARD (popupBg), not on the raw
  // background, so contrast is measured against the card surface.
  readonly property color popupBg: Commons.Color.popups.background
  readonly property color background: Commons.Color.background
  readonly property color foreground: Model.readableOn(String(Commons.Color.popups.text), String(popupBg), 4.5)
  readonly property color urgent: Model.readableOn(String(Commons.Color.urgent), String(popupBg), 4.5)
  readonly property color accent: Model.readableOn(String(Commons.Color.accent), String(popupBg), 4.5)
  readonly property color popupBorder: Commons.Color.popups.border
  readonly property color muted: Commons.Color.muted
  readonly property string fontFamily: Style.font.family
  readonly property bool reducedMotion: settings && settings.reducedMotion === true

  // ---------- localization ----------
  readonly property string systemLang: Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en"
  readonly property string language: {
    var configured = ""
    if (settings && settings.language !== undefined && settings.language !== null) configured = String(settings.language)
    if (configured === "" || configured === "auto") return Model.resolveLang(systemLang, "en")
    return Model.resolveLang(configured, Model.resolveLang(systemLang, "en"))
  }
  function tr(key, args) { return Model.t(key, language, args) }

  // ---------- paths ----------
  readonly property string controlPath: {
    var pluginDir = String(Qt.resolvedUrl("control.sh")).replace(/^file:\/\/+/, "").replace(/\/control\.sh$/, "")
    return pluginDir + "/control.sh"
  }
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/plugins/shutdown-timer"

  // ---------- state ----------
  property bool opened: false
  property bool loaded: false
  property string status: "IDLE"
  property string action: "poweroff"
  property int timeLeft: 0
  property int targetTime: 0
  property int startTime: 0
  property int totalSeconds: 30
  property int tick: 0

  // ---------- IPC: omarchy-shell honor.shutdown-timer:overlay [show|hide|cancel|snooze] ----------
  IpcHandler {
    target: "honor.shutdown-timer:overlay"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    // Same code path as the Cancel button / Escape — lets the CLI (and tests)
    // exercise the user-facing cancel without a pointer.
    function cancel(): string { root.cancel(); return "ok" }
    function snooze(mins: string): string { root.snooze(parseInt(mins || "5", 10)); return "ok" }
  }

  // ---------- lifecycle ----------
  function open(payloadJson) {
    root.opened = true
    root.refresh()
    // A window summoned with nothing to count down is a dead modal: close it
    // as soon as the state says IDLE instead of drawing "00:00".
    idleGuard.restart()
  }

  Timer {
    id: idleGuard
    interval: 260
    repeat: false
    onTriggered: if (root.opened && root.status === "IDLE") root.close()
  }

  function close() {
    root.opened = false
    countdownTimer.stop()
  }

  function toggle() {
    if (root.opened) close()
    else open("{}")
  }

  // Both actions run control.sh, with a direct write as the fallback: an
  // overlay that closes on a cancel which never reached the daemon is the
  // worst outcome, because the machine powers off anyway.
  function send(command) {
    actionProc.command = ["bash", "-c",
      "bash '" + controlPath + "' send '" + command + "' 2>/dev/null || " +
      "{ mkdir -p '" + stateDir + "' && echo '" + command + "' > '" + stateDir + "/control'; }"]
    actionProc.running = true
  }

  function cancel() { send("cancel") }
  function snooze(mins) { send("snooze:" + String(mins === undefined ? 5 : mins)) }

  // ---------- read state.json ----------
  function refresh() {
    if (proc.running) return
    proc.command = ["bash", "-c",
      "cat '" + stateDir + "/state.json' 2>/dev/null || " +
      "echo '{\"status\":\"IDLE\",\"action\":\"\",\"timeLeft\":0,\"targetTime\":0}'"]
    proc.running = true
  }

  // ---------- computed ----------
  readonly property int displayedTime: {
    if (!root.loaded) return 0
    root.tick  // dependency: re-eval every tick
    if (root.status === "COUNTDOWN" || root.status === "COUNTDOWN_SCHED") {
      if (root.targetTime > 0) return Math.max(0, root.targetTime - Math.floor(Date.now() / 1000))
      return root.timeLeft
    }
    // Shown from the bar while the timer is still ACTIVE: read the real
    // remainder instead of the old "00:00" first frame.
    if (root.status === "ACTIVE" || root.status === "PAUSED") {
      if (root.targetTime > 0) return Math.max(0, root.targetTime - Math.floor(Date.now() / 1000))
      return root.timeLeft
    }
    return root.timeLeft
  }

  // 0 → just summoned, 1 → fired; drives the progress bar
  readonly property real remainingFraction: {
    var total = root.targetTime - root.startTime
    if (!(total > 0)) total = root.totalSeconds
    if (total <= 0) return 0
    return Model.clamp(root.displayedTime / total, 0, 1)
  }

  // ---------- polling state.json ----------
  Timer {
    id: pollTimer
    interval: 250
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---------- live tick for smooth countdown ----------
  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: { root.tick++; root.refresh() }
  }

  Process {
    id: proc
    running: false
    stdout: StdioCollector { id: stateOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var parsed = null
        try { parsed = JSON.parse(String(stateOut.text || "")) } catch(e) {}
        if (parsed && typeof parsed === "object") {
          var nextStatus = String(parsed.status || "IDLE")
          // An external cancel (control.sh, the bar menu) or a snooze ends the
          // countdown without touching this overlay; close so it does not linger.
          if (root.opened && root.status === "COUNTDOWN" && nextStatus !== "COUNTDOWN") root.close()
          root.loaded = true
          root.status = nextStatus
          root.action = String(parsed.action || "poweroff")
          root.timeLeft = typeof parsed.timeLeft === "number" ? parsed.timeLeft : 0
          root.targetTime = typeof parsed.targetTime === "number" ? parsed.targetTime : 0
          root.startTime = typeof parsed.startTime === "number" ? parsed.startTime : 0
          if (root.totalSeconds <= 0 && root.timeLeft > 0) root.totalSeconds = root.timeLeft
        }
      }
    }
  }

  Process {
    id: actionProc
    running: false
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      console.log("shutdown-timer overlay: action rc=" + exitCode)
      root.close()
    }
  }

  // ---------- fullscreen overlay surface ----------
  PanelWindow {
    id: panel
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: root.opened
    WlrLayershell.namespace: "omarchy-shutdown-timer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // keyboard: Escape cancels, Enter postpones. Parent is PanelWindow (an
    // Item), so anchors.fill works here.
    Item {
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (!root.opened) return
        if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.snooze(5); event.accepted = true }
      }
    }

    // fullscreen scrim. It has to be *darker* than the card: the card sits on
    // the theme background too, so a scrim painted in that same colour leaves
    // the card invisible — which is exactly what it did before.
    Rectangle {
      anchors.fill: parent
      color: Qt.darker(root.background, 2.2)
      opacity: 0.92
    }

    // ---------- card ----------
    Rectangle {
      id: card
      anchors.centerIn: parent
      // parent is the fullscreen PanelWindow; root is an unsized Item and its
      // width is 0, so measuring against it collapsed the card to nothing.
      width: Math.min(Style.space(560), parent.width * 0.8)
      height: cardColumn.implicitHeight + Style.space(96)
      radius: Math.round(Style.cornerRadius * 1.8)
      border.width: 1
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
      // The first frame has no state yet; drawing it would show "00:00" for a
      // moment, which reads as "it is firing now".
      opacity: root.loaded ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      // Same lit plate as the popup's hero: light at the top, deep at the
      // base, and the accent washing through it.
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.lighter(root.popupBg, 1.14) }
        GradientStop { position: 0.55; color: root.popupBg }
        GradientStop { position: 1.0; color: Qt.darker(root.popupBg, 1.16) }
      }

      Rectangle {
        anchors.fill: parent
        radius: card.radius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
          GradientStop { position: 0.6; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.03) }
          GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) }
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)
        height: 1
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.28)
      }

      Column {
        id: cardColumn
        anchors.fill: parent
        anchors.margins: Style.space(48)
        spacing: Style.space(18)

        // action label
        Text {
          width: parent.width
          text: Model.actionLabel(root.action, root.language)
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        // countdown number — strictly monospace so the digits do not jitter,
        // and large enough that it reads from across a room: this is the last
        // warning before the machine goes down.
        Text {
          width: parent.width
          text: Model.formatTime(root.displayedTime)
          textFormat: Text.PlainText
          color: root.displayedTime <= 10 ? root.urgent : root.foreground
          font.family: "monospace"
          font.bold: true
          font.pixelSize: Math.round(card.width * (root.displayedTime >= 100 ? 0.17 : 0.21))
          horizontalAlignment: Text.AlignHCenter
        }

        // progress: a gauge, not a hairline — it drains as the deadline nears
        Item {
          id: gauge
          width: parent.width
          height: Math.max(8, Style.space(8))
          readonly property color tint: root.displayedTime <= 10 ? root.urgent : root.accent

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          }

          Rectangle {
            id: gaugeFill
            width: Math.max(height, parent.width * root.remainingFraction)
            height: parent.height
            radius: height / 2
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Qt.lighter(gauge.tint, 1.25) }
              GradientStop { position: 1.0; color: gauge.tint }
            }
            color: gauge.tint
            Behavior on width {
              enabled: !root.reducedMotion
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // the lit head: the same pip the dial carries
            Rectangle {
              height: Math.max(6, gauge.height + 2)
              width: height
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              x: parent.width - width
              color: Qt.lighter(parent.color, 1.35)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.45)
            }
          }
        }

        // actions: cancel is a filled key, snooze a quiet pill — the same two
        // voices the popup uses.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Key {
            id: cancelBtn
            width: Math.max(Style.space(160), parent.width * 0.42)
            text: root.tr("overlay.cancel")
            role: "primary"
            accentColor: root.urgent
            ink: root.foreground
            surface: root.popupBg
            fontSize: Style.font.body
            onClicked: root.cancel()
          }

          Key {
            width: Math.max(Style.space(120), parent.width * 0.3)
            text: root.tr("overlay.snooze")
            role: "ghost"
            ink: root.foreground
            accentColor: root.accent
            surface: root.popupBg
            fontSize: Style.font.bodySmall
            onClicked: root.snooze(5)
          }
        }

        // The escape hatch has to be discoverable during the countdown, and at
        // 11 px, not the 9 px it used to be.
        Text {
          width: parent.width
          text: root.tr("overlay.hint")
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.62
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}