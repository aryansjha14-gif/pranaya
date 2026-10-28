#!/usr/bin/env python3
"""Draw the Pranaya launcher icons. Runs on the build machine so the repo
stays free of binary blobs."""
import os

from PIL import Image, ImageDraw, ImageFont

OUT = "assets/android_icon"
os.makedirs(OUT, exist_ok=True)

FONT = None
for candidate in (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
):
    if os.path.exists(candidate):
        FONT = candidate
        break


def make(size: int, round_icon: bool = False) -> Image.Image:
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for y in range(s):
        t = y / s
        colour = (0, int(230 - 120 * t), int(118 + 60 * t), 255)
        draw.line([(0, y), (s, y)], fill=colour)
    mask = Image.new("L", (s, s), 0)
    mask_draw = ImageDraw.Draw(mask)
    if round_icon:
        mask_draw.ellipse([0, 0, s, s], fill=255)
    else:
        mask_draw.rounded_rectangle([0, 0, s, s], radius=int(s * 0.24), fill=255)
    img.putalpha(mask)
    draw = ImageDraw.Draw(img)
    if FONT:
        font = ImageFont.truetype(FONT, int(s * 0.58))
        text = "P"
        box = draw.textbbox((0, 0), text, font=font)
        w = box[2] - box[0]
        h = box[3] - box[1]
        draw.text(
            ((s - w) / 2 - box[0], (s - h) / 2 - box[1]),
            text,
            font=font,
            fill=(6, 14, 10, 255),
        )
    else:
        draw.ellipse(
            [s * 0.3, s * 0.3, s * 0.7, s * 0.7],
            fill=(6, 14, 10, 255),
        )
    return img.resize((size, size), Image.LANCZOS)


for px in (48, 72, 96, 144, 192, 512):
    make(px).save(f"{OUT}/ic_launcher_{px}.png")
    make(px, round_icon=True).save(f"{OUT}/ic_launcher_round_{px}.png")

print("icons written to", OUT)
