#!/usr/bin/env bash
# test_webhook_args.sh — the webhook URL is a secret, so it must never appear in
# a process's arguments: /proc/<pid>/cmdline is readable by every local account.
# curl reads its whole request from a config on stdin (-K -) instead.
#
# Three phases, each with its own daemon:
#   1. a curl shim records argv and stdin  -> no token in argv, config on stdin
#   2. a real curl posts to a local server -> the request still works
#   3. a URL with a newline               -> refused, no directive injected
set -u
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
trap t_teardown EXIT

CAP="$T_ROOT/curl-calls"
SHIM_DIR="$T_ROOT/bin"
export TIMER_TEST_CURL_CAP="$CAP"
SENTINEL="T0K3N-SENTINEL-4f8a2c"

make_curl_shim() {
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/curl" <<'SH'
#!/usr/bin/env bash
n=$(ls "$TIMER_TEST_CURL_CAP"/*.argv 2>/dev/null | wc -l)
printf '%s\n' "$@" > "$TIMER_TEST_CURL_CAP/$n.argv"
cat > "$TIMER_TEST_CURL_CAP/$n.stdin"
exit 0
SH
  chmod +x "$SHIM_DIR/curl"
}

# t_teardown wipes T_ROOT, so every phase recreates what it needs.
fresh_phase() {
  t_teardown
  mkdir -p "$T_STATE" "$CAP"
  make_curl_shim
}

cat > "$T_ROOT/record-fire" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$T_ROOT/fired.log"
SH
chmod +x "$T_ROOT/record-fire"

# --- phase 1: what curl is handed ------------------------------------------
fresh_phase
export PATH="$SHIM_DIR:$PATH"
printf '{"overlaySeconds":5,"webhookUrl":"https://hooks.example.test/services/%s"}\n' "$SENTINEL" \
  > "$T_STATE/settings.json"
t_setup
printf '%s\n' "$T_ROOT/record-fire" > "$T_STATE/action-override"

t_send "set-secs:6:poweroff"
t_wait_for status IDLE 30 || t_fail "the timer never completed a firing"
grep -q "executed" "$T_STATE/history.tsv" || t_fail "no firing was recorded"

if grep -l -- "$SENTINEL" "$CAP"/*.argv >/dev/null 2>&1; then
  t_fail "the webhook URL is in curl's argv: $(cat "$CAP"/*.argv | tr '\n' ' ')"
fi
t_pass "curl received no argument that contains the token"
grep -qs -- "url = \"https://hooks.example.test/services/$SENTINEL\"" "$CAP"/*.stdin \
  || t_fail "the URL never reached curl: $(head -3 "$CAP"/*.stdin 2>/dev/null)"
t_pass "the URL reached curl through its config on stdin"
grep -qs -- 'data = ' "$CAP"/*.stdin || t_fail "the request body is not in the config"
t_pass "the request body is in the config, not in an argument"

# --- phase 2: a real curl still sends the right request --------------------
fresh_phase
unset TIMER_TEST_CURL_CAP
export PATH="${PATH#"$SHIM_DIR:"}"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
RECV="$T_ROOT/received.json"
python3 "$(dirname "${BASH_SOURCE[0]}")/webhook_server.py" "$PORT" "$RECV" &
SERVER=$!
printf '{"overlaySeconds":5,"webhookUrl":"http://127.0.0.1:%s/hook?token=%s"}\n' "$PORT" "$SENTINEL" \
  > "$T_STATE/settings.json"
t_setup
printf '%s\n' "$T_ROOT/record-fire" > "$T_STATE/action-override"
t_send "set-secs:6:poweroff"

for _ in $(seq 1 250); do [[ -s "$RECV" ]] && break; sleep 0.1; done
kill "$SERVER" 2>/dev/null || true
[[ -s "$RECV" ]] || t_fail "the real curl never delivered the webhook"
t_pass "the real curl delivered the webhook"

python3 - "$RECV" "$SENTINEL" <<'PY' || t_fail "the delivered request is not the one the daemon built"
import json, sys
recv = json.load(open(sys.argv[1]))
body = json.loads(recv["body"])
assert recv["path"] == "/hook?token=" + sys.argv[2], recv["path"]
assert recv["content_type"].startswith("application/json"), recv["content_type"]
assert body == {"plugin": "shutdown-timer", "action": "poweroff", "at": body["at"]}, body
PY
t_pass "path, content type and JSON body arrived intact"

# --- phase 3: a URL that cannot be one config value is refused -------------
fresh_phase
export PATH="$SHIM_DIR:$PATH"
{ printf '{"overlaySeconds":5,"webhookUrl":"https://hooks.example.test/x\n'
  printf 'output = "/tmp/shutdown-timer-pwned"\n"}\n'; } > "$T_STATE/settings.json"
rm -f /tmp/shutdown-timer-pwned
t_setup
printf '%s\n' "$T_ROOT/record-fire" > "$T_STATE/action-override"
t_send "set-secs:6:poweroff"
t_wait_for status IDLE 30 || t_fail "the third timer never fired"
sleep 0.5
[[ -z "$(ls "$CAP"/*.argv 2>/dev/null)" ]] || t_fail "curl ran with a URL carrying a newline"
t_pass "a URL with a control character never reaches curl"
[[ ! -e /tmp/shutdown-timer-pwned ]] || t_fail "the injected config directive was honoured"
t_pass "no config directive was injected"
grep -q "webhook skipped: URL has a character a curl config cannot hold" "$T_STATE/daemon.log" \
  || t_fail "the refusal was not logged"
t_pass "the refusal is in the log"
