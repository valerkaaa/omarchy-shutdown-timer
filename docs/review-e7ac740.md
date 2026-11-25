# Review response — commit e7ac740

**Scope:** the three findings raised against `e7ac740` (release 3.0.3) in
`daemon.sh`, `Service.qml` and `PopupContent.qml`.

**Method:** read of the exact lines quoted in the findings, then local execution
on the stock machine (Omarchy, Qt 6.12.0, Quickshell 0.3.2, Hyprland/Wayland).
Every finding was reproduced against the reviewed tree before any change, and
the reproduction is kept as a test where it can be automated. Nothing here is a
claim without a command behind it.

**Result:** all three confirmed. Two were defects in this plugin and are fixed;
the third is a Qt defect (QTBUG-149610) that the plugin now steps around
completely.

---

## 1. Medium — a pause inside the final checks did not stop the action

`daemon.sh:532–541` (`pause`), `daemon.sh:748–761` and `809–822` (the last-moment
gate in the ACTIVE and COUNTDOWN branches).

**Confirmed.** `pause` stores `PAUSED` and `targetTime=0`. The gate that 3.0.2
added before `do_action` knew exactly two cases — `IDLE` (a cancel) and `ACTIVE`
with a target in the future (a re-armed timer). A `PAUSED` state matched neither,
so the branch fell through to `append_history executed` and `do_action`: the UI
and `history.tsv` recorded a pause and the machine powered off anyway.

Reproduction: `tests/test_pause_final_gate.sh`. A shim `pgrep` sleeps only while
the daemon reports `COUNTDOWN`, i.e. only once `time_left <= 0`, which is inside
the final checks; the test writes `pause` at that moment. On the reviewed tree
the test fails with `got 'IDLE', want 'PAUSED'` — the action ran. On 3.0.4 the
state stays `PAUSED`, the log says `pause arrived during the final checks — not
firing poweroff`, and no action runs.

Fix: one `final_gate()` used by both branches — cancel, pause and a re-armed
timer all stop the firing; the gate is still the last statement before
`append_history`/`do_action`, and it drains the control file itself, so a command
written during the guards is read.

## 2. Medium — the webhook URL was readable in a process's arguments

`Service.qml:119–156` (settings writer), `daemon.sh:188–197` (`curl`).

**Confirmed.** `/proc/<pid>/cmdline` is mode `0444` on this system and `/proc` is
mounted without `hidepid`, so any local account could read another account's
arguments. The settings file itself was not the leak: `settings.json` is `0600`
inside a `0700` home. The two argv leaks were:

- `curl … -d "$body" "$url"` — the full webhook URL, token included, in plain
  text in `curl`'s argv;
- `bash -c "… printf %s '<base64 of the settings JSON>' | base64 -d > …"` — the
  same URL, base64 (reversible, not encryption), in the writer's argv on every
  settings change and on every start.

Reproduction: `tests/test_webhook_args.sh`. On the reviewed tree it fails with
the whole argv printed, token visible:
`-m 5 -s -o /dev/null -X POST … https://hooks.example.test/services/T0K3N-SENTINEL-4f8a2c`.
On 3.0.4 no argument contains the token.

Fixes:

- `curl` reads its entire request from a config on stdin (`-K -`). A URL that
  cannot be one quoted config value — `"`, `\`, newline, CR, tab — is refused
  with a log line instead of being pasted in; otherwise it could add directives
  of its own (`output = …`), which would be a new injection path.
- The settings writer sends the JSON on stdin, writes `settings.json.tmp` and
  renames it over `settings.json` (`umask 077`), and folds a change that arrives
  mid-write into one more write. `Service.qml` no longer has a function that
  returns a command string; the debug IPC hook calls the real writer.

The test also proves the request still works: a real POST against a local server
arrives with the right path, `application/json` and an intact JSON body, and a
URL carrying a newline never reaches `curl` at all.

Residual: the URL still lives in `settings.json` (`0600`, `0700` home) — as
before, and not reachable from another account.

## 3. Medium, conditional — the time boxes made Qt read the clipboard

`PopupContent.qml:501–552`.

**Confirmed, root cause upstream.** The plugin has no clipboard code at all
(`grep -i clipboard` finds only `selectByMouse`). The reads come from Qt: on
6.12.0 every writable `QQuickTextInput` connects `QClipboard::dataChanged` to its
`canPaste` refresh, which calls `QMimeData::text()` — the whole offer, on the
main thread, with no paste action. That is **QTBUG-149610**, affected
6.8.8 / 6.10.3 / 6.11.0–6.11.2 / 6.12.0, fixed in 6.8.10, **6.12.1** and 6.13.

Measured here (Qt 6.12.0, 100 MB in the clipboard, `VmHWM`, Wayland protocol
trace):

| shape of the field | peak RSS | clipboard requests |
|---|---|---|
| writable `TextField` | 407 MB | 1 on appearance, then one per clipboard change |
| `readOnly: true` | 111 MB | 0 |
| `Text` / no text item | 104 / 95 MB | 0 |

With one live writable field, three clipboard changes produced four
`wl_data_offer.receive("text/plain;charset=utf-8")` requests — no paste, no
focus change.

The obvious mitigation — `readOnly` while the panel is closed — is **not
enough**: `QQuickTextInput::setReadOnly()` runs the same refresh itself, so
turning the field editable when the panel opens pulls the whole offer right
then. Measured: 409 MB peak, i.e. identical to the always-writable case.

Fix: the mm/ss boxes are `readOnly: true` for life, and the digits are fed by
`typeInto()` (digits, 720/59 clamp, Backspace, Tab between boxes, Enter
submits). Zero clipboard traffic. `tests/test_exact_fields.sh` drives the live
panel with `wtype` and checks the read-only property plus all four behaviours;
it passes 9/9.

Residual, out of this plugin's hands: every other panel in the shell that has a
writable field is still affected until Qt 6.11.3/6.12.1 ships — that is the
Omarchy report (issue #15083 / #8753), not this plugin.

## Also fixed while verifying

`tools/acceptance.sh` armed `override echo` for its checks and left it behind:
after a run, the next real timer would only write a line to the log instead of
powering off. A trap now cancels the timer and turns the override off on every
exit path. This was found because the first acceptance run after the fixes left
the machine in dry-run mode.

## Verification (all on the final tree)

- `tests/run_all.sh` — ALL GREEN.
- `tools/acceptance.sh` — 28 checks, 0 failed.
- `tests/test_pause_final_gate.sh`, `tests/test_webhook_args.sh` — fail on
  `e7ac740`, pass on this tree.
- `tests/test_exact_fields.sh` — 9/9 against the live panel.
- `qmllint` on `Service.qml`, `Panel.qml`, `PopupContent.qml` — no errors.
- Live shell: no QML errors from this plugin in the Quickshell log.

## Reproduce

```bash
cd ~/.config/omarchy/plugins/honor.shutdown-timer
bash tests/test_pause_final_gate.sh     # pauses inside the final checks
bash tests/test_webhook_args.sh         # token in argv, hostile URL
bash tests/test_exact_fields.sh         # live panel, needs wtype
bash tests/run_all.sh
bash tools/acceptance.sh
```
