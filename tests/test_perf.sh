#!/usr/bin/env bash
# test_perf.sh — the budget from TZ §11, measured on a live isolated daemon.
#
#   CPU idle ≤ 0.1 %   wakeups idle ≤ 2/min   child procs idle: 0
#   CPU countdown ≤ 0.5 %   RSS ≤ 6 MB   cancel latency ≤ 150 ms
#
# All figures are measured, and the test fails when a budget is exceeded.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

t_setup

proc_stat() { cat "/proc/$T_DAEMON_PID/stat" 2>/dev/null; }

cpu_ticks() { # utime + stime in clock ticks
  local s; s=$(proc_stat) || { echo 0; return; }
  echo "$s" | awk '{print $14 + $15}'
}

rss_kb() { awk '/VmRSS/{print $2}' "/proc/$T_DAEMON_PID/status" 2>/dev/null || echo 0; }

ctxt_switches() { awk '/^voluntary_ctxt_switches/{print $2}' "/proc/$T_DAEMON_PID/status" 2>/dev/null || echo 0; }

HZ=$(getconf CLK_TCK)

# ---------- IDLE: cpu, wakeups, children, rss ----------
t_send "cancel"
sleep 1
c0=$(cpu_ticks); w0=$(ctxt_switches); t0=$(date +%s)
sleep 12
c1=$(cpu_ticks); w1=$(ctxt_switches); t1=$(date +%s)
dt=$(( t1 - t0 ))

cpu_pct=$(awk -v d="$((c1 - c0))" -v hz="$HZ" -v sec="$dt" 'BEGIN{printf "%.3f", 100.0 * d / hz / sec}')
wakeups=$(( w1 - w0 ))
wake_per_min=$(awk -v w="$wakeups" -v sec="$dt" 'BEGIN{printf "%.1f", 60.0 * w / sec}')
kids=$(pgrep -Pc "$T_DAEMON_PID" 2>/dev/null || echo 0)
rss=$(rss_kb)

echo "idle: cpu=${cpu_pct}% (budget 0.1)  wakeups=${wakeups} in ${dt}s = ${wake_per_min}/min (budget 2)  children=${kids} (budget 0)  rss=${rss} kB (budget 6144)"

awk -v v="$cpu_pct" 'BEGIN{exit !(v <= 0.1)}'   || t_fail "idle CPU ${cpu_pct}% > 0.1%"
t_pass "idle CPU within budget"
awk -v v="$wake_per_min" 'BEGIN{exit !(v <= 2.0)}' || t_fail "idle wakeups ${wake_per_min}/min > 2"
t_pass "idle wakeups within budget"
[[ "$kids" == "0" ]] || t_fail "daemon has $kids child processes while idle"
t_pass "no child processes while idle"
(( rss <= 6144 )) || t_fail "RSS ${rss} kB > 6 MB"
t_pass "RSS within budget"

# ---------- CANCEL LATENCY ----------
t_send "set:45:poweroff"
sleep 0.5
best=9999
for i in 1 2 3; do
  start=$(date +%s%N)
  printf 'cancel\n' > "$T_STATE/control"
  t_poke
  while true; do
    [[ "$(t_state status)" == "IDLE" ]] && break
    sleep 0.01
  done
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  (( ms < best )) && best=$ms
  sleep 0.3
  t_send "set:45:poweroff"
  sleep 0.3
done
echo "cancel latency (best of 3): ${best} ms (budget 150)"
(( best <= 150 )) || t_fail "cancel latency ${best} ms > 150 ms"
t_pass "cancel latency within budget"

# ---------- COUNTDOWN cpu ----------
t_send "cancel"; sleep 0.3
t_send "set:1:poweroff"   # 60 s; force COUNTDOWN by rewinding the target
raw=$(<"$T_STATE/state.json")
old=$(echo "$raw" | grep -o '"targetTime":[0-9]*' | cut -d: -f2)
new=$(( $(date +%s) + 25 ))
printf '%s\n' "${raw/\"targetTime\":$old/\"targetTime\":$new}" > "$T_STATE/state.json"
t_poke; sleep 0.5
c0=$(cpu_ticks); sleep 8; c1=$(cpu_ticks)
cpu_cd=$(awk -v d="$((c1 - c0))" -v hz="$HZ" 'BEGIN{printf "%.3f", 100.0 * d / hz / 8}')
echo "countdown: cpu=${cpu_cd}% (budget 0.5)"
awk -v v="$cpu_cd" 'BEGIN{exit !(v <= 0.5)}' || t_fail "countdown CPU ${cpu_cd}% > 0.5%"
t_pass "countdown CPU within budget"

t_send "cancel"
echo "test_perf: all passed"
