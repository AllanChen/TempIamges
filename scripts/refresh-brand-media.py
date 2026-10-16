#!/usr/bin/env python3
"""Compose Glance's product screenshots with the generated alpine sample pair.

The photographs live in layout/brand-assets. This script replaces only sample
media and thumbnail fills; the window controls come from the Figma exports.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "layout/brand-assets"
SAMPLES = ROOT / "outputs/glance-promo-20s/assets"
SITE = ROOT / "website-static/src/assets/img"
RESAMPLE = Image.Resampling.LANCZOS

before = Image.open(BRAND / "glance-alpine-before.png").convert("RGB")
after = Image.open(BRAND / "glance-alpine-after.png").convert("RGB")
focus_source = Image.open(SAMPLES / "focus.png").convert("RGBA")
compare_source = Image.open(SAMPLES / "compare.png").convert("RGBA")


def rounded_crop(source, box, radius):
    piece = source.crop(box)
    mask = Image.new("L", piece.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, piece.width - 1, piece.height - 1), radius, fill=255)
    piece.putalpha(mask)
    return piece


def tile(source, photo, badge=None):
    tile = source.copy()
    thumb = ImageOps.fit(photo, (82, 82), method=RESAMPLE).convert("RGBA")
    mask = Image.new("L", thumb.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 81, 81), 5, fill=255)
    thumb.putalpha(mask)
    tile.alpha_composite(thumb, (6, 6))
    if badge is not None:
        tile.alpha_composite(badge, (49, 66))
    return tile


def focus():
    size = focus_source.size
    photo = ImageOps.fit(before, size, method=RESAMPLE).filter(ImageFilter.GaussianBlur(34))
    fitted = ImageOps.contain(before, size, method=RESAMPLE)
    photo.paste(fitted, ((size[0] - fitted.width) // 2, 0))
    result = photo.convert("RGBA")
    strip = Image.new("RGBA", (size[0], 119), (15, 17, 20, 133))
    result.alpha_composite(strip, (0, 893))
    badge = focus_source.crop((778, 972, 821, 995))
    pieces = (
        (focus_source.crop((623, 906, 717, 1000)), before, None),
        (focus_source.crop((729, 906, 823, 1000)), after, badge),
        (focus_source.crop((835, 906, 929, 1000)), before, None),
    )
    for i, (frame, scene, marker) in enumerate(pieces):
        result.alpha_composite(tile(frame, scene, marker), (623 + i * 106, 906))
    result.alpha_composite(rounded_crop(focus_source, (640, 23, 914, 79), 17), (640, 23))
    for x, color in ((25, "#f46f61"), (51, "#ffbd49"), (78, "#55c95f")):
        ImageDraw.Draw(result).ellipse((x - 6, 18, x + 6, 30), fill=color)
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), 16, fill=255)
    result.putalpha(mask)
    return result


def compare():
    result = compare_source.copy()
    left = ImageOps.fit(before, (777, 1012), method=RESAMPLE).convert("RGBA")
    right = ImageOps.fit(after, (777, 1012), method=RESAMPLE).convert("RGBA")
    window = Image.new("RGBA", (1554, 1012))
    window.alpha_composite(left, (0, 0))
    window.alpha_composite(right, (777, 0))
    ImageDraw.Draw(window).line((777, 0, 777, 1012), fill=(235, 230, 222, 155), width=2)
    window.alpha_composite(Image.new("RGBA", (1554, 117), (15, 17, 20, 128)), (0, 895))
    badge = focus_source.crop((778, 972, 821, 995))
    for i, (frame, scene, marker) in enumerate((
        (focus_source.crop((623, 906, 717, 1000)), before, None),
        (focus_source.crop((729, 906, 823, 1000)), after, badge),
        (focus_source.crop((835, 906, 929, 1000)), before, None),
    )):
        window.alpha_composite(tile(frame, scene, marker), (617 + i * 106, 906))
    window.alpha_composite(rounded_crop(compare_source, (688, 48, 962, 107), 16), (640, 18))
    for x, color in ((26, "#f46f61"), (52, "#ffbd49"), (79, "#55c95f")):
        ImageDraw.Draw(window).ellipse((x - 6, 18, x + 6, 30), fill=color)
    mask = Image.new("L", window.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1553, 1011), 13, fill=255)
    window.putalpha(mask)
    result.alpha_composite(window, (48, 30))
    return result


def save_jpeg(image, path, size):
    image = image.resize(size, RESAMPLE)
    flattened = Image.new("RGB", size, "#101115")
    flattened.paste(image, mask=image.getchannel("A"))
    flattened.save(path, quality=91, optimize=True, subsampling=0)


def english_assets():
    """English counterparts for the two screenshots with baked-in Chinese UI."""
    base = Image.open(SITE / "focus.jpg").convert("RGBA")
    menu = base.copy()
    draw = ImageDraw.Draw(menu)
    regular = "/System/Library/Fonts/SFNS.ttf"
    def label(x, y, value, size=22, color=(235, 234, 232)):
        draw.text((x, y), value, font=ImageFont.truetype(regular, size), fill=color, anchor="lm")
    for box in ((229, 365, 592, 728), (602, 365, 1077, 916)):
        draw.rounded_rectangle(box, radius=13, fill=(23, 24, 29), outline=(76, 75, 77), width=2)
    draw.rounded_rectangle((239, 377, 582, 421), radius=8, fill=(233, 170, 127))
    for i, name in enumerate(("Widget", "Copy Image", "Edit", "Export", "Tools", "Show in Finder", "Image Info")):
        label(256, 399 + i * 47, name, 22, (31, 27, 27) if i == 0 else (231, 230, 231))
    draw.line((251, 612, 570, 612), fill=(67, 67, 70), width=1)
    label(625, 391, "Installed", 19, (173, 173, 177))
    label(995, 391, "Credits", 18, (173, 173, 177))
    names = ("Remove Background", "Upscale", "Outpaint", "Video Watermark", "AI Search", "Image Watermark", "Image to Prompt", "Free Gallery")
    for i, name in enumerate(names):
        y = 435 + i * 52
        if i == 1:
            draw.rounded_rectangle((614, y - 22, 1065, y + 22), radius=7, fill=(233, 170, 127))
        label(629, y, name, 20, (34, 28, 27) if i == 1 else (230, 228, 229))
        draw.rounded_rectangle((1000, y - 17, 1047, y + 17), radius=8, fill=(206, 145, 105) if i == 1 else (43, 44, 48))
        label(1017, y, "1", 20, (52, 37, 31) if i == 1 else (204, 203, 205))
    draw.line((623, 861, 1055, 861), fill=(69, 68, 72), width=1)
    label(629, 889, "Widget Marketplace…", 20, (209, 208, 210))
    menu.convert("RGB").save(SITE / "widget-menu-en.jpg", quality=91, optimize=True, subsampling=0)

    result = ImageOps.fit(after, (1400, 948), method=RESAMPLE).convert("RGBA")
    badge = ImageDraw.Draw(result)
    badge.rounded_rectangle((1084, 46, 1352, 114), radius=14, fill=(25, 34, 31, 246))
    badge.text((1218, 80), "AI complete", font=ImageFont.truetype(regular, 26), fill=(163, 218, 190), anchor="mm")
    badge.rounded_rectangle((0, 0, 1399, 947), radius=32, outline=(16, 17, 20), width=12)
    result.convert("RGB").save(SITE / "widget-result-en.jpg", quality=91, optimize=True, subsampling=0)


def main():
    focus_image = focus()
    compare_image = compare()
    focus_image.save(BRAND / "focus-alpine.png", optimize=True)
    compare_image.save(BRAND / "compare-alpine.png", optimize=True)
    save_jpeg(focus_image, SITE / "focus.jpg", (1400, 912))
    save_jpeg(compare_image, SITE / "compare.jpg", (1400, 940))

    menu_source = Image.open(ROOT / "layout/figma-export/widget-context-menu-compact-credits.png").convert("RGBA")
    menu_image = focus_image.resize((1400, 916), RESAMPLE)
    for source_box, dest_box in (
        ((16, 68, 158, 210), (229, 365, 592, 728)),
        ((159, 68, 345, 286), (602, 365, 1077, 916)),
    ):
        panel = rounded_crop(menu_source, source_box, 5)
        panel = panel.resize((dest_box[2] - dest_box[0], dest_box[3] - dest_box[1]), RESAMPLE)
        menu_image.alpha_composite(panel, dest_box[:2])
    save_jpeg(menu_image, SITE / "widget-menu.jpg", (1400, 916))

    result_image = ImageOps.fit(after, (1400, 948), method=RESAMPLE).convert("RGBA")
    badge = Image.new("RGBA", (268, 68))
    badge_draw = ImageDraw.Draw(badge)
    badge_draw.rounded_rectangle((0, 0, 267, 67), 14, fill=(25, 34, 31, 246))
    badge_font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 28)
    badge_draw.text((134, 34), "AI 处理完成", fill=(163, 218, 190), font=badge_font, anchor="mm")
    result_image.alpha_composite(badge, (1084, 46))
    border = Image.new("RGBA", result_image.size)
    ImageDraw.Draw(border).rounded_rectangle((0, 0, 1399, 947), 32, outline=(16, 17, 20), width=12)
    result_image.alpha_composite(border)
    save_jpeg(result_image, SITE / "widget-result.jpg", (1400, 948))
    english_assets()
    print("Refreshed four website screenshots and reusable focus/compare compositions")


if __name__ == "__main__":
    main()
