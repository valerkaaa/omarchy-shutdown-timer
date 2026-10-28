.pragma library

// ---------- localization ----------
//
// Omarchy itself ships no catalogue: each plugin carries its own strings. The
// dictionary below is keyed by a stable id, and `t(key, lang)` falls back to
// English and then to the key itself, so a missing translation shows up as a
// readable label rather than an empty field.
//
// `resolveLang` maps anything the settings or the environment can produce
// (ru_RU.UTF-8, ru-RU, Russian, en_US, ...) onto a supported code.

var SUPPORTED = ["en", "ru"]

var STRINGS = {
  en: {
    "plugin.title": "Shutdown timer",
    "state.none": "No timer set",
    "state.noneHint": "Pick a time below · right-click the icon cancels",
    "state.paused": "%1 — paused",
    "state.countdown": "%1 — counting down",
    "state.active": "%1 on a timer",
    "state.ready": "Ready to schedule",
    "action.poweroff": "Power off",
    "action.reboot": "Reboot",
    "action.suspend": "Suspend",
    "action.hibernate": "Hibernate",
    "section.action": "ACTION",
    "section.presets": "PRESETS",
    "section.exact": "EXACT TIME",
    "mode.relative": "In N minutes",
    "mode.absolute": "At HH:MM",
    "launch.enterTime": "Enter a time as HH:MM",
    "launch.at": "Start at %1",
    "launch.in": "Start in %1 min",
    "launch.reset": "Reset timer (start over)",
    "btn.cancel": "Cancel",
    "btn.snooze": "+5 minutes",
    "btn.pause": "Pause",
    "btn.resume": "Resume",
    "unit.min": "min",
    "unit.minShort": "m",
    "unit.hourShort": "h",
    "unit.secShort": "s",
    "time.in": "in",
    "error.badTime": "Enter the time as HH:MM",
    "overlay.cancel": "Cancel",
    "overlay.snooze": "+5 minutes",
    "overlay.hint": "Esc or the button cancels · Enter postpones",
    "overlay.action": "Power off",
    "notify.early": "%1 in %2",
    "notify.now": "%1 in %2",
    "notify.title": "Shutdown timer",
    "notify.system": "System",
    "tooltip.idle": "Shutdown timer · click for the menu, right-click to refresh",
    "tooltip.cancelHint": "right-click cancels",
    "tooltip.countdown": "Final countdown: %1 · right-click cancels",
    "state.scheduled": "%1 — scheduled",
    "section.repeat": "REPEAT",
    "section.advanced": "ADVANCED",
    "section.history": "HISTORY",
    "repeat.once": "Once",
    "repeat.daily": "Every day",
    "repeat.weekdays": "Weekdays",
    "repeat.weekends": "Weekends",
    "repeat.add": "Add schedule",
    "repeat.remove": "Remove",
    "repeat.none": "No schedules yet",
    "adv.battery": "Do not power off on battery",
    "adv.quiet": "Quiet mode (no notifications)",
    "adv.wait": "Wait for sleep/shutdown inhibitors",
    "adv.dnd": "Notifications are silenced",
    "adv.snoozeStep": "Snooze step",
    "history.empty": "No runs yet",
    "history.executed": "executed",
    "history.cancelled": "cancelled",
    "history.snoozed": "postponed",
    "history.set": "set",
    "history.scheduled": "by schedule",
    "week.1": "Mon",
    "week.2": "Tue",
    "week.3": "Wed",
    "week.4": "Thu",
    "week.5": "Fri",
    "week.6": "Sat",
    "week.7": "Sun",
    "reason.battery": "Battery guard: will suspend instead",
    "reason.inhibited": "Waiting for: %1",
  },
  ru: {
    "plugin.title": "Таймер выключения",
    "state.none": "Таймер не задан",
    "state.noneHint": "Выберите время ниже · ПКМ по иконке отменяет",
    "state.paused": "%1 — пауза",
    "state.countdown": "%1 — отсчёт",
    "state.active": "%1 по таймеру",
    "state.ready": "Готово к планированию",
    "action.poweroff": "Выключить",
    "action.reboot": "Перезагрузить",
    "action.suspend": "Сон",
    "action.hibernate": "Гибернация",
    "section.action": "ДЕЙСТВИЕ",
    "section.presets": "ПРЕСЕТЫ",
    "section.exact": "ТОЧНОЕ ВРЕМЯ",
    "mode.relative": "Через N минут",
    "mode.absolute": "В ЧЧ:ММ",
    "launch.enterTime": "Введите время ЧЧ:ММ",
    "launch.at": "Запустить в %1",
    "launch.in": "Запустить на %1 мин",
    "launch.reset": "Сбросить таймер (начать заново)",
    "btn.cancel": "Отмена",
    "btn.snooze": "+5 минут",
    "btn.pause": "Пауза",
    "btn.resume": "Продолжить",
    "unit.min": "мин",
    "unit.minShort": "м",
    "unit.hourShort": "ч",
    "unit.secShort": "с",
    "time.in": "через",
    "error.badTime": "Введите время в формате ЧЧ:ММ",
    "overlay.cancel": "Отмена",
    "overlay.snooze": "+5 минут",
    "overlay.hint": "Esc или кнопка — отменить · Enter — отложить",
    "overlay.action": "Выключение",
    "notify.early": "%1 через %2",
    "notify.now": "%1 через %2",
    "notify.title": "Таймер выключения",
    "notify.system": "Система",
    "tooltip.idle": "Таймер выключения · ЛКМ — меню, ПКМ — обновить",
    "tooltip.cancelHint": "ПКМ — отмена",
    "tooltip.countdown": "Финальный отсчёт: %1 · ПКМ — отмена",
    "state.scheduled": "%1 — по расписанию",
    "section.repeat": "ПОВТОР",
    "section.advanced": "ДОПОЛНИТЕЛЬНО",
    "section.history": "ИСТОРИЯ",
    "repeat.once": "Однократно",
    "repeat.daily": "Каждый день",
    "repeat.weekdays": "Будни",
    "repeat.weekends": "Выходные",
    "repeat.add": "Добавить расписание",
    "repeat.remove": "Удалить",
    "repeat.none": "Расписаний пока нет",
    "adv.battery": "Не выключать на батарее",
    "adv.quiet": "Тихий режим (без уведомлений)",
    "adv.wait": "Ждать завершения загрузок",
    "adv.dnd": "Уведомления заглушены",
    "adv.snoozeStep": "Шаг отложить",
    "history.empty": "Запусков пока нет",
    "history.executed": "выполнено",
    "history.cancelled": "отменено",
    "history.snoozed": "отложено",
    "history.set": "задан",
    "history.scheduled": "по расписанию",
    "week.1": "Пн",
    "week.2": "Вт",
    "week.3": "Ср",
    "week.4": "Чт",
    "week.5": "Пт",
    "week.6": "Сб",
    "week.7": "Вс",
    "reason.battery": "Режим батареи: будет сон вместо выключения",
    "reason.inhibited": "Ждём: %1"
  }
}

