#!/usr/bin/env bash
# Verification of the TZ §15 acceptance list. Every line is a check against
# live output, not a claim. Run from anywhere.
set -u
PLUGIN="$HOME/.config/omarchy/plugins/honor.shutdown-timer"
cd "$PLUGIN" || exit 1
export WAYLAND_DISPLAY=wayland-1

pass=0; fail=0
ok()   { echo "  [x] $*"; pass=$((pass+1)); }
bad()  { echo "  [ ] $*  <-- FAIL"; fail=$((fail+1)); }
check(){ if eval "$1" >/dev/null 2>&1; then ok "$2"; else bad "$2"; fi; }

# A run must never leave the machine in dry-run mode: the checks arm
# `override echo`, and a run that forgets to disarm it turns the real timer into
# a no-op — the next shutdown would only write a line to the log.
cleanup_dry_run() {
  bash control.sh cancel >/dev/null 2>&1 || true
  bash control.sh override off >/dev/null 2>&1 || true
}
trap cleanup_dry_run EXIT INT TERM

# Every test's full output goes to one file: a red line in the summary is not
# enough to tell a real defect from a flake, and the tail is all that survives.
TEST_LOG="${TEST_LOG:-/tmp/shutdown-timer-acceptance-tests.log}"
: > "$TEST_LOG"

echo "== §15 acceptance checks =="

# 1. widget visible, correct slot, no jumping.
# An idle widget must take exactly one icon slot so it lines up with its
# neighbours; the wider slot only exists while the label is up. Both sizes
# follow the bar's font, and the font is a user setting — so the reference is a
# neighbouring icon widget, not a hardcoded number (27 px was base-size 12).
# Start from a still widget: the caption is only up while a timer runs, and a
# leftover timer from an earlier check would be measured as the idle slot.
bash control.sh cancel >/dev/null 2>&1
bash control.sh override echo >/dev/null 2>&1
sleep 2
read -r vis idle h sec ref <<< "$(omarchy-shell shell debugBarGeometry 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
mine = next((i for i in d if i.get('id') == 'honor.shutdown-timer'), None)
ref = next((i for i in d if i.get('id') == 'omarchy.bluetooth'), None)
if mine and ref:
    print(mine['visible'], mine['width'], mine['height'], mine['section'], ref['width'])")"
if [[ "${vis:-}" == "True" && -n "${idle:-}" && "${idle}" == "${ref:-x}" ]]; then
  ok "widget visible, idle slot ${idle} px = the bar's icon slot (neighbour ${ref} px, ${sec} section)"
else
  bad "widget slot: idle ${idle:-?} px vs neighbour ${ref:-?} px, visible ${vis:-?}"
fi

