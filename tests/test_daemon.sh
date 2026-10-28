#!/usr/bin/env bash
# test_daemon.sh — single instance (flock), recovery after kill -9, no
# double daemons, and state kept across a restart.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

# a second daemon must exit immediately (flock), leaving the first alive
setsid bash "$PLUGIN_DIR/daemon.sh" >>"$T_ROOT/daemon2.log" 2>&1 </dev/null &
sleep 1
pid_file=$(cat "$T_STATE/daemon.pid")
count=$(pgrep -fc "daemon.sh" || true)
t_assert_eq "$pid_file" "$T_DAEMON_PID" "pid file still points at the first daemon"
# log() writes to the state dir's daemon.log, not the stdout redirect file
grep -q "another instance holds the lock" "$T_STATE/daemon.log" || t_fail "second instance did not report the lock"
t_pass "second instance refused by flock"

# state survives kill -9
t_send "set:45:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "timer armed before the kill"
kill -9 "$T_DAEMON_PID"
sleep 0.5

# restart: the daemon must restore ACTIVE with its target intact
target_before=$(t_state targetTime)
setsid bash "$PLUGIN_DIR/daemon.sh" >>"$T_ROOT/daemon3.log" 2>&1 </dev/null &
sleep 1
new_pid=$(cat "$T_STATE/daemon.pid")
[[ "$new_pid" != "$T_DAEMON_PID" ]] || t_fail "daemon pid did not change"
T_DAEMON_PID="$new_pid"
t_assert_eq "$(t_state status)" "ACTIVE" "state restored after kill -9"
t_assert_eq "$(t_state targetTime)" "$target_before" "target preserved after kill -9"
grep -q "restored ACTIVE" "$T_STATE/daemon.log" || t_fail "no restore log line"
t_pass "resume after kill -9 is logged"

# an overdue target (time passed while the daemon was away) shows the
# countdown window instead of firing instantly.
# Arm the timer while the daemon is ALIVE first — a command left in the
# control file would otherwise be drained at startup and mask the overdue
# path (it would arm a fresh 60 s timer instead of restoring the past one).
printf 'set:1:poweroff\n' > "$T_STATE/control"; t_poke
sleep 0.8
t_assert_eq "$(t_state status)" "ACTIVE" "fresh 60 s timer armed"

kill -9 "$T_DAEMON_PID"; sleep 0.3
# rewind targetTime to "2 seconds ago" so a restart sees an overdue timer
raw=$(<"$T_STATE/state.json")
old_target=$(echo "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
new_target=$(( $(date +%s) - 2 ))
printf '%s\n' "${raw/\"targetTime\":$old_target/\"targetTime\":$new_target}" > "$T_STATE/state.json"

setsid bash "$PLUGIN_DIR/daemon.sh" >>"$T_ROOT/daemon4.log" 2>&1 </dev/null &
sleep 1.5
new_pid=$(cat "$T_STATE/daemon.pid"); T_DAEMON_PID="$new_pid"
st=$(t_state status)
[[ "$st" == "COUNTDOWN" ]] || t_fail "overdue timer did not open the countdown window (st=$st)"
t_pass "overdue timer opens the countdown window"
grep -q "overdue" "$T_STATE/daemon.log" || t_fail "no overdue log line"
t_pass "overdue restore is logged"

t_send "cancel"
echo "test_daemon: all passed"
