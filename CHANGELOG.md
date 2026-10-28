# Changelog

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project adheres to [Semantic Versioning](https://semver.org/).

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
