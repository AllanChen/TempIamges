"""Make the Watermark Remover example pair from one clean photo.

after.png  = the clean photo (resized to 1200 px wide)
before.png = the same photo with a generic, made-up tiled watermark ("SAMPLE · PHOTO STUDIO"), no real brand.
The pair is an illustration (labelled 示例效果 / Example effect), not real Widget output.

Usage (repo root): .venv/bin/python design/marketing/videos/widget-daily/watermark/make_samples.py <clean-photo> [out-dir]
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1])
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent / 'samples'
out.mkdir(parents=True, exist_ok=True)

img = Image.open(src).convert('RGB')
img = img.resize((1200, round(img.height * 1200 / img.width)), Image.Resampling.LANCZOS)
img.save(out / 'after.png')

W, H = img.size
font = ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', 46, index=1)
big = ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', 120, index=1)
layer = Image.new('RGBA', (W * 2, H * 2))
d = ImageDraw.Draw(layer)
label = '©  SAMPLE · PHOTO STUDIO'
step_x, step_y = 620, 230
for row, y in enumerate(range(0, H * 2, step_y)):
    for x in range(-step_x + (row % 2) * step_x // 2, W * 2, step_x):
        d.text((x, y), label, font=font, fill=(255, 255, 255, 92), stroke_width=2, stroke_fill=(0, 0, 0, 40))
layer = layer.rotate(math.degrees(math.atan2(1, 2.2)), resample=Image.Resampling.BICUBIC)
layer = layer.crop((W // 2, H // 2, W // 2 + W, H // 2 + H))
d = ImageDraw.Draw(layer)
d.text((W / 2, H * .52), 'SAMPLE', font=big, fill=(255, 255, 255, 150), anchor='mm', stroke_width=3, stroke_fill=(0, 0, 0, 60))
before = Image.alpha_composite(img.convert('RGBA'), layer).convert('RGB')
before.save(out / 'before.png')
print(out / 'before.png', out / 'after.png', img.size)
