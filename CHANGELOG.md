# Changelog

## 3.0.4 — the last second, and the token

- A pause written while the daemon was inside its final checks was recorded as
  PAUSED and then outrun by the action: the last-moment gate only knew cancel
  (IDLE) and a re-armed timer (ACTIVE with a future target), so a PAUSED state
  fell through to `do_action`. A pause now stops the firing the same way a
  cancel does, in both the ACTIVE and the COUNTDOWN branch, and says so in the
  log. `tests/test_pause_final_gate.sh` holds the daemon inside the checks with
  a slow `pgrep` and fails on the old code (`IDLE` instead of `PAUSED`).
- The webhook URL never becomes a command-line argument. It usually carries the
  token of the service it posts to, and `/proc/<pid>/cmdline` is world-readable
  on a stock Linux desktop, so `curl` now reads its whole request from a config
  on stdin (`-K -`). A URL carrying a newline or another control character is
  refused instead of being pasted into that config, where it would add
  directives of its own. `tests/test_webhook_args.sh` reproduces the leak on the
  old code and checks a real POST against a local server.
- The settings writer in `Service.qml` no longer puts the settings JSON into
  `bash -c`: the payload goes to the writer's stdin, and the write lands on a
  temporary file that is renamed over `settings.json`, so a change during a
  slider drag can neither leak the URL through argv nor leave the daemon
  reading half a file.
- The mm/ss boxes are read-only to Qt for life and take their digits from a key
  handler. A writable `QQuickTextInput` makes Qt pull the *whole* clipboard on
  every clipboard change (QTBUG-149610, fixed in Qt 6.12.1), and on 6.12 even
  `setReadOnly(false)` performs that read — so a field that turns editable when
  the panel opens still pays. Measured here on Qt 6.12.0 with a 100 MB
  clipboard: writable field 407 MB peak RSS, read-only field 111 MB, and
  "read-only until the panel opens" 409 MB, i.e. no better at the moment it
  matters. Read-only for life: zero reads, and typing, the 720-minute clamp,
  Tab and Backspace now live in `typeInto()`.
  `tests/test_exact_fields.sh` drives the live panel with `wtype` and checks
  all four, plus that both fields really are read-only.
- `tools/acceptance.sh` disarms its own dry run. The checks arm
  `override echo`, and an exiting run used to leave it behind: the next real
  timer would only write a line to the log instead of powering off. A trap now
  cancels the timer and turns the override off on every exit path.

## 3.0.3 — the wheel keeps up

- Two quick notches of the wheel while a timer ran were counted from the same
  stale remaining time, so the second one changed nothing: 30 -> 35 -> 35. The
  wheel now continues from the value the widget itself set, as long as that
  value is fresh and the daemon's target still matches it — a timer re-armed
  elsewhere (a preset, the field, another widget) drops the fresh base and the
  daemon is asked again. Found by the gesture test, which failed one run in
  three on a loaded machine.
- `tests/test_absolute.sh` waited a fixed 0.4 s for the daemon to apply a
  command and then read the state; under load it read the previous target and
  called a working daemon broken. It now waits for the effect.
- `tools/acceptance.sh` kept only the last line of a failing test, which is not
  enough to tell a defect from a flake — every test's full output now goes to
  `/tmp/shutdown-timer-acceptance-tests.log`. Its QML check also matched
  Omarchy's own `network/Panel.qml` binding loop; it is scoped to this plugin's
  files now.


## 3.0.2 — the cancel that arrives last

- The countdown honoured a cancel only up to the control file's last read.
  Between that read and the power action the daemon spends real time on the
  battery, process and inhibitor guards, so a cancel written in that window sat
  unread while the shutdown, reboot or suspend still ran. The channel and the
  state are now read once more immediately before the action: a cancel makes the
  daemon stay IDLE, and a re-armed timer makes it re-evaluate instead of firing.
  `tests/test_cancel.sh` still passes, including the last-second case.

