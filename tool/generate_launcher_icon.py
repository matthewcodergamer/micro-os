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
    """Transparent adaptive foreground: a luminous M inside a microchip."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle((210, 205, 814, 819), radius=150,
                         outline=(0, 190, 255, 245), width=34)
    for i in range(6):
        x = 330 + i * 72
        gd.line((x, 132, x, 210), fill=(30, 205, 255, 220), width=18)
        gd.line((x, 814, x, 892), fill=(30, 205, 255, 220), width=18)
        y = 330 + i * 72
        gd.line((132, y, 210, y), fill=(30, 205, 255, 220), width=18)
        gd.line((814, y, 892, y), fill=(30, 205, 255, 220), width=18)
    layer = Image.alpha_composite(layer, glow.filter(ImageFilter.GaussianBlur(38)))

    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((210, 205, 814, 819), radius=150,
                           outline=(75, 220, 255, 255), width=24)
    draw.rounded_rectangle((252, 247, 772, 777), radius=116,
                           outline=(30, 132, 255, 230), width=12)

    # The custom M is drawn as one continuous, rounded neon stroke.
    m = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    md = ImageDraw.Draw(m)
    points = [(340, 680), (340, 365), (512, 555), (684, 365), (684, 680)]
    md.line(points, fill=(60, 205, 255, 255), width=78, joint="curve")
    for x, y in (points[0], points[-1]):
        md.ellipse((x - 39, y - 39, x + 39, y + 39),
                   fill=(60, 205, 255, 255))
    layer = Image.alpha_composite(layer, m.filter(ImageFilter.GaussianBlur(34)))
    layer = Image.alpha_composite(layer, m)
    highlight = ImageDraw.Draw(layer)
    highlight.line([(370, 646), (370, 415), (512, 570),
                    (654, 415), (654, 646)],
                   fill=(218, 249, 255, 255), width=12, joint="curve")
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
    draw.rounded_rectangle((220, 220, 804, 804), radius=142,
                           outline=(255, 255, 255, 255), width=24)
    draw.line([(350, 680), (350, 390), (512, 560),
               (674, 390), (674, 680)],
              fill=(255, 255, 255, 255), width=58, joint="curve")
    mono.save(ROOT / "microos_monochrome.png", optimize=True)
    print(f"Generated MicroOS launcher assets in {ROOT}")


if __name__ == "__main__":
    main()
