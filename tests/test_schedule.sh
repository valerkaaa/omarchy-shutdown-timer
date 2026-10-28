#!/usr/bin/env bash
# test_schedule.sh — schedules are stored, listed, fire once per day, and
# re-arm for the next matching weekday; removal works.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup
SCHED="$T_STATE/schedules.tsv"

# add via the daemon command (the CLI does the same)
t_send "schedule-add:1001:23:30:1,2,3,4,5:poweroff"
[[ -f "$SCHED" ]] || t_fail "schedules file was not created"
grep -q '^1001' "$SCHED" || t_fail "schedule not stored"
t_pass "schedule stored"

# count is published in state.json for the bar dot
t_send "ping"
t_assert_eq "$(t_state scheduleCount)" "1" "scheduleCount published"

# weekly match: today's weekday must match, other days must not
today=$(date +%u)
t_send "schedule-add:1002:23:30:$today:reboot"
t_send "ping"
t_assert_eq "$(t_state scheduleCount)" "2" "second schedule stored"

# fire: force the stored time to the current minute and clear lastFired
now_hm=$(date +%H:%M)
sed -i "s/^1002\t[^\t]*/1002\t$now_hm/" "$SCHED"
sed -i "s/^1001\t[^\t]*/1001\t23:59/" "$SCHED"
# clear the lastFired column for 1002 so today counts as unfired
awk -F'\t' 'BEGIN{OFS="\t"} $1=="1002"{$5="-"} {print}' "$SCHED" > "$SCHED.tmp" && mv "$SCHED.tmp" "$SCHED"

# the daemon checks schedules while IDLE; give it a nudge
t_send "ping"
t_wait_for status "COUNTDOWN_SCHED" 5 || t_fail "schedule did not fire (st=$(t_state status))"
t_pass "matching schedule fires"

# it must be marked as fired for today, so it does not fire twice
last=$(awk -F'\t' '$1=="1002"{print $5}' "$SCHED")
[[ "$last" == "$(date +%F)" ]] || t_fail "schedule not marked fired today (got '$last')"
t_pass "schedule marked fired for today"

# while COUNTDOWN_SCHED, the same schedule must not re-fire
sleep 1.2
t_send "ping"
st=$(t_state status)
[[ "$st" == "COUNTDOWN_SCHED" ]] || t_fail "state changed to $st unexpectedly"
t_pass "no double fire"

# cancel stops it and returns to IDLE
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel of a scheduled firing failed"
t_pass "cancel after schedule"

# remove
t_send "schedule-remove:1001"
t_send "ping"
t_assert_eq "$(t_state scheduleCount)" "1" "schedule removed"

# a schedule on another weekday does not fire today
t_send "schedule-remove:1002"
other=$(( today % 7 + 1 ))
t_send "schedule-add:1003:$now_hm:$other:poweroff"
t_send "ping"
sleep 1.2
st=$(t_state status)
[[ "$st" == "IDLE" ]] || t_fail "off-day schedule fired (st=$st, today=$today other=$other)"
t_pass "off-day schedule stays idle"

echo "test_schedule: all passed"