// "ru_RU.UTF-8" | "ru-RU" | "Russian" | "en_US" → "ru" | "en"
function resolveLang(value, fallback) {
  var fb = fallback === undefined ? "en" : String(fallback)
  var raw = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (raw === "") return fb
  if (raw === "auto" || raw === "system") return fb
  var head = raw.split(/[._@-]/)[0]
  if (head === "russian" || head === "русский") head = "ru"
  if (head === "english" || head === "английский") head = "en"
  if (SUPPORTED.indexOf(head) !== -1) return head
  // a bare "en"/"ru" that arrived as a longer tag was already handled; here the
  // tag is something we do not carry — fall back rather than showing keys
  for (var i = 0; i < SUPPORTED.length; i++) {
    if (raw.indexOf(SUPPORTED[i]) === 0) return SUPPORTED[i]
  }
  return fb
}

// key → localized text; %1..%9 are substituted from `args` (array or scalar)
function t(key, lang, args) {
  var code = resolveLang(lang, "en")
  var table = STRINGS[code] || STRINGS.en
  var text = table[key]
  if (text === undefined) text = STRINGS.en[key]
  if (text === undefined) return String(key)
  if (args === undefined || args === null) return text
  var list = (args instanceof Array) ? args : [args]
  for (var i = 0; i < list.length; i++) {
    text = text.replace("%" + (i + 1), String(list[i]))
  }
  return text
}

// ---------- pure formatting & null-safe access ----------

function field(obj, path, fallback) {
  if (obj === null || obj === undefined) return fallback
  var parts = String(path).split(".")
  var cur = obj
  for (var i = 0; i < parts.length; i++) {
    if (cur === null || cur === undefined) return fallback
    cur = cur[parts[i]]
  }
  return cur === null || cur === undefined ? fallback : cur
}

