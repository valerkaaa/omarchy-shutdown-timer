#!/usr/bin/env bash
# test_absolute.sh — HH:MM in the past rolls to tomorrow; HH:MM right now
# is accepted; the target is on the wall clock (not a counter).
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

now_epoch() { date +%s; }

# a time ~2 minutes ahead today
future=$(date -d '+2 minutes' +%H:%M)
t_send "set-abs:$future:poweroff"
t_assert_eq "$(t_state mode)" "absolute" "absolute mode is recorded"
target=$(t_state targetTime)
now=$(now_epoch)
delta=$((target - now))
(( delta > 60 && delta <= 180 )) || t_fail "target delta=$delta for $future, want ~120"
t_pass "future HH:MM lands ~2 min ahead ($delta s)"

# a time ~1 hour in the past must roll to tomorrow
past=$(date -d '-1 hour' +%H:%M)
t_send "set-abs:$past:poweroff"
target=$(t_state targetTime)
now=$(now_epoch)
delta=$((target - now))
(( delta > 82000 && delta <= 90000 )) || t_fail "past HH:MM delta=$delta, want ~23h"
t_pass "past HH:MM rolls to tomorrow ($delta s)"

# the countdown is recomputed from the wall clock, not a counter:
# timeLeft must roughly equal target - now
left=$(t_state timeLeft)
[[ $(( left - delta )) -le 2 && $(( delta - left )) -le 2 ]] || t_fail "timeLeft=$left vs delta=$delta"
t_pass "timeLeft matches wall-clock target"

t_send "cancel"
echo "test_absolute: all passed"
