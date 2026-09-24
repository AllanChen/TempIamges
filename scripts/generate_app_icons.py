#!/usr/bin/env python3
"""Regenerate macOS AppIcon.appiconset from logo.png with proper safe-area padding.

The original logo fills the entire canvas, which makes the icon look oversized in
places like Command+Tab. macOS app icons should keep their content inside a safe
area (about 80% of the canvas). This script scales the logo to 80% and centers it,
then renders all required icon sizes.

Usage:
    python3 -m venv .venv-icon
    .venv-icon/bin/pip install Pillow
    .venv-icon/bin/python scripts/generate_app_icons.py
"""

from PIL import Image
import os

SRC = "logo.png"
OUT_DIR = "Glance/Resources/Assets.xcassets/AppIcon.appiconset"

# macOS app icon sizes: (point_size, scale, output_filename)
SIZES = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

# Target master canvas: 1024x1024 (the largest @2x icon). Content occupies 80%.
MASTER_SIZE = 1024
CONTENT_SCALE = 0.8


def make_master() -> Image.Image:
    src = Image.open(SRC).convert("RGBA")
    # logo.png is 1080x1080; downscale content to 80% of the master canvas.
    content_size = int(MASTER_SIZE * CONTENT_SCALE)
    src_resized = src.resize((content_size, content_size), Image.Resampling.LANCZOS)

    master = Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))
    offset = (MASTER_SIZE - content_size) // 2
    master.paste(src_resized, (offset, offset), src_resized)
    return master


def main():
    master = make_master()
    os.makedirs(OUT_DIR, exist_ok=True)

    for point_size, scale, filename in SIZES:
        px = point_size * scale
        icon = master.resize((px, px), Image.Resampling.LANCZOS)
        out_path = os.path.join(OUT_DIR, filename)
        icon.save(out_path, "PNG")
        print(f"Generated {out_path} ({px}x{px})")


if __name__ == "__main__":
    main()
