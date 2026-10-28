#!/usr/bin/env bash
# test_override.sh — the live dry-run switch: with `action-override` present
# the daemon must log the action and run the override command instead of the
# real power command, so an E2E can end at zero without powering the PC off.
#
# The harness already exports ACTION_OVERRIDE=echo so tests never power off;
# to prove the FILE is what decides, the file gets a command whose output
# differs from `echo` ("printf 'FILEHIT %s\n'").
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

printf "printf 'FILEHIT %%s\\\\n'\n" > "$T_STATE/action-override"

fire_now() { # rewind the target to now+2 and wait for the firing
  local want=$(( $(date +%s) + 2 )) i raw old
  for i in $(seq 1 25); do
    raw=$(<"$T_STATE/state.json")
    old=$(printf '%s' "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
    [[ "$old" == "$want" ]] && break
    printf '%s\n' "${raw/\"targetTime\":$old/\"targetTime\":$want}" > "$T_STATE/state.json"
    sleep 0.15
  done
  t_wait_for status IDLE 8 || t_fail "the timer never fired (st=$(t_state status))"
}

t_send "set:1:poweroff"
fire_now
t_pass "the timer fired without a real power action"

grep -q "executed via override: printf" "$T_STATE/daemon.log" || t_fail "the file override did not run (log: $(tail -3 "$T_STATE/daemon.log"))"
t_pass "the firing went through the FILE override, not the env one"

# with the file gone, the env override takes over again
rm -f "$T_STATE/action-override"
t_send "set:1:poweroff"
fire_now
grep -q "executed via override: echo" "$T_STATE/daemon.log" || t_fail "env override not honoured after the file was removed"
t_pass "env override is honoured when the file is absent"

echo "test_override: all passed"
