#!/usr/bin/env python3
"""Regenerate the four plugin-store icons.

Dark and light variants, disc and squircle. Geometry is shared, only the
gradient changes, so a shape edit cannot drift between the four files.

The corner radius is deliberately large (a squircle, 30 % of the tile): the
plugin tiles in the store render at ~48 px and a 40/448 corner reads as a
nearly square tile there. The power mark is a stroked ring + stem with round
caps — the same soft corners the bar mark uses, at 512 px.
"""
import math
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"

# brighter than the first cut: at 48 px on a dark bar a #0b5f75 start reads
# navy-black instead of teal
RAMPS = {
    "dark": ("#2ee6cf", "#1f7ae0", "#16307a"),
    "light": ("#0fd1c0", "#1b74d6", "#1a2f7a"),
}

TILE = 512
INSET = 24          # breathing room around the tile
SIDE = TILE - INSET * 2
RADIUS_ROUND = 142  # squircle corner, 30 % of the side
RADIUS_DISC = SIDE / 2

RING_R = 116
STROKE = 30


def tile(shape: str) -> str:
    if shape == "disc":
        r = RADIUS_DISC
        return (f'<circle cx="{TILE/2}" cy="{TILE/2}" r="{r}" fill="url(#face)"/>'
                f'<circle cx="{TILE/2}" cy="{TILE/2}" r="{r}" fill="none" '
                f'stroke="#ffffff" stroke-opacity="0.28" stroke-width="3"/>')
    return (f'<rect x="{INSET}" y="{INSET}" width="{SIDE}" height="{SIDE}" '
            f'rx="{RADIUS_ROUND}" ry="{RADIUS_ROUND}" fill="url(#face)"/>'
            f'<rect x="{INSET}" y="{INSET}" width="{SIDE}" height="{SIDE}" '
            f'rx="{RADIUS_ROUND}" ry="{RADIUS_ROUND}" fill="none" '
            f'stroke="#ffffff" stroke-opacity="0.28" stroke-width="3"/>')


def svg(variant: str, shape: str) -> str:
    a, b, c = RAMPS[variant]
    cx = cy = TILE / 2
    # -56° → +236° leaves the canonical 70° opening at the top
    return f"""<svg width="{TILE}" height="{TILE}" viewBox="0 0 {TILE} {TILE}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Shutdown timer plugin icon">
  <defs>
    <linearGradient id="face" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0%" stop-color="{a}"/>
      <stop offset="52%" stop-color="{b}"/>
      <stop offset="100%" stop-color="{c}"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.3" cy="0.12" r="0.85">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.34"/>
      <stop offset="55%" stop-color="#ffffff" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="tileClip"><path d="{_clip_path(shape)}"/></clipPath>
  </defs>
  {tile(shape)}
  <g clip-path="url(#tileClip)">
    <rect x="{INSET}" y="{INSET}" width="{SIDE}" height="{SIDE}" fill="url(#sheen)"/>
  </g>
  <g fill="none" stroke="#ffffff" stroke-width="{STROKE}" stroke-linecap="round">
    <path d="{_ring_arc(cx, cy)}"/>
  </g>
  <!-- stem: from one ring-radius above the ring's top edge to just past the
       centre, exactly as the canonical 24-unit power path has it (3 → 13) -->
  <path d="M {cx} {cy - RING_R - 14} V {cy + 16}" fill="none" stroke="#ffffff"
        stroke-width="{STROKE}" stroke-linecap="round"/>
</svg>
"""


def _ring_arc(cx: float, cy: float) -> str:
    """The ring as one arc: -55° to +235°, i.e. the canonical 70° opening."""
    a0, a1 = math.radians(-55), math.radians(-55 + 290)
    x0, y0 = cx + RING_R * math.cos(a0), cy + RING_R * math.sin(a0)
    x1, y1 = cx + RING_R * math.cos(a1), cy + RING_R * math.sin(a1)
    return (f"M {x0:.1f} {y0:.1f} A {RING_R} {RING_R} 0 1 1 {x1:.1f} {y1:.1f}")


def _clip_path(shape: str) -> str:
    if shape == "disc":
        return f"M {TILE/2} {TILE/2 - RADIUS_DISC} a {RADIUS_DISC} {RADIUS_DISC} 0 1 0 0.1 0 z"
    x0, y0 = INSET, INSET
    x1, y1 = INSET + SIDE, INSET + SIDE
    r = RADIUS_ROUND
    return (f"M {x0 + r} {y0} H {x1 - r} A {r} {r} 0 0 1 {x1} {y0 + r} "
            f"V {y1 - r} A {r} {r} 0 0 1 {x1 - r} {y1} "
            f"H {x0 + r} A {r} {r} 0 0 1 {x0} {y1 - r} "
            f"V {y0 + r} A {r} {r} 0 0 1 {x0 + r} {y0} z")


def main() -> None:
    for variant in ("dark", "light"):
        for shape in ("disc", "round"):
            name = f"omarchy_shutdown_plugin_icon_{variant}_{shape}.svg"
            (ASSETS / name).write_text(svg(variant, shape))
            print(name)


if __name__ == "__main__":
    main()
