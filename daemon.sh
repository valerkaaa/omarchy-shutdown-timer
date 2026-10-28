#!/usr/bin/env bash
#
# daemon.sh — фоновый демон таймера выключения для Omarchy.
#
# Единственный источник правды о времени. UI (Panel.qml / Overlay.qml) только
# читает state.json и пишет команды в control; время сам не считает.
#
# Канал команд — файл control (совместимость и fallback прямой записью) плюс
# FIFO-пробуждение: short `control.sh` пишет файл и толкает FIFO, демон спит
# на `read -t` (bash builtin, без форков) и просыпается мгновенно. В IDLE без
# расписания демон просыпается раз в 10 минут, а не каждую секунду.
#
# Состояние: state.json (атомарная запись через mv). Переживает kill -9:
# при старте ACTIVE/PAUSED восстанавливается, а если время истекло в простое —
# показывается окно отсчёта, а не мгновенное выключение.
#
# ACTION_OVERRIDE=<cmd> подменяет системное действие (тесты: ACTION_OVERRIDE=echo).

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/plugins/shutdown-timer"
mkdir -p "$STATE_DIR"

STATE_FILE="$STATE_DIR/state.json"
HISTORY_FILE="$STATE_DIR/history.tsv"
SCHEDULES_FILE="$STATE_DIR/schedules.tsv"
CONTROL_FILE="$STATE_DIR/control"
FIFO="$STATE_DIR/wake"
PID_FILE="$STATE_DIR/daemon.pid"
LOCK_FILE="$STATE_DIR/daemon.lock"
LOG_FILE="$STATE_DIR/daemon.log"

OMARCHY_BIN="${OMARCHY_PATH:-/usr/share/omarchy}"
NOTIFY_SEND="${OMARCHY_BIN}/bin/omarchy-notification-send"
NOTIFICATIONS_STATE="$HOME/.local/state/omarchy/notifications.json"

ACTION_OVERRIDE="${ACTION_OVERRIDE:-}"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# ---------- single instance ----------

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "another instance holds the lock, exiting"
  exit 0
fi
echo $$ > "$PID_FILE"

# wake channel: read end must be RDWR so opening never blocks a writer
[[ -p "$FIFO" ]] || { rm -f "$FIFO"; mkfifo -m 600 "$FIFO"; }
exec 9<>"$FIFO"

# ---------- settings (re-read on every use — a setting can change live) ----------

ui_lang="en"
notify_early_secs=300
overlay_seconds=30
snooze_mins=5
snooze_limit=3
quiet=false

settings_field() {
  local key="$1" default="$2"
  [[ -f "$STATE_DIR/settings.json" ]] || { echo "$default"; return; }
  local raw
  raw=$(<"$STATE_DIR/settings.json")
  if [[ $raw =~ \"$key\":\ *\"([^\"]*)\" ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ $raw =~ \"$key\":\ *(-?[0-9]+) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ $raw =~ \"$key\":\ *(true|false) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  echo "$default"
}

resolve_lang() {
  local configured
  configured=$(settings_field language auto)
  if [[ "$configured" == "auto" || "$configured" == "system" || -z "$configured" ]]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
      ru*|Russian*) ui_lang="ru" ;;
      *)            ui_lang="en" ;;
    esac
  else
    ui_lang="$configured"
  fi
}

reload_settings() {
  notify_early_secs=$(( $(settings_field notifyEarlyMins 5) * 60 ))
  overlay_seconds=$(settings_field overlaySeconds 30)
  snooze_mins=$(settings_field snoozeMins 5)
  snooze_limit=$(settings_field snoozeLimit 3)
  quiet=$(settings_field quiet false)
  resolve_lang
}

# ---------- localization (mirrors Model.js) ----------

format_time() {
  local s=$1 h m sec
  h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
  if (( h > 0 )); then printf "%d:%02d:%02d" $h $m $sec
  else printf "%02d:%02d" $m $sec; fi
}

