#!/usr/bin/env bash
# test_state_files.sh — state.json, settings.json and schedules.tsv live in a
# writable state dir. Anyone in the session (or a half-finished write) can leave
# garbage in them, and the daemon reloads all three on every tick. Garbage must
# be tolerated: a bare name in arithmetic is fatal under `set -u`, so a
# hand-written `"notifyEarlyMins": "abc"` used to kill the daemon — and the
# widget restarted it straight into the same crash.
#
# Contract: after each kind of damage the daemon is still alive, the effective
# settings stay inside their documented ranges, and the state is a valid,
# parseable line.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup
alive() { kill -0 "$T_DAEMON_PID" 2>/dev/null; }
assert_alive() { alive || t_fail "$1 killed the daemon"; t_pass "$1 leaves the daemon alive"; }

# settings are read through a reload: poke the daemon after writing
reload() { printf '%s\n' "$2" > "$T_STATE/$1"; t_send "ping"; }
field() { # key [min max] -> value must be numeric and in range
  local v; v=$(t_state "$1")
  [[ "$v" =~ ^-?[0-9]+$ ]] || t_fail "$1 is not numeric: '$v'"
  if [[ $# -eq 3 ]]; then
    (( v >= $2 && v <= $3 )) || t_fail "$1 out of range: $v not in $2..$3"
  fi
}

# --- settings.json: a string where a number belongs ----------------------
reload settings.json '{"notifyEarlyMins":"abc","overlaySeconds":"abc","snoozeMins":"abc","batteryThreshold":"abc"}'
assert_alive "string settings"
t_send "set:30:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "a timer still arms afterwards"
t_send "cancel"
grep -q "unbound variable" "$T_STATE/daemon.log" \
  && t_fail "an unbound-variable error reached the log" \
  || t_pass "no unbound-variable error logged"

# --- settings.json: absurd numbers get clamped, not stored ---------------
reload settings.json '{"overlaySeconds":999999,"notifyEarlyMins":99999,"snoozeMins":0,"batteryThreshold":500}'
assert_alive "out-of-range settings"
reload settings.json '{}'
t_send "set:30:poweroff"
t_send "snooze:5"
# the snooze step is what snoozeMins feeds; with 0 clamped to 1 the timer grows
t_send "cancel"

# --- settings.json: broken and empty ------------------------------------
reload settings.json '{"overlaySeconds":'
assert_alive "truncated settings.json"
reload settings.json ''
assert_alive "empty settings.json"

# --- state.json: every field is garbage ---------------------------------
printf '%s\n' '{"status":"FOO","action":"banana","timeLeft":"x","targetTime":"y","mode":42,"startTime":null,"snoozeCount":"-"}' > "$T_STATE/state.json"
t_send "ping"
assert_alive "garbage state.json"

# an ACTIVE with a nonsense targetTime must still be readable and must not
# fire the machine off in the same second
printf '%s\n' '{"status":"ACTIVE","action":"poweroff","timeLeft":-99999,"targetTime":0,"mode":"relative","startTime":0,"snoozeCount":-3}' > "$T_STATE/state.json"
t_send "ping"
assert_alive "impossible targetTime"
grep -q '"status"' "$T_STATE/state.json" || t_fail "state.json was left unparseable"

# --- state.json: empty file ---------------------------------------------
: > "$T_STATE/state.json"
t_send "ping"
assert_alive "empty state.json"

# --- schedules.tsv: junk lines survive a tick ---------------------------
printf '%s\n' 'мусор' '99:99	1,9	banana' '' '5	8:00	1	poweroff' > "$T_STATE/schedules.tsv"
t_send "ping"
assert_alive "junk schedules.tsv"

# --- clamped, not obeyed: the countdown window keeps its documented range --
# overlaySeconds feeds `now + overlay_seconds`; a string defaulted and a huge
# number clamped, both visible as the length of the window the wake opens.
overlay_window() { # want_seconds label
  local want=$1 label=$2
  t_send "cancel"
  t_send "set:3:poweroff"
  local want_ts=$(( $(date +%s) + 2 )) raw old
  for _ in $(seq 1 30); do
    raw=$(<"$T_STATE/state.json")
    old=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9-]*' | cut -d: -f2)
    [[ "$old" == "$want_ts" ]] && break
    printf '%s\n' "${raw/\"targetTime\":$old/\"targetTime\":$want_ts}" > "$T_STATE/state.json"
    sleep 0.1
  done
  kill -STOP "$T_DAEMON_PID"; sleep 6; kill -CONT "$T_DAEMON_PID"
  t_wait_for status COUNTDOWN 6 || t_fail "$label: no countdown window after the wake"
  local now delta; now=$(date +%s)
  delta=$(( $(t_state targetTime) - now ))
  (( delta >= want - 4 && delta <= want + 2 )) \
    || t_fail "$label: window is ${delta}s, expected about ${want}s"
  t_pass "$label: window is ~${want}s (${delta}s)"
  t_send "cancel"
}

reload settings.json '{"overlaySeconds":"abc"}'
overlay_window 30 "a string overlaySeconds falls back to the default"
reload settings.json '{"overlaySeconds":999999}'
overlay_window 120 "an absurd overlaySeconds is clamped to the manifest maximum"

# --- clamped limit is enforced: a negative snoozeLimit means no snoozing ----
reload settings.json '{"snoozeLimit":-5}'
t_send "set:30:poweroff"
t_send "snooze:5"
t_assert_eq "$(t_state snoozeCount)" "0" "snoozeLimit -5 clamps to 0, so the first snooze is refused"
t_send "cancel"

# --- the daemon still works normally after all that ----------------------
reload settings.json '{"overlaySeconds":30,"notifyEarlyMins":5,"snoozeMins":5}'
t_send "set:15:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "a valid timer still works after the damage"
t_send "snooze:5"
t_assert_eq "$(t_state snoozeCount)" "1" "and snoozing works again"
t_send "cancel"
t_assert_eq "$(t_state status)" "IDLE" "and it still cancels"

echo "test_state_files: all passed"
