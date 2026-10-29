# Changelog

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project adheres to [Semantic Versioning](https://semver.org/).

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
