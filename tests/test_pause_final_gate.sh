#!/usr/bin/env bash
# test_pause_final_gate.sh — a pause written while the daemon is inside the
# final checks must stop the action, exactly as a cancel already does.
#
# The window is widened deterministically. In the COUNTDOWN branch `pgrep` runs
# only once `time_left <= 0`, i.e. inside the final checks, so a shim pgrep that
# sleeps only while the daemon reports COUNTDOWN marks exactly that moment. A
# pause written then cannot be swallowed by the next tick's drain_control
# instead — which is what made this defect invisible to the earlier cancel test.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

SHIM_DIR="$T_ROOT/bin"
mkdir -p "$SHIM_DIR"
export TIMER_TEST_GATE_MARK="$T_ROOT/inside-final-checks"
export TIMER_TEST_STATE_DIR="$T_STATE"
cat > "$SHIM_DIR/pgrep" <<'SH'
#!/usr/bin/env bash
# Slow only when the daemon is COUNTDOWN, i.e. already inside the final checks;
# everything else (the harness's own `pgrep -f`) stays instant.
if [[ -f "$TIMER_TEST_STATE_DIR/state.json" ]] \
   && grep -q '"status": *"COUNTDOWN"' "$TIMER_TEST_STATE_DIR/state.json"; then
  : > "${TIMER_TEST_GATE_MARK:-/dev/null}"
  sleep 2
fi
exec /usr/bin/pgrep "$@"
SH
chmod +x "$SHIM_DIR/pgrep"
export PATH="$SHIM_DIR:$PATH"

FIRE_LOG="$T_ROOT/fired.log"
cat > "$T_ROOT/record-fire" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$FIRE_LOG"
SH
chmod +x "$T_ROOT/record-fire"

mkdir -p "$T_STATE"
# waitForProcesses names a process that never exists: that is what makes the
# daemon call pgrep at all, and the shim needs the call to hold the window open.
printf '%s\n' '{"overlaySeconds":5,"waitForProcesses":"gate-test-never","webhookUrl":""}' > "$T_STATE/settings.json"
t_setup
printf '%s\n' "$T_ROOT/record-fire" > "$T_STATE/action-override"

t_send "set-secs:6:poweroff"
t_assert_eq "$(t_state status)" "ACTIVE" "timer armed for six seconds"

# Wait for the daemon to be inside the final checks, then pause it there.
for _ in $(seq 1 300); do
  [[ -f "$TIMER_TEST_GATE_MARK" ]] && break
  sleep 0.1
done
[[ -f "$TIMER_TEST_GATE_MARK" ]] || t_fail "daemon never reached the final checks"

printf 'pause\n' > "$T_STATE/control"
t_poke
sleep 6

t_assert_eq "$(t_state status)" "PAUSED" "the pause is recorded"
[[ ! -s "$FIRE_LOG" ]] || t_fail "the action fired even though a pause was recorded ($(cat "$FIRE_LOG"))"
t_pass "no fire after a pause inside the final checks"
grep -q "pause arrived during the final checks" "$T_STATE/daemon.log" \
  || t_fail "the pause was not handled by the final gate"
t_pass "the final gate logged the dropped firing"
t_teardown
trap - EXIT
