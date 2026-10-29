#!/usr/bin/env python3
"""Locate a framed card (popup or overlay) in a screenshot: print "x y w h".

Both cards draw a thin accent-coloured frame around a solid panel. That frame
is the most reliable handle on the card: the popup is a Qt popup (absent from
`hyprctl layers`) and the overlay's geometry is not published.

The frame is recognised by shape, not by a hard-coded colour: candidate
rectangles are built from pairs of thin vertical lines of one colour, and a
candidate is kept only if its whole perimeter is painted in that same colour.
Wallpaper, terminal text and the dimming backdrop behind the overlay all fail
the perimeter test, so the desktop may be as busy as it likes.

Usage:  card_bbox.py shot.png   ->  "x y w h"   (0 0 0 0 when no card is up)
"""
import subprocess
import sys
from collections import defaultdict


MIN_RUN = 120          # a border must be at least this many px long
MAX_THICK = 8          # a border line is thinner than this
MIN_SIDE = 120         # a card is at least this big
MAX_GAP = 3            # px between the columns of one border line
PERIMETER = 0.9        # share of the perimeter that must be the border colour


def load_ppm(path):
    raw = subprocess.run(["magick", path, "-depth", "8", "ppm:-"],
                         capture_output=True, check=True).stdout
    pos, fields = 0, []
    while len(fields) < 3:
        while raw[pos:pos + 1].isspace():
            pos += 1
        if raw[pos:pos + 1] == b"#":
            while raw[pos:pos + 1] != b"\n":
                pos += 1
            continue
        start = pos
        while not raw[pos:pos + 1].isspace():
            pos += 1
        tok = raw[start:pos]
        if tok == b"P6":
            continue
        fields.append(int(tok))
    pos += 1
    w, h = fields[0], fields[1]
    return w, h, raw[pos:pos + w * h * 3]


def clusters(values, gap=MAX_GAP):
    """Group sorted ints into runs separated by more than `gap`."""
    out = []
    for v in sorted(values):
        if out and v - out[-1][-1] <= gap:
            out[-1].append(v)
        else:
            out.append([v])
    return out


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("-"):
        print(__doc__)
        return 2
    w, h, data = load_ppm(sys.argv[1])
    stride = w * 3

    def colour(x, y):
        o = y * stride + x * 3
        return data[o] << 16 | data[o + 1] << 8 | data[o + 2]

    if (x0 := min(w, 3)) and (x1 := max(0, 3)):  # noqa: E501  (keeps x0/x1 local)
        pass

    # columns that contain a long unbroken run of some colour
    col_hits = defaultdict(list)
    row_hits = defaultdict(list)
    for x in range(w):
        prev, start = None, 0
        for y in range(h + 1):
            v = colour(x, y) if y < h else None
            if v != prev:
                if prev is not None and y - start >= MIN_RUN:
                    col_hits[prev].append(x)
                prev, start = v, y
    for y in range(h):
        prev, start = None, 0
        for x in range(w + 1):
            v = colour(x, y) if x < w else None
            if v != prev:
                if prev is not None and x - start >= MIN_RUN:
                    row_hits[prev].append(y)
                prev, start = v, x

    best = None
    for c in set(col_hits) & set(row_hits):
        lines = [ln for ln in clusters(col_hits[c]) if len(ln) <= MAX_THICK]
        if len(lines) < 2:
            continue
        for i in range(len(lines)):
            for j in range(i + 1, len(lines)):
                x0, x1 = lines[i][0], lines[j][-1]
                cw = x1 - x0 + 1
                if cw < MIN_SIDE or cw > 0.98 * w:
                    continue
                rows = [r for r in clusters(row_hits[c]) if len(r) <= MAX_THICK]
                if len(rows) < 2:
                    continue
                for a in range(len(rows)):
                    for b in range(a + 1, len(rows)):
                        y0, y1 = rows[a][0], rows[b][-1]
                        ch = y1 - y0 + 1
                        if ch < MIN_SIDE or ch > 0.98 * h:
                            continue
                        # the whole perimeter must be that colour
                        peri = 0
                        total = 0
                        for x in range(x0, x1 + 1):
                            for y in (y0, y1):
                                total += 1
                                if colour(x, y) == c:
                                    peri += 1
                        for y in range(y0, y1 + 1):
                            for x in (x0, x1):
                                total += 1
                                if colour(x, y) == c:
                                    peri += 1
                        if peri < PERIMETER * total:
                            continue
                        area = cw * ch
                        if best is None or area > best[0]:
                            best = (area, x0, y0, cw, ch)

    if best is None:
        print("0 0 0 0")
        return 1
    _, x, y, cw, ch = best
    print(x, y, cw, ch)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