function known(value) {
  return typeof value === "number" && isFinite(value)
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// seconds → "12:34" or "1:23:45"
function formatTime(seconds) {
  if (!known(seconds) || seconds < 0) return "--:--"
  var s = Math.ceil(seconds)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  if (h > 0) {
    return h + ":" + String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0")
  }
  return String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0")
}

// seconds → human readable, short units per language ("1h 5m", "1ч 5м")
function formatTimeHuman(seconds, lang) {
  if (!known(seconds) || seconds < 0) return ""
  var s = Math.ceil(seconds)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var parts = []
  if (h > 0) parts.push(h + t("unit.hourShort", lang))
  if (m > 0) parts.push(m + t("unit.minShort", lang))
  parts.push(sec + t("unit.secShort", lang))
  return parts.join(" ")
}

// minutes → "5m" or "1h 30m"
function formatMinutes(minutes, lang) {
  if (!known(minutes) || minutes < 1) return ""
  if (minutes < 60) return String(minutes) + t("unit.minShort", lang)
  var h = Math.floor(minutes / 60)
  var m = minutes % 60
  return h + t("unit.hourShort", lang) + (m > 0 ? " " + m + t("unit.minShort", lang) : "")
}

// action key → localized name
function actionLabel(action, lang) {
  if (action === "poweroff") return t("action.poweroff", lang)
  if (action === "reboot") return t("action.reboot", lang)
  if (action === "suspend") return t("action.suspend", lang)
  if (action === "hibernate") return t("action.hibernate", lang)
  return action || "—"
}

// action key → Nerd Font glyph
function actionGlyph(action) {
  if (action === "reboot") return "\uf021"   // nf-fa-refresh
  if (action === "suspend") return "\uf186"  // nf-fa-moon_o
  if (action === "hibernate") return "\uf186"
  return "\uf011"                            // nf-fa-power_off
}

// state → color intent: "normal" | "warning" | "urgent"
function stateColor(status, timeLeft, overlaySeconds) {
  if (status === "COUNTDOWN") return "urgent"
  if (status === "ACTIVE") {
    if (timeLeft <= 60) return "urgent"
    if (timeLeft <= 300) return "warning"
    return "normal"
  }
  return "normal"
}

// ISO timestamp → "HH:MM"
function formatTimeOnly(timestamp) {
  if (!known(timestamp) || timestamp <= 0) return ""
  var d = new Date(timestamp * 1000)
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}

// ---------- contrast (TZ 12: text ≥ 4.5:1 on the theme surface) ----------
// Some themes pair a warm red with a warm light surface and land just under
// 4.5:1 (Flexoki Light: #D14D41 on #FFFCF0 is 4.21). Rather than hope, the
// text color is nudged toward black or white — whichever direction lifts the
// ratio — until it clears the bar.

function _srgb(c) {
  c = c / 255
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

function _hexToRgb(hex) {
  var h = String(hex).replace("#", "")
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  var n = parseInt(h, 16)
  if (isNaN(n)) return null
  return [ (n >> 16) & 255, (n >> 8) & 255, n & 255 ]
}

function _luminance(hex) {
  var rgb = _hexToRgb(hex)
  if (!rgb) return 0
  return 0.2126 * _srgb(rgb[0]) + 0.7152 * _srgb(rgb[1]) + 0.0722 * _srgb(rgb[2])
}

function contrastRatio(a, b) {
  var la = _luminance(a), lb = _luminance(b)
  var hi = Math.max(la, lb), lo = Math.min(la, lb)
  return (hi + 0.05) / (lo + 0.05)
}

function _mix(hexA, hexB, t) {
  var a = _hexToRgb(hexA), b = _hexToRgb(hexB)
  if (!a || !b) return hexA
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var v = Math.round(a[i] * (1 - t) + b[i] * t)
    out += (v < 16 ? "0" : "") + v.toString(16)
  }
  return out
}

// Returns `fg` itself when it already clears `minRatio` on `bg`; otherwise the
// nearest mix toward black/white that clears it, so urgency keeps its hue.
function readableOn(fg, bg, minRatio) {
  minRatio = minRatio || 4.5
  var target = String(fg)
  if (contrastRatio(target, String(bg)) >= minRatio) return target
  var toward = _luminance(String(bg)) > 0.5 ? "#000000" : "#ffffff"
  for (var t = 0.05; t <= 0.85; t += 0.05) {
    var candidate = _mix(target, toward, t)
    if (contrastRatio(candidate, String(bg)) >= minRatio) return candidate
  }
  return toward
}
