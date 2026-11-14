#!/usr/bin/env bash
# Layout tests: everything sits on the dial's axis, nothing spills out.
#
# Like the gesture tests these need the running widget, and skip when no shell
# answers. The centre check is what catches "the input drifted to the side":
# a fixed-width row packed left used to be 14 px off and nobody noticed.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN"
CTL=(bash control.sh)
IPC=(omarchy-shell honor.shutdown-timer)

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

if ! "${IPC[@]}" status >/dev/null 2>&1; then
  echo "SKIP: no running shell (layout tests need the live widget)"
  exit 0
fi

cleanup() {
  "${CTL[@]}" cancel >/dev/null 2>&1 || true
  "${IPC[@]}" debugTray "" >/dev/null 2>&1 || true
  "${IPC[@]}" close >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${CTL[@]}" override echo >/dev/null 2>&1
"${IPC[@]}" open >/dev/null 2>&1
sleep 1

# ---- the dial, the input and the hint share one axis
geom=$("${IPC[@]}" debugGeom)
centre=$(echo "$geom" | python3 -c "import sys,json;print(json.load(sys.stdin)['column']['w']//2)")
for key in dial row hint; do
  cx=$(echo "$geom" | python3 -c "import sys,json;print(json.load(sys.stdin)['$key']['cx'])")
  d=$(( cx - centre )); (( d < 0 )) && d=$(( -d ))
  (( d <= 1 )) && ok "$key is on the axis (cx=$cx, centre=$centre)" || bad "$key is $d px off the axis (cx=$cx, centre=$centre)"
done

# ---- the presets mirror each other
left=$(echo "$geom" | python3 -c "import sys,json;print(json.load(sys.stdin)['presetsLeft']['x'])")
right=$(echo "$geom" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['column']['w']-(d['presetsRight']['x']+d['presetsRight']['w']))")
(( left == right )) && ok "preset columns are symmetric (margin $left)" || bad "preset margins differ: left=$left right=$right"

# ---- nothing crosses the column, in any section
for section in "" repeat more history; do
  if [[ -z "$section" ]]; then
    "${IPC[@]}" debugTray "" >/dev/null 2>&1
  else
    "${IPC[@]}" debugTray "$section" >/dev/null 2>&1
  fi
  sleep 0.9
  n=$("${IPC[@]}" debugOverflow | python3 -c "import sys,json;print(json.load(sys.stdin)['count'])")
  (( n == 0 )) && ok "no overflow (${section:-idle})" || bad "overflow in ${section:-idle}: $n items"
done

# ---- and while a timer runs, where the extra keys appear
"${IPC[@]}" debugTray "" >/dev/null 2>&1
"${CTL[@]}" set 30 >/dev/null 2>&1; sleep 1.2
n=$("${IPC[@]}" debugOverflow | python3 -c "import sys,json;print(json.load(sys.stdin)['count'])")
(( n == 0 )) && ok "no overflow (active)" || bad "overflow when active: $n items"

echo "== layout: $pass passed, $fail failed =="
(( fail == 0 ))
