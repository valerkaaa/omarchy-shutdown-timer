#!/usr/bin/env bash
#
# control.sh — CLI и лаунчер плагина shutdown-timer (TZ 9.7).
#
#   control.sh set <mins> [action]         поставить на N минут
#   control.sh at <HH:MM> [action]         поставить на время (завтра, если прошло)
#   control.sh cancel                      отменить
#   control.sh pause | resume              пауза / продолжить
#   control.sh snooze [mins]               отложить (по умолчанию из настроек)
#   control.sh reset                       перевзвести текущий таймер
#   control.sh status [--json]             состояние
#   control.sh schedule add <HH:MM> <days> [action]
#   control.sh schedule list | remove <id>
#   control.sh history [--json]            последние запуски
#   control.sh ensure | daemon-stop
#   control.sh override [cmd|off]          сухой прогон: не выключать ПК
#   control.sh send <raw>                  произвольная команда демону
#   control.sh get-state                   сырой state.json
#
# Команды идут двумя путями: файл control (читается демоном и удаляется) и
# FIFO-пробуждение, чтобы демон не просыпался каждую секунду в покое.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/plugins/shutdown-timer"
mkdir -p "$STATE_DIR"

STATE_FILE="$STATE_DIR/state.json"
OVERRIDE_FILE="$STATE_DIR/action-override"
CONTROL_FILE="$STATE_DIR/control"
FIFO="$STATE_DIR/wake"
PID_FILE="$STATE_DIR/daemon.pid"
SETTINGS_FILE="$STATE_DIR/settings.json"
HISTORY_FILE="$STATE_DIR/history.tsv"
SCHEDULES_FILE="$STATE_DIR/schedules.tsv"

WEEKDAYS_RU=(Пн Вт Ср Чт Пт Сб Вс)
WEEKDAYS_EN=(Mon Tue Wed Thu Fri Sat Sun)

# ---------- daemon lifecycle ----------

is_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

ensure_daemon() {
  if ! is_running; then
    nohup bash "$SCRIPT_DIR/daemon.sh" >> "$STATE_DIR/daemon.log" 2>&1 &
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.2
      is_running && { echo "daemon started (pid $(cat "$PID_FILE"))"; return 0; }
    done
    echo "ERROR: daemon failed to start" >&2
    return 1
  fi
}

daemon_stop() {
  if is_running; then
    local pid
    pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null || true
    echo "daemon stopped (pid $pid)"
  else
    echo "daemon not running"
  fi
}

# ---------- dry run ----------

cmd_override() { # [cmd|off|status]
  local want="${1:-status}"
  case "$want" in
    status|"")
      [[ -s "$OVERRIDE_FILE" ]] && echo "override: $(<"$OVERRIDE_FILE") <action>" || echo "override: off (real power actions)"
      ;;
    off|none|real)
      rm -f "$OVERRIDE_FILE"; echo "override off — power actions will really run"
      ;;
    *)
      printf '%s\n' "$want" > "$OVERRIDE_FILE"
      echo "override on — power actions will run as: $want <action>"
      ;;
  esac
}

# ---------- state ----------

state_field() { # key default — pure bash, no fork
  local key="$1" default="${2:-}"
  [[ -f "$STATE_FILE" ]] || { echo "$default"; return; }
  local raw; raw=$(<"$STATE_FILE")
  if [[ $raw =~ \"$key\":\ *\"([^\"]*)\" ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ $raw =~ \"$key\":\ *(-?[0-9]+) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  echo "$default"
}

send_command() {
  printf '%s\n' "$1" > "$CONTROL_FILE"
  # Poke the daemon so an idle sleep ends immediately. Two details matter:
  #  - the newline, because the daemon's `read` returns on a full LINE;
  #  - opening the FIFO RDWR, because a plain `>` redirect BLOCKS while no
  #    reader exists (daemon restarting or dead) — `exec 3<>` never blocks.
  if [[ -p "$FIFO" ]]; then
    exec 3<>"$FIFO"
    printf '\n' >&3
    exec 3>&-
  fi
}

get_state() { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo '{"status":"IDLE"}'; }

# ---------- language ----------

CLI_LANG=""
resolve_cli_lang() {
  [[ -n "$CLI_LANG" ]] && return
  local configured="auto"
  if [[ -f "$SETTINGS_FILE" ]]; then
    local raw; raw=$(<"$SETTINGS_FILE")
    [[ $raw =~ \"language\":\ *\"([^\"]*)\" ]] && configured="${BASH_REMATCH[1]}"
  fi
  if [[ "$configured" == "auto" || "$configured" == "system" || -z "$configured" ]]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
      ru*|Russian*) configured="ru" ;;
      *)            configured="en" ;;
    esac
  fi
  CLI_LANG="$configured"
}

action_label() {
  resolve_cli_lang
  if [[ "$CLI_LANG" == "ru" ]]; then
    case "$1" in
      poweroff) echo "Выключить" ;; reboot) echo "Перезагрузить" ;;
      suspend) echo "Сон" ;; hibernate) echo "Гибернация" ;; lock) echo "Блокировка" ;;
      *) echo "$1" ;;
    esac
  else
    case "$1" in
      poweroff) echo "Power off" ;; reboot) echo "Reboot" ;;
      suspend) echo "Suspend" ;; hibernate) echo "Hibernate" ;; lock) echo "Lock" ;;
      *) echo "$1" ;;
    esac
  fi
}

