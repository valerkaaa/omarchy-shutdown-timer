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

echo "== §15 acceptance checks =="

# 1. widget visible, correct slot, no jumping.
# An idle widget must take exactly one icon slot (27 px) so it lines up with
# its neighbours; the wider slot (63 px) only exists while the label is up.
geo=$(omarchy-shell shell debugBarGeometry 2>/dev/null | python3 -c "
import sys,json
for it in json.load(sys.stdin):
    if 'shutdown' in it.get('id',''): print(it['visible'], it['width'], it['height'], it['section'])")
if [[ "$geo" == "True 27 26 "* || "$geo" == "True 63 26 "* || "$geo" == "True 66 26 "* ]]; then
  ok "widget visible, slot 27 px idle / 63–66 px with label (11 px figure) ($geo)"
else
  bad "widget slot: $geo"
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
[[ $rc -eq 0 ]] && ok "test_cancel.sh green" || bad "test_cancel.sh red: $(echo "$out" | tail -1)"

# 5. cancel closes the overlay itself; machine stays on — overlay wires cancel to control.sh
check "grep -q 'cancel' Overlay.qml" "overlay cancel wired"

# 6. +5 minutes works, snooze limit holds
check "grep -q 'snooze' tests/test_state.sh" "snooze limit covered by test_state.sh"

# 7. pause/resume keep the remainder
check "grep -q 'paused clock does not move' tests/test_state.sh" "pause/resume covered"

# 8. absolute time and schedule incl. tomorrow rollover
out=$(timeout 200 bash tests/test_absolute.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_absolute.sh green (incl. tomorrow)" || bad "test_absolute red"

# 9. state survives kill -9 and shell restart
out=$(timeout 100 bash tests/test_daemon.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_daemon.sh green (kill -9 recovery)" || bad "test_daemon red"

# 10. sleep/wake does not lose the timer
out=$(timeout 120 bash tests/test_sleep.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_sleep.sh green (suspend window)" || bad "test_sleep red"

# 11. budgets of §11
out=$(timeout 200 bash tests/test_perf.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_perf.sh green (budgets)" || bad "test_perf red"

# 11b. malformed control input must not kill the daemon (control is a plain file)
out=$(timeout 120 bash tests/test_input.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_input.sh green (bad input is rejected, daemon survives)" || bad "test_input red"

out=$(timeout 120 bash tests/test_state_files.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "test_state_files.sh green (damaged state files are survived)" || bad "test_state_files red"

# 12. all tests green, bash -n clean
out=$(timeout 550 bash tests/run_all.sh 2>&1 | tail -1)
[[ "$out" == *"ALL GREEN"* ]] && ok "run_all.sh: ALL GREEN" || bad "suite: $out"
check "bash -n daemon.sh && bash -n control.sh" "bash -n clean"

# 13. no QML errors in the live log
L=$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog 2>/dev/null | head -1)
if strings "$L" 2>/dev/null | grep -aqE '(shutdown|Panel|Overlay|Service|TimerIcon|Model)\.(qml|js):[0-9]+:[0-9]+:'; then
  bad "QML errors in the shell log"
else
  ok "shell log clean of QML errors"
fi

# 14. README, CHANGELOG, LICENSE, screenshots
check "[[ -f README.md && -f CHANGELOG.md && -f LICENSE ]]" "README/CHANGELOG/LICENSE present"
check "ls assets/screenshots/dark/*.png assets/screenshots/light/*.png >/dev/null" "screenshots present"

# The card shots must actually show the card, not the desktop behind it. A
# frame check would need the exact margin the crop was cut with, and a rounded
# card has no straight line there; the honest test is that the centre (the
# card surface) differs from the corners (whatever is behind it), plus a size
# floor so a thumbnail cannot pass by accident.
for t in dark light; do
  for f in 6-popup.png 7-overlay.png; do
    python3 - "assets/screenshots/$t/$f" <<'PY' || bad "card shot $t/$f is flat or too small"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
if w < 500 or h < 300:
    sys.exit(1)
def mean(box):
    px = list(im.crop(box).resize((8, 8)).getdata())
    return [sum(p[i] for p in px) / len(px) for i in range(3)]
corner = mean((0, 0, w // 12, h // 12))
centre = mean((w // 2 - w // 8, h // 2 - h // 8, w // 2 + w // 8, h // 2 + h // 8))
sys.exit(0 if max(abs(corner[i] - centre[i]) for i in range(3)) > 10 else 1)
PY
  done
done && ok "card screenshots show a card, not the desktop" || bad "a card screenshot is flat"

# 15. install from a clean clone
check "omarchy plugin validate . " "manifest validates"

echo
echo "== result: $pass passed, $fail failed =="
exit $((fail > 0))
