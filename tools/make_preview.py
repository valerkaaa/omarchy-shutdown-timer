#!/usr/bin/env python3
"""Build the marketplace preview card (preview.png) from live assets.

The marketplace turns this one image into the catalogue card and the detail
header, so it must read at card size (a few hundred px wide): a big name, the
four actions, and the two surfaces the plugin actually draws — never a photo of
a whole desktop.

Everything is composed from files in this repository (the store icon, the popup
screenshot, the five bar states), so the card cannot drift from the plugin:

    python3 tools/make_preview.py            # writes preview.png
    python3 tools/make_preview.py --out x.png
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1280, 800
PLUGIN = Path(__file__).resolve().parent.parent
FONT_BOLD = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf"
FONT_REGULAR = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"

BG_TOP = (36, 27, 26)          # ristretto-ish, the theme the README shoots in
BG_BOTTOM = (18, 13, 12)
INK = (230, 217, 219)
MUTED = (170, 143, 138)
ACCENT = (243, 141, 112)
MARGIN = 72

TITLE = "Shutdown Timer"
TAGLINE = "poweroff · reboot · suspend · hibernate"
SUBTITLE = "bar widget + countdown overlay for Omarchy 4"
STRIP_CAPTION = "idle · active · last 5 min · paused · countdown"


def background() -> Image.Image:
    rows = np.linspace(0, 1, H)[:, None]
    base = (np.array(BG_TOP) * (1 - rows) + np.array(BG_BOTTOM) * rows)
    img = np.repeat(base[:, None, :], W, axis=1)

    # one warm glow behind the popup, so the flat panel has a light source
    # without washing out the text column on the left
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.hypot((xx - 980) / 780, (yy - 300) / 640)
    glow = np.clip(1 - d, 0, 1) ** 2 * 0.4
    img = img * (1 - glow[..., None]) + np.array(ACCENT) * glow[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype("uint8"))


def svg_icon(size: int, tmp: Path) -> Image.Image:
    out = tmp / "mark.png"
    subprocess.run(["magick", "-background", "none", "-density", "600",
                    str(PLUGIN / "assets/omarchy_shutdown_plugin_icon_dark_round.svg"),
                    "-resize", f"{size}x{size}", str(out)], check=True)
    return Image.open(out).convert("RGBA")


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1),
                                           radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def drop_shadow(canvas: Image.Image, box: tuple, radius: int, blur: int = 22,
                alpha: int = 200) -> None:
    x, y, w, h = box
    pad = blur * 3
    layer = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((pad, pad, pad + w, pad + h),
                                            radius, fill=(0, 0, 0, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(layer, (x - pad, y - pad + 10))


def fit_height(img: Image.Image, height: int) -> Image.Image:
    return img.resize((round(img.width * height / img.height), height), Image.LANCZOS)


def main() -> int:
    out = PLUGIN / "preview.png"
    if "--out" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--out") + 1])

    canvas = background().convert("RGBA")
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        # ---- the popup, the surface that sells the plugin ----
        popup = rounded(Image.open(PLUGIN / "assets/screenshots/dark/6-popup.png")
                        .convert("RGBA"), 14)
        popup = fit_height(popup, 560)
        px, py = W - MARGIN - popup.width, 104
        drop_shadow(canvas, (px, py, popup.width, popup.height), 14)
        canvas.alpha_composite(popup, (px, py))

        # ---- the five bar states ----
        strip_y = H - MARGIN - 59
        x = MARGIN
        for name in ("1-idle", "2-active", "3-warning", "4-paused", "5-countdown"):
            shot = (Image.open(PLUGIN / f"assets/screenshots/dark/{name}.png")
                    .convert("RGBA").resize((190, 59), Image.NEAREST))
            drop_shadow(canvas, (x, strip_y, 190, 59), 6, blur=8, alpha=140)
            canvas.alpha_composite(shot, (x, strip_y))
            x += 190 + 14

        # ---- mark and words last, so no shadow can dim them ----
        canvas.alpha_composite(svg_icon(96, tmp), (MARGIN, MARGIN - 6))

        draw = ImageDraw.Draw(canvas)
        bold = ImageFont.truetype(FONT_BOLD, 62)
        mid = ImageFont.truetype(FONT_REGULAR, 27)
        small = ImageFont.truetype(FONT_REGULAR, 21)
        draw.text((MARGIN, 196), TITLE, font=bold, fill=INK)
        draw.text((MARGIN, 276), TAGLINE, font=mid, fill=ACCENT)
        draw.text((MARGIN, 316), SUBTITLE, font=mid, fill=MUTED)
        draw.text((MARGIN, strip_y - 40), STRIP_CAPTION, font=small, fill=MUTED)

    canvas.convert("RGB").save(out, optimize=True)
    print(f"{out.relative_to(PLUGIN)}  {canvas.width}x{canvas.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
