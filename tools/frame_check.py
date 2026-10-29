#!/usr/bin/env python3
"""Check that a card crop really frames the card at the requested margin.

A capture taken in the wrong coordinate space, or taken a moment too early,
still has the right size and still parses — it just shows the desktop offset by
a quarter instead of the card. The one thing it cannot do is put a thin, evenly
coloured line exactly where the margin says the card's frame must be.

All three numbers are in the crop's own pixels (the margin is the one the crop
was cut with, so the frame must sit exactly there).

Usage:  frame_check.py crop.png MARGIN CARD_W CARD_H
Exit:   0 frame found where it belongs, 1 it is not there.
"""
import sys

from PIL import Image

TOL_STD = 12        # a frame line is evenly coloured; content is not
TOL_DIFF = 8        # and it must stand out from what is around the card


def patch_mean(im, x, y, size=12):
    px = [im.getpixel((i, j))
          for i in range(max(0, x), min(im.width, x + size))
          for j in range(max(0, y), min(im.height, y + size))]
    n = len(px)
    return [sum(p[c] for p in px) / n for c in range(3)]


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    path, inset, card_w, card_h = sys.argv[1], *map(int, sys.argv[2:])
    im = Image.open(path).convert("RGB")
    if inset < 2 or inset * 2 >= min(im.width, im.height):
        print(f"inset {inset} px does not fit the crop")
        return 1
    if abs(im.width - (card_w + 2 * inset)) > 2:
        print(f"crop is {im.width} px wide, expected {card_w + 2 * inset}")
        return 1

    corner = patch_mean(im, 0, 0)
    for x, y in ((im.width - 12, 0), (0, im.height - 12),
                 (im.width - 12, im.height - 12)):
        m = patch_mean(im, x, y)
        corner = [(a + b) / 2 for a, b in zip(corner, m)]

    lines = {}
    for name, (x0, y0, x1, y1) in {
        "top": (inset + 5, inset, im.width - inset - 5, inset),
        "bottom": (inset + 5, im.height - 1 - inset, im.width - inset - 5,
                   im.height - 1 - inset),
        "left": (inset, inset + 5, inset, im.height - inset - 5),
        "right": (im.width - 1 - inset, inset + 5, im.width - 1 - inset,
                  im.height - inset - 5),
    }.items():
        if x0 == x1:
            px = [im.getpixel((x0, y)) for y in range(y0, y1)]
        else:
            px = [im.getpixel((x, y0)) for x in range(x0, x1)]
        n = len(px)
        mean = [sum(p[c] for p in px) / n for c in range(3)]
        std = max((sum((p[c] - mean[c]) ** 2 for p in px) / n) ** 0.5
                  for c in range(3))
        lines[name] = (std, max(abs(mean[c] - corner[c]) for c in range(3)))

    bad = [f"{k}(std {s:.0f} diff {d:.0f})"
           for k, (s, d) in lines.items() if s > TOL_STD or d < TOL_DIFF]
    if bad:
        print("no card frame at the margin: " + ", ".join(bad))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
