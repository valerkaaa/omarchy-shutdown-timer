#!/usr/bin/env bash
# test_input.sh — the control channel is a plain file, so anything in the
# session can write into it. A malformed line must be rejected, never kill the
# daemon: `set:abc:poweroff` used to reach `$((abc * 60))`, which under `set -u`
# ends the whole process (and the user's scheduled shutdown with it).
#
# Every case here asserts two things: the daemon is still alive, and the
# command was corrected or rejected — not silently half-applied.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

alive() { kill -0 "$T_DAEMON_PID" 2>/dev/null; }
assert_alive() {
  alive || t_fail "the daemon died after '$1'"
  t_pass "survives '$1'"
}
logged() { grep -q -- "$1" "$T_STATE/daemon.log"; }

# --- garbage minutes: must not be evaluated as a variable ---------------
t_send "set:abc:poweroff"
assert_alive "set:abc:poweroff"
logged "rejected set: minutes 'abc'" || t_fail "no rejection logged for set:abc"
t_assert_eq "$(t_state status)" "IDLE" "set:abc leaves the state untouched"

# --- unknown action ------------------------------------------------------
t_send "set:30:bogus"
assert_alive "set:30:bogus"
logged "rejected set: unknown action 'bogus'" || t_fail "no rejection logged for the bad action"
t_assert_eq "$(t_state status)" "IDLE" "set:30:bogus leaves the state untouched"

# --- out-of-range minutes (the UI slider is 1..1440) ---------------------
t_send "set:0:poweroff"
t_assert_eq "$(t_state status)" "IDLE" "set:0 is refused (minutes >= 1)"
t_send "set:99999:poweroff"
t_assert_eq "$(t_state status)" "IDLE" "set:99999 is refused (minutes <= 1440)"
t_send "set:1440:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "set:1440 is accepted"
t_send "cancel"

# --- bad absolute time ---------------------------------------------------
t_send "set-abs:99:99:poweroff"
assert_alive "set-abs:99:99:poweroff"
logged "rejected set-abs: invalid time '99:99'" || t_fail "no rejection logged for 99:99"
t_assert_eq "$(t_state status)" "IDLE" "set-abs:99:99 leaves the state untouched"

# --- bad snooze count (needs a live timer to reach the arithmetic) --------
t_send "set:30:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "timer armed for the snooze checks"
t_send "snooze:abc"
assert_alive "snooze:abc while ACTIVE"
logged "rejected snooze: 'abc'" || t_fail "no rejection logged for snooze:abc"
t_assert_eq "$(t_state snoozeCount)" "0" "snooze:abc does not count as a snooze"
t_send "snooze:0"
t_assert_eq "$(t_state snoozeCount)" "0" "snooze:0 is refused"
t_send "snooze:1"
t_assert_eq "$(t_state snoozeCount)" "1" "a valid snooze still works"
t_send "cancel"

# --- schedule id / weekday validation ------------------------------------
# an id like `.*` would otherwise be read as a grep pattern and delete every
# schedule; a weekday outside 1..7 would be stored and never match
t_send "schedule-add:1001:23:30:1,2,3,4,5:poweroff"
t_assert_eq "$(t_state scheduleCount)" "1" "valid schedule stored"
t_send "schedule-add:.*:23:30:1:poweroff"
logged "rejected schedule-add: bad id '.*'" || t_fail "no rejection logged for a regex id"
t_assert_eq "$(t_state scheduleCount)" "1" "regex id refused"
t_send "schedule-add:1002:23:30:9:poweroff"
logged "rejected schedule-add: bad id '1002' or days '9'" || t_fail "no rejection logged for weekday 9"
t_send "schedule-add:1002:23:99:1:poweroff"
logged "rejected schedule-add: invalid time '23:99'" || t_fail "no rejection logged for 23:99"
t_assert_eq "$(t_state scheduleCount)" "1" "invalid schedules refused"

t_send "schedule-remove:.*"
assert_alive "schedule-remove:.*"
t_assert_eq "$(t_state scheduleCount)" "1" "a regex id does not wipe the schedule list"
t_send "schedule-remove:1001"
t_assert_eq "$(t_state scheduleCount)" "0" "a plain id still removes"

# --- a command with an embedded newline / shell metacharacters ------------
# `poweroff; touch /tmp/x` came out as the whole string when unchecked
t_send "set:5:poweroff; touch /tmp/never"
assert_alive "set with a shell tail"
t_assert_eq "$(t_state status)" "IDLE" "the shell tail is refused as a non-action"

# --- unknown command is logged, not fatal --------------------------------
t_send "frobnicate"
assert_alive "unknown command"
logged "unknown command: frobnicate" || t_fail "unknown command was not logged"

echo "test_input: all passed"
