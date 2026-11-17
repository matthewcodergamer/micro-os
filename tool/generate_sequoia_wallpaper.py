#!/usr/bin/env python3
"""Generate Misty OS's Sequoia-inspired wallpaper.

Apple's own macOS wallpaper artwork is copyrighted and must not be mirrored
into this repository. This script draws an original wallpaper in the same
visual language as macOS Sequoia: a deep blue-to-amber sunrise with layered,
translucent ridgelines.

Run from the repository root:

    python3 tool/generate_sequoia_wallpaper.py

Output: assets/wallpapers/sequoia.jpg (1440x3120, deterministic).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "wallpapers" / "sequoia.jpg"

WIDTH = 1440
HEIGHT = 3120
SEED = 15092024  # macOS 15.0 build date; keeps output reproducible.


def _lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        round(a[0] + (b[0] - a[0]) * t),
        round(a[1] + (b[1] - a[1]) * t),
        round(a[2] + (b[2] - a[2]) * t),
    )


def _gradient(height: int) -> Image.Image:
    """Vertical sky: night at the top, sunrise at the horizon."""
    stops = [
        (0.00, (8, 12, 32)),
        (0.18, (14, 22, 54)),
        (0.38, (32, 40, 84)),
        (0.55, (78, 58, 108)),
        (0.68, (146, 82, 116)),
        (0.78, (208, 116, 100)),
        (0.86, (242, 158, 104)),
        (1.00, (250, 206, 160)),
    ]
    img = Image.new("RGB", (1, height))
    px = img.load()
    for y in range(height):
        t = y / (height - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                f = (t - t0) / (t1 - t0)
                px[0, y] = _lerp(c0, c1, f)
                break
    return img.resize((WIDTH, height), Image.BILINEAR)


def _ridge(
    rand: random.Random,
    base_y: float,
    amplitude: float,
    colour: tuple[int, int, int],
    alpha: int,
) -> Image.Image:
    """One translucent mountain ridge with a soft, noise-driven skyline."""
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    phase_a = rand.uniform(0, math.tau)
    phase_b = rand.uniform(0, math.tau)
    period_a = rand.uniform(520, 900)
    period_b = rand.uniform(180, 340)

    points: list[tuple[int, int]] = [(0, HEIGHT)]
    for x in range(0, WIDTH + 8, 8):
        y = (
            base_y
            - amplitude * math.sin((x / period_a) * math.tau + phase_a)
            - amplitude * 0.35 * math.sin((x / period_b) * math.tau + phase_b)
        )
        points.append((x, round(y)))
    points.append((WIDTH, HEIGHT))

    draw.polygon(points, fill=(*colour, alpha))
    return layer


def main() -> None:
    rand = random.Random(SEED)

    sky = _gradient(HEIGHT).convert("RGBA")

    # Sun glow just above the horizon.
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = WIDTH * 0.52, HEIGHT * 0.80
    for step in range(18, 0, -1):
        r = step * 46
        a = int(5 + (18 - step) * 1.4)
        gdraw.ellipse(
            (cx - r, cy - r * 0.55, cx + r, cy + r * 0.55),
            fill=(255, 196, 140, a),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    sky = Image.alpha_composite(sky, glow)

    # Ridges, far to near.
    ridges = [
        (HEIGHT * 0.815, 70, (60, 46, 92), 150),
        (HEIGHT * 0.845, 92, (44, 34, 74), 190),
        (HEIGHT * 0.882, 104, (30, 24, 56), 220),
        (HEIGHT * 0.925, 86, (18, 15, 40), 240),
        (HEIGHT * 0.965, 60, (10, 9, 26), 252),
    ]
    for base_y, amp, colour, alpha in ridges:
        sky = Image.alpha_composite(sky, _ridge(rand, base_y, amp, colour, alpha))

    # Atmospheric haze near the horizon so the ridges read as depth.
    haze = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(haze)
    hdraw.rectangle(
        (0, HEIGHT * 0.74, WIDTH, HEIGHT * 0.90),
        fill=(255, 178, 140, 26),
    )
    haze = haze.filter(ImageFilter.GaussianBlur(90))
    sky = Image.alpha_composite(sky, haze)

    # Film grain keeps flat gradients from banding on OLED panels.
    noise = Image.effect_noise((WIDTH, HEIGHT), 10).convert("L")
    grain = Image.merge("RGBA", (noise, noise, noise, noise.point(lambda v: 7)))
    sky = Image.alpha_composite(sky, grain)

    # Gentle vignette.
    vignette = Image.new("L", (WIDTH, HEIGHT), 0)
    vdraw = ImageDraw.Draw(vignette)
    vdraw.ellipse(
        (-WIDTH * 0.35, -HEIGHT * 0.15, WIDTH * 1.35, HEIGHT * 1.15),
        fill=255,
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(280))
    dark = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 90))
    sky = Image.composite(sky, Image.alpha_composite(sky, dark), vignette)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    # JPEG keeps the 1440x3120 gradient under a megabyte; PNG would ship 2.7 MB
    # of film grain that the phone cannot even resolve.
    sky.convert("RGB").save(OUT, format="JPEG", quality=92, subsampling=0, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size:,} bytes, {WIDTH}x{HEIGHT})")


if __name__ == "__main__":
    main()
