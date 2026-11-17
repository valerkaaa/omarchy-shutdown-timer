#!/usr/bin/env bash
# Gesture tests: the dial, the wheel, the hold and the confirm sheet.
#
# These need the running shell (they drive the widget's IPC), so unlike the
# other tests they cannot run against an isolated daemon. When no shell
# answers, the test skips instead of failing: `bash tools/acceptance.sh` is
# still the gate for the daemon side.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN"
CTL=(bash control.sh)
IPC=(omarchy-shell honor.shutdown-timer)

pass=0; fail=0
ok()   { echo "  ok   $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL $1"; fail=$((fail + 1)); }

json() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }

if ! "${IPC[@]}" status >/dev/null 2>&1; then
  echo "SKIP: no running shell (gesture tests need the live widget)"
  exit 0
fi

cleanup() {
  "${CTL[@]}" cancel >/dev/null 2>&1 || true
  "${CTL[@]}" override off >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${CTL[@]}" override echo >/dev/null 2>&1

# ---- the dial's angle map: top 0, right 180, bottom 360, left 540 of 720
# Точки считаются от центра диска: попап бывает разной ширины, и зашитые
# координаты попадали бы в край или за него (диск тогда клампит угол).
read -r DW DH <<< "$("${IPC[@]}" debugDial "0,0" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['w'],d['h'])" 2>/dev/null)"
CX=$((DW / 2)); CY=$((DH / 2)); R=$((DW * 45 / 100))
[[ "$DW" -gt 0 ]] && ok "dial: geometry ${DW}x${DH}" || bad "dial: geometry not reported"

# Верх — точка замыкания шкалы: 0 и 120 сходятся в одном угле, и какая из
# двух величин выйдет, решает округление на пикселе. Оба ответа верны.
got=$("${IPC[@]}" debugDial "$CX,$((CY - R))" | json "['minutes']")
[[ "$got" == "0" || "$got" == "120" ]] && ok "dial: 12 o'clock is the wrap (0/120)" || bad "dial top gave '$got'"
got=$("${IPC[@]}" debugDial "$((CX + R)),$CY" | json "['minutes']")
[[ "$got" == "30" ]] && ok "dial: 3 o'clock is 30 min of 120" || bad "dial right gave '$got'"
got=$("${IPC[@]}" debugDial "$CX,$((CY + R))" | json "['minutes']")
[[ "$got" == "60" ]] && ok "dial: 6 o'clock is 60 min of 120" || bad "dial bottom gave '$got'"

# ---- the drag is relative: a quarter turn is +15 min, Shift a quarter of 12
"${CTL[@]}" cancel >/dev/null 2>&1; sleep 0.5
before=$("${IPC[@]}" debugDrag 0 0 false | json "['minutes']")
after=$("${IPC[@]}" debugDrag 0 90 false | json "['minutes']")
[[ "$after" -eq $(( before + 15 )) ]] && ok "drag: a quarter turn adds 15 min ($before -> $after)" || bad "drag $before -> $after (want +15)"

before=$("${IPC[@]}" debugDrag 0 0 false | json "['minutes']")
after=$("${IPC[@]}" debugDrag 0 90 true | json "['minutes']")
[[ "$after" -eq $(( before + 3 )) ]] && ok "drag: Shift quarter turn adds 3, not 15 ($before -> $after)" || bad "fine drag $before -> $after (want +3)"

before=$("${IPC[@]}" debugDrag 0 0 false | json "['minutes']")
after=$("${IPC[@]}" debugDrag 0 0 false | json "['minutes']")
[[ "$after" -eq "$before" ]] && ok "drag: a press without movement changes nothing" || bad "idle drag moved $before -> $after"
"${CTL[@]}" cancel >/dev/null 2>&1; sleep 0.4

