#!/usr/bin/env bash
# Regenerate the README screenshots from the live shell — nothing here is a
# mock, every file is a grim capture of the real widget.
#
#   assets/screenshots/<theme>/1..5-*.png     the bar states, from the widget slot
#   assets/screenshots/<theme>/6-popup.png    the popup window
#   assets/screenshots/<theme>/7-overlay.png  the full-screen countdown
#   assets/screenshots/<theme>/8-vertical.png the widget on a vertical bar
#   assets/screenshots/states.gif             the states, animated
#
# Usage:  bash tools/screenshots.sh                  # everything, both themes
#         bash tools/screenshots.sh dark             # one theme
#         bash tools/screenshots.sh dark popup bar   # one theme, some surfaces
#
# Needs the plugin enabled in the running shell, plus grim, ImageMagick and
# python3. Same machine gotchas as any screenshot: the theme is switched live,
# so do not fight the desktop while it runs. The starting theme is restored at
# the end.
set -euo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN"
OUT="$PLUGIN/assets/screenshots"
CTL=(bash control.sh)
BBOX=(python3 "$PLUGIN/tools/card_bbox.py")
WORK="$(mktemp -d /tmp/shots.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

START_THEME="$(omarchy theme current)"

# The bar strip: 42 logical px of gutter left of the mark, label room right.
BAR_X=919
BAR_W=128

