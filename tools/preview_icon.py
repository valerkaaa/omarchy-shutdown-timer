#!/usr/bin/env python3
"""Render the plugin's SVG icons at real sizes and print ASCII previews so the
shapes can be judged without a vision model. Usage:

    python3 tools/preview_icon.py assets/timer.svg [--theme dark|light]

Each icon is rendered at 16/20/24/32 px on the bar background, the alpha
channel is thresholded, and the mask is printed as ASCII. A shape that reads
well here reads well in the bar; muddle shows up as unbroken blobs.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

THEMES = {
    "dark": ((22, 24, 26), (202, 204, 204)),   # background, icon colour
    "light": ((238, 238, 236), (40, 42, 44)),
}


def render(svg: Path, size: int, tmp: Path) -> Image.Image:
    out = tmp / f"{svg.stem}-{size}.png"
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size),
         "--background-color", "transparent", "-o", str(out), str(svg)],
        check=True,
    )
    return Image.open(out).convert("RGBA")


def ascii_art(img: Image.Image, threshold: int = 110) -> list[str]:
    alpha = img.split()[3]
    w, h = alpha.size
    rows = []
    for y in range(h):
        line = ""
        for x in range(w):
            a = alpha.getpixel((x, y))
            line += "█" if a >= threshold else ("▄" if a >= 60 else " ")
        rows.append(line)
    return rows


def compose(img: Image.Image, bg: tuple, fg: tuple, scale: int = 4) -> Image.Image:
    """Flatten the alpha mask onto the theme background, in the theme colour."""
    w, h = img.size
    out = Image.new("RGB", (w, h), bg)
    alpha = img.split()[3]
    solid = Image.new("RGB", (w, h), fg)
    out.paste(solid, (0, 0), alpha)
    return out.resize((w * scale, h * scale), Image.NEAREST)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    svg = Path(sys.argv[1])
    if not svg.exists():
        print(f"missing: {svg}")
        return 1

    theme = "dark"
    if "--theme" in sys.argv:
        theme = sys.argv[sys.argv.index("--theme") + 1]
    bg, fg = THEMES[theme]

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for size in (13, 16, 24, 32):
            img = render(svg, size, tmp)
            alpha = img.split()[3]
            coverage = sum(alpha.histogram()[60:]) / (size * size)
            print(f"--- {svg.name} @ {size}px  coverage={coverage:.2f}")
            for row in ascii_art(img):
                print("   " + row)
            flat = compose(img, bg, fg)
            flat.save(f"/tmp/icon-{svg.stem}-{size}-{theme}.png")
        print(f"saved flat previews to /tmp/icon-{svg.stem}-*-{theme}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