## 3.0.1 — the lock decides

- `daemon-stop` no longer trusts the pid file. A daemon killed with SIGKILL
  leaves its number behind, and the kernel eventually hands that number to
  another program of the same user — which `daemon-stop` then signalled. Now
  the process that holds the daemon's `flock` is the only one that gets a
  signal; a stale or missing pid file is repaired from the lock holder instead
  of being believed. `tests/test_stale_pid.sh` reproduces the old kill and
  fails on the old code.

## 3.0.0 — the dial

The popup is an instrument now: a ring you drag, scroll or type into, with the
presets around it and seconds on the menu.

**Time input**
- Wheel anywhere in the popup: ±1 minute a notch, ±5 with Shift. On the bar
  icon: ±5 and ±15 without opening anything.
- The ring drags relatively — one turn is an hour, Shift is the fine gear —
  and no longer jumps to where the press landed.
- Two boxes for minutes and seconds with the colon printed between them;
  `0` + `40` is forty seconds, and the daemon learned `set-secs` for it.
- Six presets around the dial, three a side.

**Look**
- The aperture is gone; the dial carries a metal knob, a two-tone arc, a
  minute scale and a figure that fits by construction.
- Caption inside the ring, two lines, demi-bold; the hint names the gestures.
- Every colour from the theme; nothing literal.

**Under the hood**
- `Panel.qml` split: the popup body lives in `PopupContent.qml`.
- Tests: 19 gesture checks, 9 layout checks, 17 suite files, 27 acceptance
  checks — all green. The layout gate compares coordinates, so an off-centre
  element fails the build instead of shipping.
- Audit fixes: a dead ring drag, a settings heredoc that a webhook URL could
  break, an unrotated log, world-readable state files.

## v3 stage 14 — the wheel is the fast path

- Wheel over the dial: a notch is a minute, Shift is five. `WheelHandler`
  never received a single event in this window (proven: 431 events logged,
  all from the bubbling path), so the wheel rides on a handler over the whole
  popup, which catches what bubbles up from whatever is under the pointer.
  The count is reported by `debugWheelCount()`.
- When the popup has to scroll (a long tray), that handler steps aside and
  the wheel scrolls the list again.
- The wheel already worked on the bar icon (±5, Shift ±15) without opening
  the popup — that stays.
- `+`/`-` (and `=`/`_`) on the keyboard do the same as a notch, next to the
  existing "type the minutes" path.
- The hints now name the wheel first (en/ru), in both IDLE and ACTIVE.
- `debugWheelCount()` reports how many wheel events the dial has seen, so the
  gesture can be proven without guessing.

## v3 stage 13 — the audit pass

- **The ring drag was dead**: the handler read `root.value` (a property that
  does not exist) and then used an `m` it never computed, so every drag threw
  a ReferenceError and the value never moved. Drag state now lives on the
  root (`dragBegin`/`dragTo`), and three tests drive the same code.
- Hover indent read `parent.hot` on a MouseArea (no such property): the 2 px
  shift never happened. Ids now.
- The pause glyph sized itself from `parent.barW` inside a Repeater — fragile
  scope; it reads `root.iconSize` and is a touch thicker.
- The `service` id shadowed a member property: renamed `timerService`.
- `root.tick` stood alone as a dependency statement (no effect): a real `if`.
- `var` in block scope (hoisted) became `let`/`const`.
- The log had no rotation (it would grow for months): 256 KB, one previous.
- State files were world-readable: `umask 077` and 0600 on the files.
- Settings were written through a heredoc with raw JSON, so a webhook URL
  containing a quote, a newline or `SETTINGSEOF` could corrupt the file. Now
  base64 (`Qt.btoa` → `base64 -d`); verified with
  `http://x/a'b"c SETTINGSEOF\nline2`.