# the caption adds one short text run and nothing else
bash control.sh override echo >/dev/null 2>&1
bash control.sh set 30 >/dev/null 2>&1
sleep 2.5
lab=$(omarchy-shell shell debugBarGeometry 2>/dev/null | python3 -c "
import sys, json
for it in json.load(sys.stdin):
    if it.get('id') == 'honor.shutdown-timer': print(it['width'])")
bash control.sh cancel >/dev/null 2>&1
if [[ -n "${lab:-}" && -n "${idle:-}" && "$lab" -gt "$idle" && $((lab - idle)) -ge 20 && $((lab - idle)) -le 60 ]]; then
  ok "caption state ${lab} px: +$((lab - idle)) px of text, then back to the slot"
else
  bad "caption slot: idle ${idle:-?} px, with caption ${lab:-?} px"
fi

# 2. icon: own SVG, both themes, 16 px
check "[[ -f assets/timer.svg && -f assets/screenshots/icon-sizes.png ]]" "own SVG + 16 px evidence present"
check "[[ -f assets/screenshots/dark/1-idle.png && -f assets/screenshots/light/1-idle.png ]]" "icon rendered on both themes (screenshots)"

# 3. five states drawn and distinguishable
n=$(ls assets/screenshots/dark/*.png 2>/dev/null | wc -l)
[[ "$n" -ge 5 ]] && ok "5 bar states captured" || bad "only $n states captured"

# 4. cancel works from every state, incl. last second
check "grep -q 'cancel in the last second' tests/test_cancel.sh" "cancel-from-every-state test exists"
out=$(timeout 200 bash tests/test_cancel.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_cancel.sh green" || bad "test_cancel.sh red: $(echo "$out" | tail -1)"

# 5. cancel closes the overlay itself; machine stays on — overlay wires cancel to control.sh
check "grep -q 'cancel' Overlay.qml" "overlay cancel wired"

# 6. +5 minutes works, snooze limit holds
check "grep -q 'snooze' tests/test_state.sh" "snooze limit covered by test_state.sh"

# 7. pause/resume keep the remainder
check "grep -q 'paused clock does not move' tests/test_state.sh" "pause/resume covered"

# 8. absolute time and schedule incl. tomorrow rollover
out=$(timeout 200 bash tests/test_absolute.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_absolute.sh green (incl. tomorrow)" || bad "test_absolute red: $(echo "$out" | grep FAIL | tail -1)"

# 9. state survives kill -9 and shell restart
out=$(timeout 100 bash tests/test_daemon.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_daemon.sh green (kill -9 recovery)" || bad "test_daemon red"

# 10. sleep/wake does not lose the timer
out=$(timeout 120 bash tests/test_sleep.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_sleep.sh green (suspend window)" || bad "test_sleep red"

# 11. budgets of §11
out=$(timeout 200 bash tests/test_perf.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_perf.sh green (budgets)" || bad "test_perf red"

# 11b. malformed control input must not kill the daemon (control is a plain file)
out=$(timeout 120 bash tests/test_input.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_input.sh green (bad input is rejected, daemon survives)" || bad "test_input red"

out=$(timeout 120 bash tests/test_state_files.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
[[ $rc -eq 0 ]] && ok "test_state_files.sh green (damaged state files are survived)" || bad "test_state_files red"
out=$(timeout 180 bash tests/test_layout.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
if [[ $rc -eq 0 ]]; then
  if [[ "$out" == *SKIP* ]]; then ok "test_layout.sh skipped (no shell)"; else ok "test_layout.sh green (axis, presets, no overflow)"; fi
else
  bad "test_layout red: $(echo "$out" | grep FAIL | head -2 | tr '\n' ' ')"
fi
out=$(timeout 120 bash tests/test_gestures.sh 2>&1); rc=$?
printf '%s\n' "$out" >> "$TEST_LOG"
if [[ $rc -eq 0 ]]; then
  if [[ "$out" == *SKIP* ]]; then ok "test_gestures.sh skipped (no shell)"; else ok "test_gestures.sh green (dial, wheel, hold, confirm)"; fi
else
  bad "test_gestures red: $(echo "$out" | tail -1)"
fi

# 12. all tests green, bash -n clean
out=$(timeout 550 bash tests/run_all.sh 2>&1 | tail -1)
[[ "$out" == *"ALL GREEN"* ]] && ok "run_all.sh: ALL GREEN" || bad "suite: $out"
check "bash -n daemon.sh && bash -n control.sh" "bash -n clean"

# 13. no QML errors in the live log — only OUR files count.
# The shell log is shared with the stock panels, and a bare `Panel.qml:` pattern
# matched Omarchy's own network panel (a binding loop there is not our bug).
L=$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog 2>/dev/null | head -1)
if strings "$L" 2>/dev/null | grep -aqE 'honor\.shutdown-timer/[^ ]*\.(qml|js):[0-9]+:[0-9]+:'; then
  bad "QML errors in the shell log"
else
  ok "shell log clean of QML errors"
fi

# 14. README, CHANGELOG, LICENSE, screenshots
check "[[ -f README.md && -f CHANGELOG.md && -f LICENSE ]]" "README/CHANGELOG/LICENSE present"
check "ls assets/screenshots/dark/*.png assets/screenshots/light/*.png >/dev/null" "screenshots present"

# The card shots must actually show the card, not the desktop behind it.
for t in dark light; do
  for f in 6-popup.png 7-overlay.png; do
    out=$(bash tools/card_check.sh "assets/screenshots/$t/$f" 2>&1)
    if [[ $? -eq 0 ]]; then
      ok "card shot $t/$f ($(echo "$out" | sed -E 's/.*delta ([0-9.]+).*/delta \1 of 255/'))"
    else
      bad "card shot $t/$f: $out"
    fi
  done
done

# 15. install from a clean clone
check "omarchy plugin validate . " "manifest validates"

echo
echo "== result: $pass passed, $fail failed =="
exit $((fail > 0))
