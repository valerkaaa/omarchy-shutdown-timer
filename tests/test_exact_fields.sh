#!/usr/bin/env bash
# test_exact_fields.sh — the mm/ss boxes are read-only to Qt (a writable
# QQuickTextInput pulls the whole clipboard on every change, QTBUG-149610), so
# the plugin feeds the digits itself. That makes typing, the range clamp, Tab
# and Backspace the plugin's own code and worth a test.
#
# Needs the running widget, like the layout and gesture tests: it drives the
# real panel with wtype and reads the state back from the daemon.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
IPC=(omarchy-shell honor.shutdown-timer)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/plugins/shutdown-timer/state.json"

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

if ! "${IPC[@]}" status >/dev/null 2>&1; then
  echo "SKIP: no running shell (this test drives the live panel)"
  exit 0
fi
if ! command -v wtype >/dev/null; then
  echo "SKIP: wtype is not installed"
  exit 0
fi

left() { python3 -c "import json;print(json.load(open('$STATE'))['timeLeft'])"; }
status() { python3 -c "import json;print(json.load(open('$STATE'))['status'])"; }
texts() { "${IPC[@]}" debugTexts; }

reset_panel() {
  bash control.sh cancel >/dev/null 2>&1
  "${IPC[@]}" close >/dev/null 2>&1
  sleep 0.6
}

open_focus() {
  "${IPC[@]}" open >/dev/null
  sleep 2.2
  "${IPC[@]}" debugFieldFocus >/dev/null
  sleep 0.6
  # the panel's first window activation can drop the forced focus; retry once
  case "$(texts)" in *'"mmFocus":true'*) ;; *) "${IPC[@]}" debugFieldFocus >/dev/null; sleep 0.5 ;; esac
}

expect_state() { # want_left label
  local want="$1" label="$2" got
  got="$(left)"
  if (( got <= want + 2 && got >= want - 2 )); then ok "$label (left=${got}s)"
  else bad "$label: left=${got}s, want ~${want}s"; fi
}

trap 'bash control.sh cancel >/dev/null 2>&1; "${IPC[@]}" close >/dev/null 2>&1 || true' EXIT

# --- the security property: Qt never sees a writable field -----------------
reset_panel; open_focus
case "$(texts)" in
  *'"mmReadOnly":true'*'"ssReadOnly":true'*) ok "both boxes are read-only to Qt" ;;
  *) bad "a box is writable to Qt: $(texts)" ;;
esac

# --- digits ---------------------------------------------------------------
wtype 7; sleep 0.3
case "$(texts)" in *'"mm":"7"'*) ok "a typed digit lands in the box" ;; *) bad "typed digit lost: $(texts)" ;; esac
wtype -k Return; sleep 1.2
expect_state 420 "7 minutes starts 420 s"

# --- range clamp: 720 + a fourth digit is refused -------------------------
reset_panel; open_focus
wtype 7; sleep 0.1; wtype 2; sleep 0.1; wtype 0; sleep 0.1; wtype 0; sleep 0.3
case "$(texts)" in *'"mm":"720"'*) ok "the 720 minute ceiling is enforced" ;; *) bad "clamp failed: $(texts)" ;; esac
wtype -k Return; sleep 1.2
expect_state 43200 "720 minutes starts 43200 s"

# --- Tab reaches the seconds box ------------------------------------------
reset_panel; open_focus
wtype 1; sleep 0.2; wtype -k Tab; sleep 0.4; wtype 3; sleep 0.1; wtype 0; sleep 0.3
case "$(texts)" in
  *'"mm":"1","ss":"30"'*) ok "Tab moves into the seconds box" ;;
  *) bad "Tab did not reach the seconds box: $(texts)" ;;
esac
wtype -k Return; sleep 1.2
expect_state 90 "1:30 starts 90 s"

# --- Backspace ------------------------------------------------------------
reset_panel; open_focus
wtype 4; sleep 0.1; wtype 5; sleep 0.1; wtype 9; sleep 0.2; wtype -k BackSpace; sleep 0.3
case "$(texts)" in *'"mm":"45"'*) ok "Backspace removes the last digit" ;; *) bad "Backspace failed: $(texts)" ;; esac
wtype -k Return; sleep 1.2
expect_state 2700 "45 minutes starts 2700 s"

reset_panel
echo "  -- exact fields: $pass passed, $fail failed"
(( fail == 0 )) || exit 1
