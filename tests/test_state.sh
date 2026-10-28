#!/usr/bin/env bash
# test_state.sh — state transitions, overwrite, pause/resume, snooze limit.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

# set → ACTIVE with a live countdown
t_send "set:45:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "set starts the timer"
t_assert_eq "$(t_state action)" "poweroff" "action is recorded"
left=$(t_state timeLeft); (( left > 2695 && left <= 2700 )) || t_fail "timeLeft=$left, want ~2700"
t_pass "timeLeft counts down from 2700"

# set again → overwrite, no dialog
t_send "set:10:reboot"
t_assert_eq "$(t_state action)" "reboot" "a new set overwrites the action"
left=$(t_state timeLeft); (( left > 595 && left <= 600 )) || t_fail "timeLeft=$left, want ~600"
t_pass "a new set overwrites the duration"

# pause freezes the remainder and zeroes the target
t_send "pause"
t_assert_eq "$(t_state status)" "PAUSED" "pause enters PAUSED"
frozen=$(t_state timeLeft)
sleep 1.2
[[ "$(t_state timeLeft)" == "$frozen" ]] && t_pass "paused clock does not move" || t_fail "paused clock moved"

# resume re-anchors to now
t_send "resume"
t_assert_eq "$(t_state status)" "ACTIVE" "resume returns to ACTIVE"
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel did not reach IDLE"
t_pass "cancel returns to IDLE"

# snooze limit: 3 consecutive snoozes, then refusal
t_send "set:2:poweroff"
t_send "snooze:1"; t_send "snooze:1"; t_send "snooze:1"
t_assert_eq "$(t_state snoozeCount)" "3" "three snoozes are counted"
before=$(t_state targetTime)
t_send "snooze:1"
t_assert_eq "$(t_state targetTime)" "$before" "the fourth snooze is refused"
t_pass "snooze limit holds"

# a fresh set resets the snooze counter
t_send "set:2:poweroff"
t_assert_eq "$(t_state snoozeCount)" "0" "set resets the snooze counter"

t_send "cancel"
echo "test_state: all passed"