format_time_human() {
  local s=$1 h m sec parts="" hu mu su
  h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
  if [[ "$ui_lang" == "ru" ]]; then hu="ч"; mu="м"; su="с"; else hu="h"; mu="m"; su="s"; fi
  (( h > 0 )) && parts="${h}${hu} "
  (( m > 0 )) && parts="${parts}${m}${mu} "
  printf '%s%s' "$parts" "${sec}${su}"
}

action_label() {
  if [[ "$ui_lang" == "ru" ]]; then
    case "$1" in
      poweroff) echo "Выключить" ;; reboot) echo "Перезагрузить" ;;
      suspend) echo "Сон" ;; hibernate) echo "Гибернация" ;; *) echo "$1" ;;
    esac
  else
    case "$1" in
      poweroff) echo "Power off" ;; reboot) echo "Reboot" ;;
      suspend) echo "Suspend" ;; hibernate) echo "Hibernate" ;; *) echo "$1" ;;
    esac
  fi
}

notify_title() { if [[ "$ui_lang" == "ru" ]]; then echo "Система"; else echo "System"; fi; }
notify_in()    { if [[ "$ui_lang" == "ru" ]]; then echo "через";   else echo "in";     fi; }

# ---------- state: pure-bash read/write, atomic ----------

status="IDLE"; action=""; time_left=0; target_time=0
mode=""; start_time=0; snooze_count=0; reason=""

