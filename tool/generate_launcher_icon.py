#!/usr/bin/env python3
"""Generate the MicroOS launcher artwork before flutter_launcher_icons runs."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets" / "icon"
ROOT.mkdir(parents=True, exist_ok=True)
SIZE = 1024


def make_background():
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    start, middle, end = (10, 16, 34), (39, 49, 112), (13, 25, 48)
    for y in range(SIZE):
        for x in range(SIZE):
            t = max(0.0, min(1.0, (x * 0.62 + y * 0.78) / (SIZE * 1.4)))
            if t < 0.58:
                q, a, b = t / 0.58, start, middle
            else:
                q, a, b = (t - 0.58) / 0.42, middle, end
            color = tuple(int(a[i] + (b[i] - a[i]) * q) for i in range(3))
            dx, dy = (x - 770) / 700, (y - 220) / 700
            bloom = max(0.0, 1.0 - math.sqrt(dx * dx + dy * dy)) * 0.16
            color = (
                min(255, int(color[0] + 20 * bloom)),
                min(255, int(color[1] + 85 * bloom)),
                min(255, int(color[2] + 110 * bloom)),
            )
            pixels[x, y] = (*color, 255)
    return image


def make_foreground():
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (192, 242, 832, 778), radius=86, fill=(0, 0, 0, 150)
    )
    layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(30)))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        (180, 220, 844, 770), radius=88,
        fill=(10, 17, 34, 255), outline=(137, 204, 255, 245), width=12
    )
    draw.rounded_rectangle((194, 234, 830, 756), radius=72, fill=(17, 25, 46, 255))
    draw.rounded_rectangle((194, 234, 830, 360), radius=72, fill=(32, 45, 75, 255))
    draw.rectangle((194, 300, 830, 360), fill=(32, 45, 75, 255))
    draw.line((226, 360, 798, 360), fill=(91, 127, 177, 150), width=4)
    draw.ellipse((246, 270, 286, 310), fill=(255, 103, 111, 255))
    draw.ellipse((310, 270, 350, 310), fill=(255, 197, 77, 255))
    draw.ellipse((374, 270, 414, 310), fill=(67, 211, 139, 255))
    draw.line([(306, 486), (390, 548), (306, 610)],
              fill=(89, 198, 255, 255), width=32, joint="curve")
    draw.line([(306, 486), (390, 548), (306, 610)],
              fill=(190, 238, 255, 110), width=8, joint="curve")
    draw.rounded_rectangle((440, 590, 590, 622), radius=10,
                           fill=(240, 248, 255, 255))
    draw.rounded_rectangle((276, 684, 748, 700), radius=8,
                           fill=(72, 132, 196, 90))
    draw.rounded_rectangle((276, 684, 492, 700), radius=8,
                           fill=(66, 190, 255, 235))
    return layer


def main():
    background = make_background()
    foreground = make_foreground()
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        (168, 220, 856, 810), radius=112, fill=(43, 163, 255, 115)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    full = Image.alpha_composite(Image.alpha_composite(background, glow), foreground)
    full.convert("RGB").save(ROOT / "microos_icon.png", optimize=True)
    foreground.save(ROOT / "microos_foreground.png", optimize=True)

    mono = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mono)
    draw.rounded_rectangle((220, 265, 804, 735), radius=80,
                           outline=(255, 255, 255, 255), width=22)
    draw.line([(330, 420), (415, 500), (330, 580)],
              fill=(255, 255, 255, 255), width=30, joint="curve")
    draw.rounded_rectangle((470, 560, 650, 592), radius=10,
                           fill=(255, 255, 255, 255))
    mono.save(ROOT / "microos_monochrome.png", optimize=True)
    print(f"Generated MicroOS launcher assets in {ROOT}")


if __name__ == "__main__":
    main()
