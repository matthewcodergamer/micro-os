#!/usr/bin/env python3
"""Generate Misty OS's sky-blue cloud launcher icon and adaptive layers."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets" / "icon"
ROOT.mkdir(parents=True, exist_ok=True)
SIZE = 1024


def make_background():
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    top, bottom = (190, 218, 249), (103, 157, 222)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        # A gentle blue sky gradient, with a slightly deeper blue toward the base.
        row = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(SIZE):
            pixels[x, y] = row

    mist = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mist)
    draw.ellipse((-180, 610, 520, 1110), fill=(255, 224, 224, 115))
    draw.ellipse((520, -170, 1120, 350), fill=(255, 255, 255, 85))
    draw.ellipse((80, 80, 560, 350), fill=(255, 255, 255, 52))
    mist = mist.filter(ImageFilter.GaussianBlur(100))
    return Image.alpha_composite(image.convert("RGBA"), mist)


def make_cloud_mask():
    mask = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(mask)
    # Main cloud body and its three rounded upper lobes.
    d.rounded_rectangle((170, 500, 850, 820), radius=160, fill=255)
    d.ellipse((190, 410, 520, 745), fill=255)
    d.ellipse((330, 300, 660, 650), fill=255)
    d.ellipse((500, 320, 810, 650), fill=255)
    # The crescent-shaped bite and its floating circular highlight.
    d.ellipse((630, 340, 900, 610), fill=0)
    d.ellipse((685, 395, 785, 495), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(1.0))


def main():
    background = make_background()
    mask = make_cloud_mask()

    # Soft, cool shadow gives the white cloud the same floating/glossy character
    # as the supplied reference icon without baking a black border into the layer.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (SIZE, SIZE), 0)
    shadow_mask.paste(mask, (0, 14))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(30))
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (49, 105, 176, 0))
    shadow_layer.putalpha(shadow_mask.point(lambda p: int(p * 0.30)))
    foreground = Image.alpha_composite(shadow, shadow_layer)

    cloud = Image.new("RGBA", (SIZE, SIZE), (250, 252, 255, 0))
    cloud.putalpha(mask)
    foreground = Image.alpha_composite(foreground, cloud)

    # A faint lower highlight adds a polished, glassy finish while retaining a
    # clean white silhouette at launcher sizes.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.arc((205, 465, 830, 840), start=12, end=168,
           fill=(255, 255, 255, 100), width=9)
    highlight.putalpha(Image.composite(highlight.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    foreground = Image.alpha_composite(foreground, highlight)

    full = Image.alpha_composite(background, foreground)
    full.convert("RGB").save(ROOT / "misty_icon.png", optimize=True)
    background.convert("RGB").save(ROOT / "misty_background.png", optimize=True)
    foreground.save(ROOT / "misty_foreground.png", optimize=True)

    monochrome = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    monochrome.putalpha(mask)
    monochrome.save(ROOT / "misty_monochrome.png", optimize=True)
    print(f"Generated Misty OS launcher assets in {ROOT}")


if __name__ == "__main__":
    main()