read_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  local raw
  raw=$(<"$STATE_FILE")
  [[ $raw =~ \"status\":\ *\"([A-Z_]+)\" ]]     && status="${BASH_REMATCH[1]}"     || status="IDLE"
  [[ $raw =~ \"action\":\ *\"([a-z]*)\" ]]      && action="${BASH_REMATCH[1]}"     || action=""
  [[ $raw =~ \"timeLeft\":\ *(-?[0-9]+) ]]      && time_left="${BASH_REMATCH[1]}"  || time_left=0
  [[ $raw =~ \"targetTime\":\ *(-?[0-9]+) ]]    && target_time="${BASH_REMATCH[1]}" || target_time=0
  [[ $raw =~ \"mode\":\ *\"([a-z]*)\" ]]        && mode="${BASH_REMATCH[1]}"       || mode=""
  [[ $raw =~ \"startTime\":\ *(-?[0-9]+) ]]     && start_time="${BASH_REMATCH[1]}" || start_time=0
  [[ $raw =~ \"snoozeCount\":\ *(-?[0-9]+) ]]   && snooze_count="${BASH_REMATCH[1]}" || snooze_count=0
  [[ $raw =~ \"reason\":\ *\"([^\"]*)\" ]]      && reason="${BASH_REMATCH[1]}"     || reason=""
}

state_line=""
write_state() {
  local line
  schedule_count          # sets SCHEDULE_N (no subshell)
  dnd_state               # sets DND_STATE
  printf -v line '{"status":"%s","action":"%s","timeLeft":%d,"targetTime":%d,"mode":"%s","startTime":%d,"snoozeCount":%d,"reason":"%s","scheduleCount":%d,"dnd":%s,"pid":%d}' \
    "$status" "$action" "$time_left" "$target_time" "$mode" "$start_time" "$snooze_count" "$reason" \
    "$SCHEDULE_N" "$DND_STATE" "$$"
  [[ "$line" == "$state_line" && -f "$STATE_FILE" ]] && return 0
  state_line="$line"
  printf '%s\n' "$line" > "$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

set_state() {
  status="$1"; action="$2"; time_left="$3"; target_time="$4"
  mode="$5"; start_time="$6"; snooze_count="${7:-0}"; reason="${8:-}"
  write_state
}

# ---------- history ----------

append_history() { # outcome action
  printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" >> "$HISTORY_FILE"
  tail -n 50 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" 2>/dev/null && mv -f "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# ---------- schedules ----------
# schedules.tsv: id<TAB>HH:MM<TAB>days (1-7, comma)<TAB>action<TAB>lastFired YYYY-MM-DD

schedule_count() {
  [[ -f "$SCHEDULES_FILE" ]] || { SCHEDULE_N=0; return 0; }
  local n=0 line
  while IFS= read -r line; do [[ -n "$line" ]] && n=$((n + 1)); done < "$SCHEDULES_FILE"
  SCHEDULE_N=$n
}

days_match() { # days-spec ; true if today matches
  local spec="$1" today
  today=$(date +%u)   # 1=Mon .. 7=Sun
  local d
  for d in ${spec//,/ }; do [[ "$d" == "$today" ]] && return 0; done
  return 1
}

check_schedules() {
  [[ -f "$SCHEDULES_FILE" ]] || return 0
  [[ "$status" == "IDLE" ]] || return 0
  local now_hm today line id hm days act last fired_any=false
  now_hm=$(date +%H:%M); today=$(date +%F)
  while IFS=$'\t' read -r id hm days act last; do
    [[ -n "$id" ]] || continue
    [[ "$hm" == "$now_hm" ]] || continue
    [[ "$last" == "$today" ]] && continue
    days_match "$days" || continue
    fired_any=true
    # mark fired first (atomic-enough: single rewrite below)
    awk -F'\t' -v id="$id" -v today="$today" 'BEGIN{OFS="\t"} $1==id{$5=today} {print}' \
      "$SCHEDULES_FILE" > "$SCHEDULES_FILE.tmp" && mv -f "$SCHEDULES_FILE.tmp" "$SCHEDULES_FILE"
    now=$EPOCHSECONDS
    set_state "COUNTDOWN_SCHED" "$act" "$overlay_seconds" "$((now + overlay_seconds))" "schedule" "$now" 0 ""
    append_history "scheduled" "$act"
    log "schedule $id fired ($hm $days $act)"
    break
  done < "$SCHEDULES_FILE"
  $fired_any && return 0
  return 0
}

# ---------- conditions (TZ 9.4) ----------

dnd_state() {
  DND_STATE=false
  [[ -f "$NOTIFICATIONS_STATE" ]] || return 0
  local raw; raw=$(<"$NOTIFICATIONS_STATE")
  [[ $raw =~ \"dnd\":\ *true ]] && DND_STATE=true
}

battery_guard_should_swap() { # action → prints "suspend" if guard flips it
  [[ "$(settings_field batteryGuard false)" == "true" ]] || { echo "$1"; return; }
  local bat="/sys/class/power_supply/BAT0"
  [[ -d "$bat" ]] || { echo "$1"; return; }
  local st cap thresh
  st=$(<"$bat/status"); cap=$(<"$bat/capacity")
  thresh=$(settings_field batteryThreshold 20)
  if [[ "$st" == "Discharging" && "$cap" -lt "$thresh" && "$1" == "poweroff" ]]; then
    echo "suspend"
  else
    echo "$1"
  fi
}

inhibitors_holding() { # prints reason if another process blocks sleep:shutdown
  [[ "$(settings_field waitForInhibitors false)" == "true" ]] || return 1
  command -v systemd-inhibit >/dev/null || return 1
  local line
  while IFS= read -r line; do
    [[ "$line" == *"sleep:shutdown"* || "$line" == *"shutdown:sleep"* ]] || continue
    [[ "$line" == *"daemon.sh"* ]] && continue
    [[ "$line" == *"shutdown-timer"* ]] && continue
    printf '%s' "$(echo "$line" | awk -F'  +' '{print $3}' | cut -c1-60)"
    return 0
  done < <(systemd-inhibit --list --no-pager 2>/dev/null)
  return 1
}

# ---------- notification / action ----------

send_notification() { # urgency title body
  [[ "$quiet" == "true" ]] && return 0
  [[ "$(dnd_state)" == "true" && "$1" != "critical" ]] && return 0
  if [[ -x "$NOTIFY_SEND" ]]; then
    "$NOTIFY_SEND" -u "$1" "$2" "$3" >>"$LOG_FILE" 2>&1 || true
  elif command -v notify-send >/dev/null; then
    notify-send -u "$1" "$2" "$3" >>"$LOG_FILE" 2>&1 || true
  fi
}

do_action() {
  local act="$1"
  if [[ -n "$ACTION_OVERRIDE" ]]; then
    $ACTION_OVERRIDE "$act" >>"$LOG_FILE" 2>&1 || true
    return 0
  fi
  case "$act" in
    poweroff)  omarchy system shutdown 2>/dev/null || systemctl poweroff ;;
    reboot)    omarchy system reboot   2>/dev/null || systemctl reboot ;;
    suspend)   systemctl suspend 2>/dev/null || omarchy system suspend 2>/dev/null || true ;;
    hibernate) systemctl hibernate 2>/dev/null || omarchy system hibernate 2>/dev/null || true ;;
    lock)      omarchy system lock 2>/dev/null || omarchy-lock-screen 2>/dev/null || true ;;
  esac
}

summon_overlay() {
  if command -v omarchy-shell >/dev/null; then
    omarchy-shell honor.shutdown-timer:overlay show >>"$LOG_FILE" 2>&1 || true
  fi
}

close_overlay() {
  if command -v omarchy-shell >/dev/null; then
    omarchy-shell honor.shutdown-timer:overlay hide >>"$LOG_FILE" 2>&1 || true
  fi
}

# ---------- commands ----------

announced_early=false
announced_countdown=false

arm_timer() { # seconds action mode snoozeCount
  local secs="$1" act="$2" m="$3" sc="${4:-0}"
  local now; now=$EPOCHSECONDS
  set_state "ACTIVE" "$act" "$secs" "$((now + secs))" "$m" "$now" "$sc" ""
  announced_early=false; announced_countdown=false
}

process_command() {
  local cmd="$1"
  read_state
  case "$cmd" in
    set:*)
      local rest="${cmd#set:}"
      local mins="${rest%%:*}" act="${rest#*:}"
      [[ "$act" == "$rest" ]] && act="poweroff"
      arm_timer $((mins * 60)) "$act" "relative" 0
      append_history "set" "$act"
      ;;
    set-abs:*)
      # HH:MM carries its own colon, so split in two steps: the time is the
      # first two fields, everything after is the action.
      local rest="${cmd#set-abs:}"
      local hh="${rest%%:*}"
      rest="${rest#*:}"
      local mm="${rest%%:*}"
      local hm="${hh}:${mm}"
      local act="${rest#*:}"
      [[ "$act" == "$mm" || -z "$act" ]] && act="poweroff"
      local now target
      now=$EPOCHSECONDS
      target=$(date -d "today $hm" +%s 2>/dev/null || echo $((now + 3600)))
      (( target <= now )) && target=$((target + 86400))
      arm_timer $((target - now)) "$act" "absolute" 0
      append_history "set-at" "$act"
      ;;
    cancel)
      read_state
      [[ "$status" == "IDLE" ]] || append_history "cancelled" "$action"
      set_state "IDLE" "" 0 0 "" 0 0 ""
      announced_early=false; announced_countdown=false
      close_overlay
      ;;
    reset)
      read_state
      local now orig
      now=$EPOCHSECONDS
      if [[ "$mode" == "absolute" ]]; then orig=$time_left; else orig=$((target_time - start_time)); fi
      (( orig <= 0 )) && orig=1800
      arm_timer "$orig" "${action:-poweroff}" "${mode:-relative}" 0
      append_history "reset" "${action:-poweroff}"
      ;;
    snooze:*)
      read_state
      local mins="${cmd#snooze:}"
      if [[ "$status" == "ACTIVE" || "$status" == "COUNTDOWN" || "$status" == "COUNTDOWN_SCHED" ]]; then
        if (( snooze_count >= snooze_limit )); then log "snooze refused (limit $snooze_limit)"; return 0; fi
        local now new_target new_left
        now=$EPOCHSECONDS
        new_target=$((target_time + mins * 60))
        new_left=$((new_target - now))
        set_state "ACTIVE" "$action" "$new_left" "$new_target" "$mode" "$start_time" "$((snooze_count + 1))" ""
        announced_early=false; announced_countdown=false
        append_history "snoozed" "$action"
        close_overlay
      fi
      ;;
    pause)
      read_state
      if [[ "$status" == "ACTIVE" || "$status" == "COUNTDOWN" || "$status" == "COUNTDOWN_SCHED" ]]; then
        local now frozen
        now=$EPOCHSECONDS
        frozen=$((target_time - now)); (( frozen < 0 )) && frozen=0
        set_state "PAUSED" "$action" "$frozen" 0 "" "$start_time" "$snooze_count" ""
        close_overlay
      fi
      ;;
    resume)
      read_state
      if [[ "$status" == "PAUSED" ]]; then
        local now; now=$EPOCHSECONDS
        set_state "ACTIVE" "$action" "$time_left" "$((now + time_left))" "$mode" "$now" "$snooze_count" ""
        announced_early=false; announced_countdown=false
      fi
      ;;
    schedule-add:*)
      # schedule-add:ID:HH:MM:DAYS:ACTION — HH:MM carries a colon of its own,
      # so the time is consumed as two fields before the rest.
      local rest="${cmd#schedule-add:}"
      local id="${rest%%:*}"
      rest="${rest#*:}"
      local hh="${rest%%:*}"
      rest="${rest#*:}"
      local mm="${rest%%:*}"
      rest="${rest#*:}"
      local days="${rest%%:*}"
      local act="${rest#*:}"
      local hm="${hh}:${mm}"
      [[ -z "$act" || "$act" == "$days" ]] && act="poweroff"
      printf '%s\t%s\t%s\t%s\t-\n' "$id" "$hm" "$days" "$act" >> "$SCHEDULES_FILE"
      log "schedule added: $id $hm $days $act"
      ;;
    schedule-remove:*)
      local id="${cmd#schedule-remove:}"
      if [[ -f "$SCHEDULES_FILE" ]]; then
        # $'	' is a real tab; "^$id	" in basic grep would match the letter t
        grep -v "^$id"$'	' "$SCHEDULES_FILE" > "$SCHEDULES_FILE.tmp" || true
        mv -f "$SCHEDULES_FILE.tmp" "$SCHEDULES_FILE"
      fi
      log "schedule removed: $id"
      ;;
    ping) : ;;
    *) log "unknown command: $cmd" ;;
  esac
}

drain_control() {
  [[ -f "$CONTROL_FILE" ]] || return 0
  local cmd
  while IFS= read -r cmd; do
    cmd="${cmd%$'\r'}"
    [[ -n "$cmd" ]] && process_command "$cmd"
  done < "$CONTROL_FILE"
  rm -f "$CONTROL_FILE"
}

# ---------- startup ----------

reload_settings
read_state
log "daemon start (pid $$, status=$status)"

now=$EPOCHSECONDS
case "$status" in
  ACTIVE)
    if (( target_time > now )); then
      log "restored ACTIVE, $((target_time - now))s left"
    else
      # the deadline passed while the shell/machine was away: give a visible
      # window instead of firing instantly
      set_state "COUNTDOWN" "$action" "$overlay_seconds" "$((now + overlay_seconds))" "$mode" "$now" "$snooze_count" ""
      announced_early=true; announced_countdown=true
      summon_overlay
      log "restored overdue ACTIVE as COUNTDOWN (${overlay_seconds}s window)"
    fi
    ;;
  PAUSED|COUNTDOWN|COUNTDOWN_SCHED)
    log "restored $status"
    ;;
  *) set_state "IDLE" "" 0 0 "" 0 0 "" ;;
esac

cleanup() {
  read_state
  if [[ "$status" == "IDLE" ]]; then
    set_state "IDLE" "" 0 0 "" 0 0 ""
  fi
  rm -f "$PID_FILE"
  log "daemon exit (state kept: $status)"
}
trap cleanup EXIT
# INT/TERM must EXIT: with `trap cleanup INT TERM` alone the handler runs and
# the main loop simply continues, so the process never dies on a plain kill.
trap 'exit 0' INT TERM

drain_control

# ---------- main loop ----------

while true; do
  reload_settings
  read_state

  # decide how long to sleep: to the next second while a timer runs, long in IDLE
  timeout=0.2
  if [[ "$status" == "ACTIVE" || "$status" == "COUNTDOWN" || "$status" == "COUNTDOWN_SCHED" ]]; then
    # EPOCHREALTIME is a builtin (no fork); its separator follows the locale,
    # so strip '.' or ',' and take the milliseconds.
    frac="${EPOCHREALTIME#*[.,]}"
    ms_total=$((1020 - 10#${frac:0:3}))
    if (( ms_total >= 1000 )); then
      printf -v timeout '1.%03d' $((ms_total - 1000))
    else
      printf -v timeout '0.%03d' "$ms_total"
    fi
  else
    schedule_count
    if (( SCHEDULE_N > 0 )); then timeout=30; else timeout=600; fi
  fi

  # wait for a poke or the timeout; `read -t` is a builtin (no fork per tick)
  read -t "$timeout" -u 9 _poke || true
  drain_control
  read_state

  case "$status" in
    ACTIVE)
      now=$EPOCHSECONDS
      time_left=$((target_time - now))
      if (( time_left <= 0 )); then
        # conditions (TZ 9.4) — checked once, right before acting
        local_action=$(battery_guard_should_swap "$action")
        if [[ "$local_action" != "$action" ]]; then
          reason="battery"
          log "battery guard: $action -> $local_action"
        fi
        if held=$(inhibitors_holding); then
          reason="inhibited: $held"
          if (( ${held_since:-0} == 0 )); then held_since=$now; fi
          if (( now - held_since < 600 )); then
            write_state
            continue
          fi
          log "inhibitor waited 10 min, acting anyway"
        else
          held_since=0
        fi
        append_history "executed" "$local_action"
        log "firing $local_action"
        do_action "$local_action"
        set_state "IDLE" "$local_action" 0 "$target_time" "" 0 0 ""
      elif (( time_left <= overlay_seconds )); then
        status="COUNTDOWN"
        write_state
        summon_overlay
        if [[ "$announced_countdown" != "true" ]]; then
          send_notification "critical" "$(notify_title)" "$(action_label "$action") $(notify_in) $(format_time "$time_left")"
          announced_countdown=true
        fi
      else
        if (( time_left <= notify_early_secs )) && [[ "$announced_early" != "true" ]]; then
          send_notification "normal" "$(notify_title)" "$(action_label "$action") $(notify_in) $(format_time_human "$time_left")"
          announced_early=true
        fi
        write_state
      fi
      ;;
    COUNTDOWN|COUNTDOWN_SCHED)
      now=$EPOCHSECONDS
      time_left=$((target_time - now))
      (( time_left < 0 )) && time_left=0
      if (( time_left <= 0 )); then
        local_action=$(battery_guard_should_swap "$action")
        append_history "executed" "$local_action"
        log "firing $local_action (from $status)"
        do_action "$local_action"
        set_state "IDLE" "$local_action" 0 "$target_time" "" 0 0 ""
      else
        write_state
      fi
      ;;
    IDLE)
      check_schedules
      write_state
      ;;
  esac
done