# One capture, one crop: the bbox and the pixels it describes must come from the
# SAME frame. Two captures (one to measure, one to cut) drift by a few pixels —
# the popup re-lays itself out while the shot is taken — and `grim -g` would
# additionally need the bbox converted from device to logical space. A plain
# `grim` writes device pixels, card_bbox.py measures those pixels, and ImageMagick
# cuts them, so nothing has to be converted.
SCALE=$(hyprctl -j monitors 2>/dev/null | python3 -c "
import json,sys
print(max(m['scale'] for m in json.load(sys.stdin)))") || SCALE=1
logical_px() { awk -v v="$1" -v s="$SCALE" 'BEGIN { printf "%d", v * s }'; }
widget_geometry() { # -> "x y w h" (logical)
  omarchy-shell shell debugBarGeometry 2>/dev/null | python3 -c "
import sys,json
for it in json.load(sys.stdin):
    if 'shutdown' in it.get('id',''):
        print(it['x'], it['y'], it['width'], it['height']); break"
}
bar_height() { set -- $(widget_geometry); echo "$4"; }

# A busy desktop must not confuse the card scan: it keys on the card's own
# frame, and the crop is padded so the card sits inside the picture. The margin
# is in logical px; the batch is upscaled to the committed size afterwards.
card_crop() { # png outfile margin
  local png="$1" out="$2" margin="$3" box x y w h m
  box="$("${BBOX[@]}" "$png")"; read -r x y w h <<<"$box"
  if (( w <= 0 )); then echo "0 0 0 0"; return 1; fi
  m=$(logical_px "$margin")
  magick "$png" -crop "$((w+2*m))x$((h+2*m))+$((x-m))+$((y-m))" +repage "$out"
  # The crop can come out the right size and still show the desktop: a capture
  # in the wrong coordinate space does exactly that. Only a real card puts its
  # frame where the margin says, so the check is what makes this trustworthy.
  if ! msg=$(python3 "$PLUGIN/tools/frame_check.py" "$out" "$m" "$w" "$h"); then
    echo "crop is not the card ($msg)"
    return 2
  fi
  echo "card ${w}x${h} px"
}

# ---------- surfaces ----------

bar_states() { # theme
  local theme="$1"
  mkdir -p "$OUT/$theme"
  "${CTL[@]}" cancel >/dev/null 2>&1 || true
  sleep 1

  state() { # name
    grim -g "$BAR_X,0 ${BAR_W}x$(bar_height)" "$WORK/bar.png"
    magick "$WORK/bar.png" -filter point -resize '512x160!' "$OUT/$theme/$1.png"
    echo "    $theme/$1.png"
  }

  state 1-idle
  "${CTL[@]}" set 30 poweroff >/dev/null 2>&1; sleep 2; state 2-active
  "${CTL[@]}" set 4  poweroff >/dev/null 2>&1; sleep 2; state 3-warning
  "${CTL[@]}" pause           >/dev/null 2>&1; sleep 2; state 4-paused
  # the urgent variant exists only while the status is COUNTDOWN, i.e. inside
  # the last overlaySeconds — wait for the daemon to say so, not for a guess
  "${CTL[@]}" set 1 poweroff >/dev/null 2>&1
  for _ in $(seq 1 90); do
    [[ "$(omarchy-shell honor.shutdown-timer status 2>/dev/null | cut -d' ' -f1)" == "COUNTDOWN" ]] && break
    sleep 1
  done
  state 5-countdown
  "${CTL[@]}" cancel >/dev/null 2>&1 || true
  sleep 1
}

popup_shot() { # theme
  local theme="$1" info rc attempt
  mkdir -p "$OUT/$theme"
  for attempt in 1 2; do
    "${CTL[@]}" set 30 poweroff >/dev/null 2>&1; sleep 1
    omarchy-shell honor.shutdown-timer open >/dev/null 2>&1
    sleep 2
    grim "$WORK/full.png"
    omarchy-shell honor.shutdown-timer close >/dev/null 2>&1 || true
    rc=0; info=$(card_crop "$WORK/full.png" "$WORK/popup.png" 24) || rc=$?
    (( rc == 0 )) && break
    echo "    retry: $info"
  done
  if (( rc != 0 )); then
    echo "    $theme/6-popup.png (no card found, skipped)"; return 0
  fi
  # commit at ~1.75x logical so the text is readable in the README table
  local w; w=$(magick identify -format %w "$WORK/popup.png")
  magick "$WORK/popup.png" -filter point -resize "$(python3 -c "print(round($w/1.25*1.75))")x" \
        "$OUT/$theme/6-popup.png"
  echo "    $theme/6-popup.png ($info)"
}

overlay_shot() { # theme
  local theme="$1" info rc attempt
  mkdir -p "$OUT/$theme"
  for attempt in 1 2; do
    "${CTL[@]}" set 1 poweroff >/dev/null 2>&1
    for _ in $(seq 1 90); do
      [[ "$(omarchy-shell honor.shutdown-timer status 2>/dev/null | cut -d' ' -f1)" == "COUNTDOWN" ]] && break
      sleep 1
    done
    sleep 1
    grim "$WORK/full.png"
    "${CTL[@]}" cancel >/dev/null 2>&1 || true
    sleep 1
    rc=0; info=$(card_crop "$WORK/full.png" "$WORK/overlay.png" 40) || rc=$?
    (( rc == 0 )) && break
    echo "    retry: $info"
  done
  if (( rc != 0 )); then
    echo "    $theme/7-overlay.png (no card found, skipped)"; return 0
  fi
  local w; w=$(magick identify -format %w "$WORK/overlay.png")
  magick "$WORK/overlay.png" -filter point -resize "$(python3 -c "print(round($w/1.25*1.5))")x" \
        "$OUT/$theme/7-overlay.png"
  echo "    $theme/7-overlay.png ($info)"
}

vertical_shot() { # theme
  local theme="$1"
  mkdir -p "$OUT/$theme"
  omarchy bar position left >/dev/null 2>&1; sleep 6
  local x y w h; read -r x y w h <<<"$(widget_geometry)"
  grim -g "0,$((y-60)) $((w+16))x$((h+150))" "$WORK/vert.png"
  omarchy bar position top >/dev/null 2>&1; sleep 6
  magick "$WORK/vert.png" -filter point -resize '336x448!' "$OUT/$theme/8-vertical.png"
  echo "    $theme/8-vertical.png"
}

# ---------- main ----------

THEMES=(); SURFACES=()
for a in "$@"; do
  case "$a" in
    dark|light) THEMES+=("$a") ;;
    bar|popup|overlay|vertical) SURFACES+=("$a") ;;
    *) echo "usage: $0 [dark|light] [bar|popup|overlay|vertical]" >&2; exit 1 ;;
  esac
done
((${#THEMES[@]})) || THEMES=(dark light)
((${#SURFACES[@]})) || SURFACES=(bar popup overlay vertical)

for t in "${THEMES[@]}"; do
  case "$t" in
    dark)  theme=ristretto ;;
    light) theme=flexoki-light ;;
  esac
  echo "== $t ($theme) =="
  omarchy theme set "$theme" >/dev/null 2>&1
  sleep 6
  for s in "${SURFACES[@]}"; do
    case "$s" in
      bar)      bar_states "$t" ;;
      popup)    popup_shot "$t" ;;
      overlay)  overlay_shot "$t" ;;
      vertical) vertical_shot "$t" ;;
    esac
  done
done

# the animated GIF is built from the dark states (same framing as the table)
if [[ " ${SURFACES[*]} " == *" bar "* ]]; then
  magick "$OUT/dark/1-idle.png" "$OUT/dark/2-active.png" "$OUT/dark/3-warning.png" \
         "$OUT/dark/4-paused.png" "$OUT/dark/5-countdown.png" "$OUT/dark/1-idle.png" \
         -delay 90 -loop 0 -layers Optimize "$OUT/states.gif"
  echo "    states.gif"
fi

omarchy theme set "$START_THEME" >/dev/null 2>&1
sleep 3
echo "done; theme restored to $(omarchy theme current)"
