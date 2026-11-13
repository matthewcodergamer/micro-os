#!/usr/bin/env python3
"""Downsample bundled Dock PNGs to mobile-friendly 128px assets."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
icons = root / "assets" / "icons" / "dock"

for path in sorted(icons.glob("*.png")):
    with Image.open(path) as source:
        source.load()
        original_size = source.size
        image = source.convert("RGBA")
        image.thumbnail((128, 128), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        canvas.alpha_composite(image, ((128-image.width)//2, (128-image.height)//2))
        canvas.save(path, format="PNG", optimize=True, compress_level=9)
    print(f"{path.name}: {original_size} -> 128x128 ({path.stat().st_size:,} bytes)")
