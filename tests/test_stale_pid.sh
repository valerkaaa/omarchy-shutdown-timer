#!/usr/bin/env bash
# Stale pid: a daemon killed with SIGKILL leaves its pid file behind, and the
# kernel eventually hands that number to somebody else. `daemon-stop` must not
# shoot the stranger — the lock, not the pid, says whether the daemon lives.
#
# Runs against an isolated state dir, so the live widget's daemon is untouched.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/st-pid.XXXXXX")
export XDG_STATE_HOME="$TMP"
STATE_DIR="$TMP/omarchy/plugins/shutdown-timer"
PID_FILE="$STATE_DIR/daemon.pid"
LOCK_FILE="$STATE_DIR/daemon.lock"
CTL=(bash control.sh)

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

foreign=""
cleanup() {
  [[ -n "$foreign" ]] && kill "$foreign" 2>/dev/null
  bash control.sh daemon-stop >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---- 1. устаревший pid: демона нет, номер достался чужому процессу
sleep 300 &
foreign=$!
sleep 0.2
if ! kill -0 "$foreign" 2>/dev/null; then
  echo "SKIP: не удалось запустить подставной процесс"
  exit 0
fi

mkdir -p "$STATE_DIR"
: > "$LOCK_FILE"                    # файл замка есть, но никто его не держит
printf '%s\n' "$foreign" > "$PID_FILE"

"${CTL[@]}" daemon-stop >/dev/null 2>&1
if kill -0 "$foreign" 2>/dev/null; then
  ok "чужой процесс с устаревшим pid жив"
else
  bad "daemon-stop убил чужой процесс (устаревший pid)"
fi

if [[ -e "$PID_FILE" ]]; then
  bad "устаревший pid-файл остался на диске"
else
  ok "устаревший pid-файл убран"
fi

# ---- 2. живой демон по-прежнему останавливается
"${CTL[@]}" ensure >/dev/null 2>&1
sleep 0.6
if ! kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  bad "демон не поднялся в изолированном каталоге"
else
  ok "демон поднялся в изолированном каталоге"
fi

if "${CTL[@]}" daemon-stop 2>&1 | grep -q "daemon stopped"; then
  ok "живой демон останавливается"
else
  bad "живой демон не остановился"
fi

sleep 0.5
if [[ -e "$PID_FILE" ]]; then
  bad "pid-файл остался после остановки демона"
else
  ok "pid-файл убран после остановки"
fi

# ---- 3. замок свободен после остановки: следующий старт не блокируется
"${CTL[@]}" ensure >/dev/null 2>&1
sleep 0.6
if kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  ok "повторный старт после остановки работает"
else
  bad "повторный старт не поднял демон"
fi

echo "  -- stale-pid: $pass passed, $fail failed"
(( fail == 0 ))
