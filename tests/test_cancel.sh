#!/usr/bin/env bash
# test_cancel.sh — cancel must work from every state, including the last
# second, and the action must not run after a cancel.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

# cancel from ACTIVE
t_send "set:30:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "timer is ACTIVE"
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel from ACTIVE failed"
t_pass "cancel from ACTIVE"

# cancel from PAUSED
t_send "set:30:poweroff"
t_send "pause"
t_assert_eq "$(t_state status)" "PAUSED" "timer is PAUSED"
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel from PAUSED failed"
t_pass "cancel from PAUSED"

# cancel during the COUNTDOWN window (the overlay state)
t_send "set:1:poweroff"           # 60 s → COUNTDOWN in overlaySeconds (30)
t_wait_for status COUNTDOWN 40 || t_fail "never reached COUNTDOWN (st=$(t_state status))"
t_pass "reached COUNTDOWN"
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel from COUNTDOWN failed"
t_pass "cancel from COUNTDOWN"

# cancel with ~1 s left. A 1-minute timer is too slow for the test, so rewind
# the target to now+3 and wait for the last seconds; then cancel and verify the
# action did NOT fire.
t_send "set:1:poweroff"
want=$(( $(date +%s) + 3 ))
for i in $(seq 1 20); do
  raw=$(<"$T_STATE/state.json")
  old_target=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
  [[ "$old_target" == "$want" ]] && break
  printf '%s\n' "${raw/\"targetTime\":$old_target/\"targetTime\":$want}" > "$T_STATE/state.json"
  sleep 0.15
done
i=0
while (( i < 100 )); do
  st=$(t_state status); left=$(t_state timeLeft)
  [[ "$st" != "IDLE" && -n "$left" && "$left" -le 2 ]] && break
  sleep 0.1; i=$((i + 1))
done
(( i < 100 )) || t_fail "never got into the last seconds (st=$st left=$left)"
t_send "cancel"
t_wait_for status IDLE 3 || t_fail "cancel in the last second failed"
t_pass "cancel in the last second"
sleep 1.2
grep -q "firing" "$T_STATE/daemon.log" && t_fail "the action fired despite the last-second cancel"
t_pass "last-second cancel won over the fire"

# ...and when nothing cancels, the timer does fire (ACTION_OVERRIDE=echo).
# Rewind the target to now+2 so the test does not wait a whole minute; the
# daemon re-reads state.json every loop, but its own write can land between
# our write and its next read, so verify and retry.
t_send "set:1:poweroff"
want=$(( $(date +%s) + 2 ))
for i in $(seq 1 20); do
  raw=$(<"$T_STATE/state.json")
  old_target=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
  [[ "$old_target" == "$want" ]] && break
  printf '%s\n' "${raw/\"targetTime\":$old_target/\"targetTime\":$want}" > "$T_STATE/state.json"
  sleep 0.15
done
t_wait_for status IDLE 8 || t_fail "the timer never fired (st=$(t_state status))"
t_pass "the timer fires when left alone"
grep -q "firing poweroff" "$T_STATE/daemon.log" || t_fail "no firing line in the daemon log"
t_pass "firing is logged"
grep -q "executed" "$T_STATE/history.tsv" || t_fail "no executed history entry"
t_pass "the fired run lands in history"

# cancel is idempotent
t_send "cancel"
t_assert_eq "$(t_state status)" "IDLE" "cancel when idle is a no-op"

echo "test_cancel: all passed"