# ---- the wheel: +5 and -15 in IDLE, +10 while running
"${CTL[@]}" set 30 >/dev/null 2>&1; sleep 1
got=$("${IPC[@]}" debugWheel 5 | json "['minutes']")
[[ "$got" == "35" ]] && ok "wheel: +5 in IDLE -> 35" || bad "wheel +5 gave '$got'"
got=$("${IPC[@]}" debugWheel 5 | json "['minutes']")
[[ "$got" == "40" ]] && ok "wheel: a second quick notch adds again (35 -> 40)" || bad "wheel second notch gave '$got'"
got=$("${IPC[@]}" debugWheel -15 | json "['minutes']")
[[ "$got" == "25" ]] && ok "wheel: -15 -> 25" || bad "wheel -15 gave '$got'"
"${CTL[@]}" set 30 >/dev/null 2>&1; sleep 1
got=$("${IPC[@]}" debugWheel 10 | json "['minutes']")
[[ "$got" == "40" ]] && ok "wheel: +10 while running -> 40" || bad "wheel running gave '$got'"

# ---- exact input: minutes and seconds
"${CTL[@]}" cancel >/dev/null 2>&1; sleep 0.5
"${IPC[@]}" debugExact "1" >/dev/null; sleep 1
st=$("${CTL[@]}" status | head -1)
[[ "$st" == "Status: ACTIVE" ]] && ok "exact: '1' starts a one-minute timer" || bad "exact 1 left '$st'"
"${IPC[@]}" debugBoxes 0 40 >/dev/null; sleep 1.2
left=$("${CTL[@]}" status | awk '/Time left/ {print $3}'); left=${left#00:}
(( left >= 35 && left <= 40 )) && ok "boxes: 0 + 40 starts 40 seconds (${left}s)" || bad "boxes left=$left"

"${CTL[@]}" cancel >/dev/null 2>&1; sleep 0.5
"${IPC[@]}" debugExact "30s" >/dev/null; sleep 1.2
left=$("${CTL[@]}" status | awk '/Time left/ {print $3}')
left=${left#00:}
(( left >= 25 && left <= 30 )) && ok "exact: '30s' starts a 30 second timer (${left}s)" || bad "exact 30s left=$left"
"${CTL[@]}" cancel >/dev/null 2>&1; sleep 0.5

# ---- hold-to-cancel: a short hold must not cancel, a long one must
"${CTL[@]}" set 30 >/dev/null 2>&1; sleep 1
"${IPC[@]}" debugHoldStart >/dev/null; sleep 0.2
got=$("${IPC[@]}" debugHoldEnd | json "['fired']")
[[ "$got" == "False" ]] && ok "hold: 200 ms does not cancel" || bad "short hold fired=$got"
st=$("${CTL[@]}" status | head -1)
[[ "$st" == "Status: ACTIVE" ]] && ok "hold: timer still ACTIVE after a short hold" || bad "short hold left '$st'"

"${IPC[@]}" debugHoldStart >/dev/null; sleep 0.65
got=$("${IPC[@]}" debugHoldEnd | json "['fired']")
[[ "$got" == "True" ]] && ok "hold: 650 ms cancels" || bad "long hold fired=$got"
sleep 1
st=$("${CTL[@]}" status | head -1)
[[ "$st" == "Status: IDLE" ]] && ok "hold: timer is IDLE after a long hold" || bad "long hold left '$st'"

# ---- the confirm sheet: keep it, then cancel
"${CTL[@]}" set 30 >/dev/null 2>&1; sleep 1
got=$("${IPC[@]}" debugConfirm | json "['open']")
[[ "$got" == "True" ]] && ok "confirm: the sheet opens" || bad "confirm open=$got"
"${IPC[@]}" debugConfirmAnswer no >/dev/null; sleep 0.3
st=$("${CTL[@]}" status | head -1)
[[ "$st" == "Status: ACTIVE" ]] && ok "confirm: 'keep it' leaves the timer running" || bad "keep left '$st'"

"${IPC[@]}" debugConfirm >/dev/null; sleep 0.3
"${IPC[@]}" debugConfirmAnswer yes >/dev/null; sleep 0.8
st=$("${CTL[@]}" status | head -1)
[[ "$st" == "Status: IDLE" ]] && ok "confirm: 'cancel timer' stops it" || bad "confirm yes left '$st'"

echo "== gestures: $pass passed, $fail failed =="
(( fail == 0 ))
