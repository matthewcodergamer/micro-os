#!/usr/bin/env python3
"""Derive every Misty OS launcher layer from the approved 512px icon.

`playstore-icon-512.png` in the repository root **is** the approved Misty OS
icon. This script only resamples it: it never redraws, recolours or replaces
the artwork, so the installed APK always shows exactly what was approved.

Outputs (consumed by `flutter_launcher_icons.yaml`):

* ``misty_icon.png``        legacy launcher icon
* ``misty_foreground.png`` adaptive foreground (full bleed)
* ``misty_background.png`` adaptive background (gradient sampled from the
                           approved art so the adaptive mask never shows a seam)
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "playstore-icon-512.png"
OUT = ROOT / "assets" / "icon"
SIZE = 1024


def _edge_colour(image: Image.Image, y: int) -> tuple[int, int, int]:
    """Average colour of one full-width row of the approved artwork."""
    strip = image.crop((0, y, image.width, y + 1)).convert("RGB")
    return strip.resize((1, 1), Image.BOX).getpixel((0, 0))


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Approved icon missing: {SOURCE}")

    OUT.mkdir(parents=True, exist_ok=True)

    approved = Image.open(SOURCE).convert("RGBA")
    full = approved.resize((SIZE, SIZE), Image.LANCZOS)

    # Legacy icon + adaptive foreground: the approved art, full bleed.
    full.convert("RGB").save(OUT / "misty_icon.png", optimize=True)
    full.save(OUT / "misty_foreground.png", optimize=True)

    # Adaptive background: vertical gradient between the artwork's own top and
    # bottom edges. Neutral, seamless, and derived only from approved pixels.
    top = _edge_colour(full, 0)
    bottom = _edge_colour(full, SIZE - 1)
    background = Image.new("RGB", (SIZE, SIZE))
    pixels = background.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        row = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(SIZE):
            pixels[x, y] = row
    background.save(OUT / "misty_background.png", optimize=True)

    print(f"Derived launcher layers from {SOURCE.name} in {OUT}")
    print(f"  top edge    : {top}")
    print(f"  bottom edge : {bottom}")


if __name__ == "__main__":
    main()