in_minutes() {
  resolve_cli_lang
  if [[ "$CLI_LANG" == "ru" ]]; then echo "через $1 минут"; else echo "in $1 min"; fi
}

at_time() {
  resolve_cli_lang
  if [[ "$CLI_LANG" == "ru" ]]; then echo "в $1"; else echo "at $1"; fi
}

format_time() {
  local s=$1 h m sec
  h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
  if (( h > 0 )); then printf "%d:%02d:%02d" $h $m $sec; else printf "%02d:%02d" $m $sec; fi
}

# ---------- validation ----------

valid_action() { case "$1" in poweroff|reboot|suspend|hibernate|lock) return 0 ;; *) return 1 ;; esac; }

valid_time() { [[ "$1" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; }

# days spec: "daily" | "weekdays" | "weekends" | comma list 1-7 (1=Mon)
normalize_days() {
  case "${1,,}" in
    daily|everyday|all|ежедневно) echo "1,2,3,4,5,6,7" ;;
    weekdays|будни)               echo "1,2,3,4,5" ;;
    weekends|выходные)            echo "6,7" ;;
    *)
      local d out=""
      for d in ${1//,/ }; do
        [[ "$d" =~ ^[1-7]$ ]] || { echo ""; return 1; }
        out="${out:+$out,}$d"
      done
      echo "$out"
      ;;
  esac
}

