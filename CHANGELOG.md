# Changelog

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — 3.0 «Свеча», stage 1

The spec lives in `TZ-v3.md`; it was assembled from five independent reviews
(design, architecture, ideas, critique, second opinion) and the measurements in
`tools/acceptance.sh`.

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
