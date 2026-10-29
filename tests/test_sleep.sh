#!/usr/bin/env bash
# test_sleep.sh — a deadline that passes while the machine is suspended must
# open a visible countdown window on wake instead of firing into a black
# screen. Suspend is simulated with SIGSTOP/SIGCONT: the process is frozen
# for real seconds, which is exactly the loop-gap the daemon measures.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

# Short overlay window so the test does not wait 30 s. It must be shorter than
# the armed time, otherwise the daemon reaches COUNTDOWN on its own before the
# freeze and the ACTIVE sleep branch is never exercised.
printf '{"overlaySeconds":2}\n' > "$T_STATE/settings.json"
t_send "ping"   # let the daemon reload settings

t_send "set:1:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "timer armed"

# rewind the target to now+8 so the deadline lands well inside the freeze
want=$(( $(date +%s) + 8 ))
for i in $(seq 1 25); do
  raw=$(<"$T_STATE/state.json")
  old=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
  [[ "$old" == "$want" ]] && break
  printf '%s\n' "${raw/\"targetTime\":$old/\"targetTime\":$want}" > "$T_STATE/state.json"
  sleep 0.1
done

# "suspend": freeze the daemon for 7 s so the deadline passes while it sleeps
kill -STOP "$T_DAEMON_PID"
sleep 7
kill -CONT "$T_DAEMON_PID"

# on wake: COUNTDOWN window, not an instant fire
t_wait_for status COUNTDOWN 4 || t_fail "no countdown window after wake (st=$(t_state status))"
t_pass "deadline in sleep opens the countdown window"

# The sleep-gap line is written by whichever branch saw the gap: from ACTIVE it
# is "deadline passed during sleep", from an already-COUNTDOWN state it is
# "countdown slept through" (the test rewinds targetTime while the daemon still
# runs, so the state can legitimately have reached COUNTDOWN before the freeze).
# Both mean the same thing — accept either.
grep -qE "deadline passed during sleep|countdown slept through" "$T_STATE/daemon.log" \
  || { cp "$T_STATE/daemon.log" "/tmp/sleeplog.$$"; t_fail "no sleep log line (full log: /tmp/sleeplog.$$)"; }
t_pass "sleep window is logged"

# ...and the window still ends in a firing
t_wait_for status IDLE 10 || t_fail "the window never fired (st=$(t_state status))"
t_pass "the window fires after its time"
grep -q "firing poweroff" "$T_STATE/daemon.log" || t_fail "no firing line"
t_pass "firing is logged"

# a short gap (no sleep) must keep the instant-fire behaviour: arm, wait past
# the deadline with the daemon running normally → fires without a window
t_send "set:1:poweroff"
want=$(( $(date +%s) + 1 ))
for i in $(seq 1 25); do
  raw=$(<"$T_STATE/state.json")
  old=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
  [[ "$old" == "$want" ]] && break
  printf '%s\n' "${raw/\"targetTime\":$old/\"targetTime\":$want}" > "$T_STATE/state.json"
  sleep 0.1
done
t_wait_for status IDLE 6 || t_fail "the live timer never fired"
t_pass "a live timer still fires directly (no extra window)"

echo "test_sleep: all passed"