days_label() { # 1,2,3 -> "Пн Ср" / "Mon Wed"
  resolve_cli_lang
  local d out="" names idx
  if [[ "$CLI_LANG" == "ru" ]]; then names=("${WEEKDAYS_RU[@]}"); else names=("${WEEKDAYS_EN[@]}"); fi
  for d in ${1//,/ }; do
    [[ "$d" =~ ^[1-7]$ ]] || continue
    idx=$((d - 1))
    out="${out:+$out }${names[$idx]}"
  done
  echo "$out"
}

# ---------- commands ----------

cmd_set() {
  local mins="${1:? set <mins>}" action="${2:-poweroff}"
  [[ "$mins" =~ ^[0-9]+$ ]] && (( mins >= 1 && mins <= 1440 )) || { echo "ERROR: mins must be 1..1440" >&2; exit 1; }
  valid_action "$action" || { echo "ERROR: action must be poweroff|reboot|suspend|hibernate|lock" >&2; exit 1; }
  ensure_daemon
  send_command "set:${mins}:${action}"
  echo "Timer set: $(action_label "$action") $(in_minutes "$mins")"
}

cmd_at() {
  local time="${1:? at <HH:MM>}" action="${2:-poweroff}"
  valid_time "$time" || { echo "ERROR: time must be HH:MM" >&2; exit 1; }
  valid_action "$action" || { echo "ERROR: bad action" >&2; exit 1; }
  ensure_daemon
  send_command "set-abs:${time}:${action}"
  echo "Timer set: $(action_label "$action") $(at_time "$time")"
}

cmd_cancel()    { ensure_daemon; send_command "cancel"; echo "Timer cancelled"; }
cmd_snooze()    { ensure_daemon; send_command "snooze:${1:-5}"; echo "Timer snoozed by ${1:-5} min"; }
cmd_pause()     { ensure_daemon; send_command "pause"; echo "Timer paused"; }
cmd_resume()    { ensure_daemon; send_command "resume"; echo "Timer resumed"; }
cmd_reset()     { ensure_daemon; send_command "reset"; echo "Timer reset"; }

cmd_status() {
  local json=false
  [[ "${1:-}" == "--json" ]] && json=true
  if $json; then get_state; return; fi
  local status action left target
  status=$(state_field status IDLE)
  action=$(state_field action "")
  left=$(state_field timeLeft 0)
  target=$(state_field targetTime 0)
  echo "Status: $status"
  echo "Action: $(action_label "${action:-none}")"
  if [[ "$status" != "IDLE" ]]; then
    echo "Time left: $(format_time "$left")"
    (( target > 0 )) && echo "Target: $(date -d "@$target" '+%H:%M:%S' 2>/dev/null || echo "-")"
    local sc; sc=$(state_field snoozeCount 0)
    (( sc > 0 )) && echo "Snoozed: $sc"
  fi
  local scount; scount=$(state_field scheduleCount 0)
  (( scount > 0 )) && echo "Schedules: $scount"
}

cmd_schedule() {
  local sub="${1:-list}"; shift || true
  case "$sub" in
    add)
      local time="${1:? schedule add <HH:MM> <days> [action]}" days="${2:? days}" action="${3:-poweroff}"
      valid_time "$time" || { echo "ERROR: time must be HH:MM" >&2; exit 1; }
      valid_action "$action" || { echo "ERROR: bad action" >&2; exit 1; }
      local norm; norm=$(normalize_days "$days") || { echo "ERROR: days must be daily|weekdays|weekends|1-7 list" >&2; exit 1; }
      [[ -n "$norm" ]] || { echo "ERROR: empty days" >&2; exit 1; }
      ensure_daemon
      local id; id=$(date +%s%N | tail -c 8)
      send_command "schedule-add:${id}:${time}:${norm}:${action}"
      sleep 0.3
      echo "Schedule added: #$id $(at_time "$time") $(days_label "$norm") — $(action_label "$action")"
      ;;
    list)
      [[ -f "$SCHEDULES_FILE" ]] || { echo "No schedules"; return; }
      local id time days action last
      while IFS=$'\t' read -r id time days action last; do
        [[ -n "$id" ]] || continue
        echo "#$id  $(at_time "$time")  $(days_label "$days")  $(action_label "$action")  (last: $last)"
      done < "$SCHEDULES_FILE"
      ;;
    remove)
      local id="${1:? schedule remove <id>}"; id="${id#\#}"
      ensure_daemon
      send_command "schedule-remove:${id}"
      sleep 0.3
      echo "Schedule #$id removed"
      ;;
    *) echo "Usage: $0 schedule {add <HH:MM> <days> [action]|list|remove <id>}" >&2; exit 1 ;;
  esac
}

cmd_history() {
  local json=false
  [[ "${1:-}" == "--json" ]] && json=true
  [[ -f "$HISTORY_FILE" ]] || { $json && echo '[]' || echo "No history"; return; }
  if $json; then
    printf '['
    local first=true ts outcome action
    while IFS=$'\t' read -r ts outcome action; do
      [[ -n "$ts" ]] || continue
      $first || printf ','
      first=false
      printf '{"ts":%s,"outcome":"%s","action":"%s"}' "$ts" "$outcome" "$action"
    done < "$HISTORY_FILE"
    printf ']\n'
    return
  fi
  local ts outcome action
  while IFS=$'\t' read -r ts outcome action; do
    [[ -n "$ts" ]] || continue
    printf '%s  %-10s %s\n' "$(date -d "@$ts" '+%m-%d %H:%M:%S' 2>/dev/null || echo "$ts")" "$outcome" "$(action_label "$action")"
  done < "$HISTORY_FILE"
}

# ---------- main ----------

main() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    ensure)      ensure_daemon ;;
    daemon-stop) daemon_stop ;;
    override)    cmd_override "${1:-status}" ;;
    send)        send_command "${1:? send <cmd>}" ;;
    get-state)   get_state ;;
    set)         cmd_set "$@" ;;
    set-abs|at)  cmd_at "$@" ;;
    cancel)      cmd_cancel ;;
    snooze)      cmd_snooze "${1:-5}" ;;
    pause)       cmd_pause ;;
    resume)      cmd_resume ;;
    reset)       cmd_reset ;;
    status)      cmd_status "${1:-}" ;;
    schedule)    cmd_schedule "$@" ;;
    history)     cmd_history "${1:-}" ;;
    *)
      sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 1
      ;;
  esac
}

main "$@"
