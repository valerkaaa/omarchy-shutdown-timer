#!/usr/bin/env bash
# Is this screenshot a card on a background, or a flat rectangle?
#
# The card's centre (its surface) must differ from what is behind its corners.
# A frame check would need the exact crop margin, and a rounded card has no
# straight line there, so this compares the centre against all four corners
# and takes the strongest difference.
#
# ImageMagick, not Pillow: the test suite must not depend on a Python package
# the host may or may not have. Prints the measured delta, exits 0 above the
# floor.
set -uo pipefail

img="${1:?usage: card_check.sh <png>}"
floor=10

[[ -f "$img" ]] || { echo "$img: missing"; exit 1; }
command -v magick >/dev/null || { echo "magick missing"; exit 2; }

read -r w h < <(magick identify -format "%w %h" "$img")
if (( w < 500 || h < 300 )); then
  echo "$img: too small (${w}x${h})"
  exit 1
fi

# Mean grey (0..255) of a crop, box-filtered so a single hot pixel cannot
# decide the verdict.
mean() {
  local cw=$1 ch=$2 cx=$3 cy=$4
  magick "$img" -crop "${cw}x${ch}+${cx}+${cy}" +repage -resize 8x8\! \
    -colorspace Gray -format "%[fx:mean*255]" info:
}

cw=$(( w / 12 )); ch=$(( h / 12 ))
bx=$(( w / 8 ));  by=$(( h / 8 ))

centre=$(mean $(( 2 * bx )) $(( 2 * by )) $(( w / 2 - bx )) $(( h / 2 - by )))
tl=$(mean "$cw" "$ch" 0 0)
tr=$(mean "$cw" "$ch" $(( w - cw )) 0)
bl=$(mean "$cw" "$ch" 0 $(( h - ch )))
br=$(mean "$cw" "$ch" $(( w - cw )) $(( h - ch )))

delta=$(awk -v c="$centre" -v a="$tl" -v b="$tr" -v d="$bl" -v e="$br" 'BEGIN{
  m = (a > c ? a - c : c - a)
  x = (b > c ? b - c : c - b); if (x > m) m = x
  x = (d > c ? d - c : c - d); if (x > m) m = x
  x = (e > c ? e - c : c - e); if (x > m) m = x
  printf "%.1f", m }')

echo "$img: centre ${centre} vs corners ${tl}/${tr}/${bl}/${br}, delta ${delta} (floor ${floor})"

awk -v d="$delta" -v f="$floor" 'BEGIN{ exit (d > f ? 0 : 1) }'