- The card-shot check was an inline Python heredoc that failed spuriously
  (PIL's `_imaging` import broke intermittently in the venv). Replaced with
  `tools/card_check.sh` (ImageMagick): centre against all four corners,
  prints the delta (27.2 / 68.7 / 22.3 / 71.4 of 255).
- acceptance: 27 checks, 0 failed.

## v3 stage 12 — everything on the dial's axis

- The exact input is centred: the row sized itself to 62 % of the plate and
  packed its children to the left, which put the boxes 14 px off the dial.
  It now takes its own width and sits on the axis (measured: cx 199 of 199).
- The action row was 4 px wider than the column: the close key is 34 px and
  the segments were computed against 30. The segments now take what the row
  has left, so the row ends exactly at the edge.
- The layout walker allows 4 px of paint slack: a key's halo is drawn 3 px
  outside its box, which is glow, not overflow.
- `debugGeom()` reports the dial, the input, the hint and both preset
  columns in the column's own coordinates, so an off-centre element is a
  number, not an opinion.
- `tests/test_layout.sh`: 9 checks — dial/input/hint on the axis, presets
  mirrored, and no overflow in idle, active, repeat, more and history.
  Wired into acceptance (24 checks).
- The hint now says what the ring does (en/ru).

## v3 stage 11 — no colon to type, a ring that does not jump

- The exact input is two boxes, minutes and seconds, with the separator
  printed between them: Tab or a click moves across, ↑/↓ steps a value,
  Enter or ▶ starts. Nothing to remember, no colon to hunt for.
- The ring drags **relatively**: the value moves with the hand from where the
  press landed instead of jumping to the cursor. One turn is 60 minutes
  (6° a minute), Shift is the fine gear at 12 minutes a turn.
- The wheel over the ring is ±1 minute, Shift ±5 — the keyboard-free way to
  nudge when the hand is already on the mouse.
- The hint says what the ring does: "Drag the ring · Shift for fine · wheel
  ±1 min" (en/ru).

## v3 stage 10 — exact time, finer dial

- The caption inside the ring wraps to two lines inside 74 % of the dial, at
  body size and demi-bold, so "Power off on a timer" no longer crosses the arc.
- The figure is demi-bold at 26 % of the dial and still fits by construction:
  `11:59:58` shrinks instead of spilling out.
- Dragging the ring now covers 0–120 min instead of 0–720: one minute per
  three degrees, which is what a hand can actually aim at. Longer times come
  from the wheel (Shift ±15) and the presets.
- New exact field under the dial: `1` is a minute, `1:30` and `30s` are
  seconds, Enter or ▶ starts. Backed by a new `set-secs:` daemon command
  (5 s – 24 h) and `control.sh set-seconds`, so a 30-second timer is real.
- The aperture is gone; 15/30/45/60/90/120 sit around the dial, three a side.

# Changelog

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — 3.0 «Свеча», stage 1

The spec lives in `TZ-v3.md`; it was assembled from five independent reviews
(design, architecture, ideas, critique, second opinion) and the measurements in
`tools/acceptance.sh`.

### Added — stage 4: the HUD dial and smart conditions

- **The ring is a HUD now.** Its colour is interpolated from `accent` to
  `urgent` by how much time is left, the bloom is stronger, and inside the last
  minute the whole dial breathes (1.2 %, 1 s) unless reduced motion is on. The
  centre carries the action's own glyph above the figure, and the candle is a
  burnt stump in IDLE instead of a whole unlit candle.
- **Dragging while a timer runs is a delta**, not an absolute angle: the
  caption says `+20 мин к выключению` and the deadline moves instead of the
  countdown restarting from a new value.
- **The preset row, the number field and the relative/absolute switch are
  gone.** The dial covers 1–720 in one gesture, the wheel covers ±5 from the
  bar, and digits typed on the popup set the minutes directly (`4` `5` → 45).
- **Hold the bar icon for 500 ms to cancel**: an arc fills around the mark
  while the hold lasts, and a short click still opens the popup. Right-click
  opens it too (the old right-click-cancel was invisible and conflicted).
- **`waitForProcesses`** — the action waits up to 10 minutes while any named
  process runs (exact names; the daemon's own loop sleep is excluded), and the
  state carries `waiting for: <name>`.
- **`webhookUrl`** — a POST with `{"plugin","action","at"}` after the action,
  capped at 5 seconds, in the background.
- **`ambientFade`** (off by default) — in the last `fadeMinutes` the screen
  dims to 55 % and the sink volume drops to 60 %, both restored on cancel or
  pause; the original values are saved first, so a crash still leaves a file
  to restore from.

### Verified

- `waitForProcesses`: with a `sleep` running, a 1-minute timer stayed
  `ACTIVE` / `waiting for: sleep` past its deadline and fired once the process
  ended.
- Webhook: a local HTTP server received
  `{"plugin":"shutdown-timer","action":"poweroff","at":…}`.
- Ambient fade: brightness 96000 → 52800 during the window, back to 96000 on
  cancel.
- Digits: `4` `5` → `customMinutes: 45`; `tools/acceptance.sh` 22/22.

### Added — stage 3: two gestures the ecosystem does not have

- **A wheel on the bar icon sets the time without opening the popup.** ±5
  minutes, ±15 with Shift. In IDLE it stages the value and the tooltip says
  what the click will start; while a timer runs it moves the deadline and the
  bar shows the new figure. No other bar widget in Omarchy answers the wheel.
- **A click on the dial starts the timer** when nothing is staged. The ring's
  `MouseArea` used to swallow that click silently.
- `debugWheel "±n"` — the same code path the handler calls, provable from a
  script (`30 → 35 → 20`, and `30 → 40` while running).

### Added — stage 2: the focus dial, merged

- `HeroRing.qml` — the dial from the focus (pomodoro) plugin: a sixty-tick
  minute scale, a bloom, a lit head that pips outward on start and pause, and
  the ring itself as an input. Dragging around the dial sets the minutes
  (drag, not click — a click stays with the owner). All colours are tokens;
  the plugin it came from hard-codes violet.
- The hero is a lit plate: a surface gradient, an accent wash, one pixel of
  specular on the top edge, the dial with the figure on its axis and the
  candle standing under the figure.
- The overlay speaks the same language: the same plate, a gauge with a lit
  head instead of a hairline, Cancel as a filled urgent key, `+5` as a quiet
  pill. It no longer draws `00:00` — the figure reads the real remainder for
  `ACTIVE`/`PAUSED`, the card waits for the first state, and a window summoned
  with nothing to count down closes itself.
- `debugDial "x,y"` — the scrub's angle math, provable from a script
  (top 0, right 180, bottom 360, left 540 of 720).

### Added — stage 1

- `CandleTimer.qml` — the countdown drawn as a candle: wax shrinks with the
  time left, the flame shortens, a halo makes it read as a light source, and
  `blowOut()` kills the flame in 200 ms. Shapes and theme tokens only, no
  effects module, no literal colour.
- `Key.qml` — one machined key with four roles (`primary`, `selected`,
  `ghost`, `danger`), a one-pixel light edge on top and a shade below, a
  90 ms press, and a cursor outline that does not repaint the key.
- `TZ-v3.md` — the v3 spec: measured problems, the «Свеча» direction, the
  visual system, the popup composition, acceptance criteria and the stages.

### Changed

- **The bar mark closes its ring as the timer runs.** The canonical 70°
  opening narrows to 8° with the remaining fraction, so the mark itself is
  the progress indicator at 16 px — one parameter, no extra element.
- **The popup is a hierarchy, not a form.** Action is a row of four segments
  instead of a dropdown, the hero (candle + figure) is the largest object,
  the three escape hatches are worded keys, presets are one row of chips,
  the time is one field with a mode switch, and schedule/more/history live in
  a tray that opens in place. The launch key is always above the fold:
  `contentHeight` 387 px against 720 before, `scrolls: false`.
- The figure in the popup is `max(44, width × 0.15)` px — it used to be
  31 px of ink while the decorative icon was 46.
- The bar figure is 11 px (`bodySmall`) instead of the 10 px caption, which
  was below the plugin's own minimum.
- Right-click cancels `COUNTDOWN_SCHED` too, not only `ACTIVE`, `COUNTDOWN`
  and `PAUSED`.
- `tools/acceptance.sh` accepts the 11 px label width and any bar section.

### Verified

- `tools/acceptance.sh`: 22 passed, 0 failed.
- `debugOverflow`: `count: 0`; `debugLayout`: `scrolls: false`.
- Screenshots of IDLE and ACTIVE at 2×, bar mark at half a timer.

## [2.2.1] — 2026-10-29

### Fixed

- **A damaged `settings.json` no longer kills the daemon.** Numeric settings
  land straight in `$(( ))`, and a bare name there is fatal under `set -u`: a
  hand-written `"notifyEarlyMins": "abc"` ended the process on the next reload
  (`abc: unbound variable`), and the widget restarted it straight into the same
  crash — with a pending shutdown lost. Every numeric setting is now validated
  and clamped to the range the manifest and `Service.qml` already document
  (early warning, overlay seconds, snooze step, snooze limit, battery
  threshold): a string falls back to the default, an absurd number is clamped
  instead of obeyed. `tests/test_state_files.sh` damages all three state files
  (settings, state, schedules) and proves the daemon survives the damage, keeps
  its documented ranges, and still arms, snoozes and cancels afterwards.
- `suspend`/`hibernate` no longer fail silently: if neither `systemctl` nor the
  Omarchy helper works (no resume device, no logind seat), the log says so
  instead of the timer just going back to IDLE.

## [2.2.0] — 2026-10-29

Hardening pass after the review: the daemon can no longer be killed by a
malformed command, and the bar mark is optically matched to its neighbours.

### Added

- **The README screenshots are generated, not hand-made.** `tools/screenshots.sh`
  captures every surface (five bar states, popup, overlay, vertical bar) live on
  both themes and builds `states.gif` from them. `tools/card_bbox.py` finds a
  card by its own frame, and `tools/frame_check.py` proves the finished crop
  really frames it — a capture in the wrong coordinate space still looks fine
  and was shipping the desktop behind the popup. One capture is cut, never two,
  so the measured box and the pixels cannot drift apart mid-shot.
  `tools/acceptance.sh` runs the same check on the committed images.

### Fixed

- **A malformed control line no longer kills the daemon.** The control channel
  is a plain file any process in the session can write, and the daemon used to
  evaluate it unchecked: `set:abc:poweroff` reached `$((abc * 60))` and, under
  `set -u`, ended the process — taking the user's scheduled shutdown with it.
  The daemon now validates every command (minutes 1..1440, action whitelist,
  `HH:MM` range, snooze count, schedule id charset and weekday 1..7) and logs
  the rejection instead of dying. Covered by `tests/test_input.sh`.
- **A schedule id with a regex metacharacter** (`.*`) was used as a `grep`
  pattern on removal and deleted every schedule; ids are now plain
  `[0-9A-Za-z]+`.
- **The state badge cut itself out in black**, which read as dirt around the
  mark on a light bar. The badge is now outlined in the surface it is painted
  on (bar or popup background), so it reads as a clean notch on both themes.
- Deprecated QML signal-handler parameters (`onChanged:`/`onModified:` using
  the injected `value`/`code`) replaced with formal parameters; the Dropdown
  used a non-existent `onValueChanged` and is now on its real `changed`.

### Changed

- **Bar mark sized by painted ink, not by box.** The Nerd Font glyphs beside
  the widget paint 11–12 px inside the 16 px icon canvas; the mark now uses the
  same canvas and paints ~12 px, so it no longer overpowers the row. The stroke
  and the state badge scale with the slot, and the widget takes exactly one
  27 px icon slot when idle (the label gutter only exists while the countdown
  is on screen).
- `Shape.CurveRenderer` for the mark: the ring is anti-aliased instead of
  stair-stepped at bar size.

## [2.1.0] — 2026-10-28

Icon pass: the mark is rebuilt as a stroked path and the store icons get proper
corners.

### Changed

- **Bar mark** is a single stroked ring + stem with round caps instead of four
  stacked copies (shadow, two bevels, gradient body). The copies blurred into
  each other at a 14 px slot — the ring's counter closed up and the mark read as
  a smudge next to the crisp glyphs either side of it. One draw per state now,
  and the stroke weight scales with the slot so it never goes hairline or fat.
- **Store icons**: squircle corners (30 % of the side) instead of a nearly
  square 8 %, a brighter three-stop gradient and a rounded, thicker power mark,
  so the tile still reads at the ~48 px the store renders it at.
- Icons moved out of the fully dimmed state: the mark draws at full strength,
  which is what made it look washed out beside its neighbours.

## [2.0.0] — 2026-10-28

Reliability release: the timer can now always be cancelled, state survives
restarts, and the whole plugin speaks two languages.

### Added

- **Cancel from anywhere**: `Esc` or the button on the full-screen countdown,
  right-click on the bar widget, and the `control.sh cancel` CLI — all take
  effect even in the last second, and the overlay closes itself.
- **Countdown overlay**: large monospace countdown, progress bar, **Cancel**
  and **+5 minutes**; `Enter` postpones, `Esc` cancels.
- **Snooze limit**: a timer cannot be pushed back forever (default 3 times).
- **Pause / resume** that keeps the exact remainder.
- **Absolute time** (`HH:MM`) and **repeating schedules** per weekday
  (`once` / `daily` / `weekdays` / `weekends`), manageable from the popup and
  from the CLI.
- **Conditions**: low-battery guard (switch to a safer action instead of
  powering off) and wait-for-inhibitors before firing.
- **History** of the last runs with the outcome (`executed` / `cancelled`).
- **Languages**: `auto` (system locale), `en`, `ru` — applied to the popup,
  the overlay, notifications and the CLI.
- `control.sh status --json` and `control.sh get-state` for scripting.
- Keyboard navigation of the popup (arrows + Enter + shortcuts) and a
  `debugCursor` IPC probe for it.
- Contrast guard: popup/overlay text auto-clears 4.5:1 on any theme.
- `reducedMotion` setting for the pulsing icon and progress easing.
- **Dry run / override**: a live switch (`control.sh override`, or the popup
  toggle) that logs the action instead of running it, so an end-to-end firing
  no longer powers the machine off. Covered by `tests/test_override.sh`.
- Test suite in `tests/` (state machine, cancel paths, absolute time,
  schedules, daemon recovery, performance budgets).

### Changed

- The daemon is now the single source of truth for time; the widget only
  reads `state.json` and writes commands to `control`.
- A new timer always overwrites the previous one, without a dialog.
- Icon is drawn with four contours instead of a drop-shadow shader: exact
  bounds, no bleed into neighbouring widgets.
- Idle wakeups dropped from 1/s to ≤ 2/min (FIFO wakeup + `read -t`).

### Fixed

- A deadline that passes while the machine is suspended now opens the
  countdown window on wake instead of firing into a black screen.

- State is restored after `kill -9` — an overdue timer opens the countdown
  window instead of firing silently.
- `TERM` now actually terminates the daemon (the handler used to fall back
  into the main loop).
- `HH:MM` in CLI/schedules is no longer split on its own colon.
- Weekday codes outside 1–7 no longer abort `schedule list`.

## [1.0.0] — 2026-10-27

- First working plugin: presets, custom minutes, four actions, live bar
  label, early notification.
