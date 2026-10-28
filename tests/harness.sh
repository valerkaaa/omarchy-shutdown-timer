#!/usr/bin/env bash
# Shared harness for the plugin's tests: an isolated daemon on a scratch
# state dir with ACTION_OVERRIDE=echo so nothing ever powers the machine off.
#
# Every test sources this, then uses:
#   t_setup        start the isolated daemon
#   t_send CMD     send a raw command and wait for the daemon to apply it
#   t_state FIELD  read a field from state.json
#   t_wait_for FIELD VALUE [TIMEOUT]
#   t_teardown     kill the daemon and clean up

set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T_ROOT="$(mktemp -d /tmp/shutdown-timer-test.XXXXXX)"
export XDG_STATE_HOME="$T_ROOT/state"
T_STATE="$XDG_STATE_HOME/omarchy/plugins/shutdown-timer"
T_DAEMON_PID=""

t_fail() { echo "FAIL: $*" >&2; exit 1; }
t_pass() { echo "ok - $*"; }

t_setup() {
  mkdir -p "$T_STATE"
  export ACTION_OVERRIDE="${ACTION_OVERRIDE:-echo}"
  setsid bash "$PLUGIN_DIR/daemon.sh" >"$T_ROOT/daemon.log" 2>&1 </dev/null &
  local i
  for i in $(seq 1 40); do
    sleep 0.1
    [[ -f "$T_STATE/daemon.pid" ]] && T_DAEMON_PID=$(cat "$T_STATE/daemon.pid") && kill -0 "$T_DAEMON_PID" 2>/dev/null && return 0
  done
  t_fail "daemon did not start"
}

# Opening a FIFO for writing BLOCKS while no reader exists; opening RDWR
# never does. So every poke goes through an RDWR fd.
t_poke() {
  exec 4<>"$T_STATE/wake"
  printf '\n' >&4
  exec 4>&-
}

t_send() {
  printf '%s\n' "$1" > "$T_STATE/control"
  t_poke
  sleep 0.4
}

t_state() {
  local key="$1" raw=""
  [[ -f "$T_STATE/state.json" ]] && raw=$(<"$T_STATE/state.json")
  if [[ $raw =~ \"$key\":\ *\"([^\"]*)\" ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ $raw =~ \"$key\":\ *(-?[0-9]+) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  echo ""
}

t_wait_for() { # field value timeout_s
  local field="$1" want="$2" limit="${3:-5}" i=0
  while (( i < limit * 10 )); do
    [[ "$(t_state "$field")" == "$want" ]] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

t_assert_eq() { # got want label
  [[ "$1" == "$2" ]] || t_fail "$3: got '$1', want '$2'"
  t_pass "$3"
}

t_teardown() {
  # Kill the tracked daemon AND any other daemon that belongs to THIS test's
  # state dir — test_daemon restarts the daemon several times, and a failure
  # mid-way would otherwise leak the untracked ones.
  local p
  for p in $(pgrep -f 'plugins/honor.shutdown-timer/daemon.sh' 2>/dev/null); do
    [[ "$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^XDG_STATE_HOME=//p')" == "$XDG_STATE_HOME" ]] && kill "$p" 2>/dev/null
  done
  [[ -n "$T_DAEMON_PID" ]] && kill "$T_DAEMON_PID" 2>/dev/null
  sleep 0.3
  for p in $(pgrep -f 'plugins/honor.shutdown-timer/daemon.sh' 2>/dev/null); do
    [[ "$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^XDG_STATE_HOME=//p')" == "$XDG_STATE_HOME" ]] && kill -9 "$p" 2>/dev/null
  done
  rm -rf "$T_ROOT"
}
