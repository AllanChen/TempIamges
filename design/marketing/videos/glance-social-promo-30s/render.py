"""Render a 30-second social promo in English or Chinese.

The motion and UI composition reuse the existing Glance promo renderer and its
Figma-exported screens. Run with the repository Python environment that has
Pillow and NumPy installed, plus ffmpeg on PATH.
"""
from pathlib import Path
import argparse
import importlib.util
import subprocess

from PIL import Image, ImageDraw, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "design/marketing/videos/glance-promo-20s/render.py"
SOURCE_AUDIO = SOURCE.parent / "soundtrack.wav"
FPS = 30
DURATION = 30

spec = importlib.util.spec_from_file_location("glance_promo_source", SOURCE)
promo = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(promo)
DEFAULT_ENDING = promo.ending

BG_BEFORE = Image.open(ROOT / "design/marketing/brand-assets/clipboard-DA224852-373C-472B-A405-9260B85880B6.png").convert("RGB")
BG_AFTER = Image.open(ROOT / "design/marketing/brand-assets/clipboard-DA224852-373C-472B-A405-9260B85880B6.Remove Objects.png").convert("RGB")
EXPAND_BEFORE = Image.open(ROOT / "design/marketing/brand-assets/Screenshot 2026-11-06 at 10.52.24.png").convert("RGB")
EXPAND_AFTER = Image.open(ROOT / "design/marketing/brand-assets/Screenshot 2026-11-06 at 10.52.24.Expand.png").convert("RGB")


def ending_with_cta(t):
    image = DEFAULT_ENDING(t)
    text = "Learn more at glancepreview.com" if promo.LANG == "en" else "了解更多：glancepreview.com"
    promo.txt(image, (960, 922), text, 27, promo.WHITE, "en" if promo.LANG == "en" else "cn", "mm")
    return image


def loc(en, zh):
    return en if promo.LANG == "en" else zh


def intro_scene(t):
    image = promo.BG.copy()
    promo.shell(image, 0)
    promo.copy(
        image, "01  /  QUICK PREVIEW",
        [loc("Select a file.", "选中文件。"), loc("Open it instantly.", "一键快速预览。")],
        loc("From any app, select a path\nand open it with Glance.", "在任意应用中选中文件路径，\n用 Glance 快速打开。"), t,
        "OPTION  +  SPACE",
    )
    panel = Image.new("RGBA", (1100, 460))
    draw = ImageDraw.Draw(panel)
    draw.rounded_rectangle((28, 35, 1070, 215), 24, fill=(23, 24, 30), outline=(65, 58, 53), width=2)
    promo.txt(panel, (70, 66), loc("From your current app", "从你正在使用的应用"), 24, promo.GRAY, "en" if promo.LANG == "en" else "cn")
    draw.rounded_rectangle((65, 128, 1032, 185), 10, fill=(66, 48, 37))
    promo.txt(panel, (85, 141), "~/Pictures/portrait.jpg", 27, promo.WARM, "mono")
    key = Image.new("RGBA", (430, 92))
    kd = ImageDraw.Draw(key)
    kd.rounded_rectangle((0, 0, 429, 91), 18, fill=(36, 30, 27), outline=promo.WARM, width=2)
    promo.txt(key, (45, 24), "⌥", 36, promo.WARM, "en")
    promo.txt(key, (105, 31), "Option  +  Space", 27, promo.WHITE, "en")
    alpha = promo.ease(t / .55)
    promo.put(image, panel, (660, 300 + 22 * (1 - alpha)), alpha)
    promo.put(image, key, (995, 570), promo.ease((t - .6) / .45))
    return image


def photo_card(source, heading, width=500, height=760):
    card = Image.new("RGBA", (width, height), (19, 20, 25, 255))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, width - 1, height - 1), 20, fill=(19, 20, 25, 255), outline=(63, 58, 56, 255), width=2)
    promo.txt(card, (width // 2, 26), heading, 18, promo.WARM, "en" if promo.LANG == "en" else "cn", "mt")
    photo = ImageOps.contain(source, (width - 28, height - 72), Image.Resampling.LANCZOS)
    x = (width - photo.width) // 2
    y = 60 + (height - 72 - photo.height) // 2
    layer = promo.rounded(photo, (photo.width, photo.height), 12)
    promo.put(card, layer, (x, y))
    return card


def draw_pair(image, before, after, before_label, after_label, t):
    left = photo_card(before, before_label)
    right = photo_card(after, after_label)
    appear_before = promo.ease(t / .5)
    appear_after = promo.ease((t - .8) / .55)
    promo.put(image, promo.shadow(left.size), (650, 155), appear_before)
    promo.put(image, left, (710, 215 + 20 * (1 - appear_before)), appear_before)
    promo.put(image, promo.shadow(right.size), (1250, 155), appear_after)
    promo.put(image, right, (1310, 215 + 20 * (1 - appear_after)), appear_after)
    arrow = Image.new("RGBA", (72, 72))
    d = ImageDraw.Draw(arrow)
    d.line((9, 36, 59, 36), fill=(*promo.WARM, 235), width=4)
    d.polygon([(58, 26), (70, 36), (58, 46)], fill=(*promo.WARM, 235))
    promo.put(image, arrow, (1224, 545), appear_after)


def background_scene(t):
    image = promo.BG.copy()
    promo.shell(image, 1)
    promo.copy(image, "02  /  REPLACE THE BACKGROUND",
                [loc("Keep the subject.", "保留人物。"), loc("Change the scene.", "换掉背景。")],
                loc("Turn a busy city backdrop\ninto a quiet green park.", "把城市街景换成\n清爽的公园背景。"), t,
                loc("BEFORE  →  NEW BACKGROUND", "原图  →  替换背景"))
    draw_pair(image, BG_BEFORE, BG_AFTER, loc("ORIGINAL", "原图"), loc("NEW BACKGROUND", "替换后"), t)
    return image


def expand_scene(t):
    image = promo.BG.copy()
    promo.shell(image, 2)
    promo.copy(image, "03  /  EXPAND THE IMAGE",
                [loc("Give the image", "给画面"), loc("more room.", "更多空间。")],
                loc("Extend the frame beyond\nthe original crop.", "扩展原有取景范围，\n补出画面之外的内容。"), t,
                loc("ORIGINAL  →  EXPANDED", "原图  →  扩图后"))
    draw_pair(image, EXPAND_BEFORE, EXPAND_AFTER, loc("ORIGINAL", "原图"), loc("EXPANDED", "扩图后"), t)
    return image


def widget_scene(t):
    image = promo.BG.copy()
    promo.shell(image, 3)
    promo.copy(image, loc("04  /  IMAGE WIDGETS", "04  /  图片 Widget"),
                [loc("Choose a Widget.", "选择 Widget。"), loc("See the result.", "查看处理结果。")],
                loc("Run image tools from your\nGlance workflow.", "在 Glance 的工作流程中\n运行图片处理工具。"), t,
                "REPLACE BACKGROUND  ·  EXPAND IMAGE")
    left = photo_card(BG_AFTER, loc("NEW BACKGROUND", "替换背景"), 330, 510)
    right = photo_card(EXPAND_AFTER, loc("EXPANDED", "扩图后"), 330, 510)
    a = promo.ease(t / .5)
    promo.put(image, promo.shadow(left.size), (1000, 220), a)
    promo.put(image, left, (1060, 280 + 18 * (1 - a)), a)
    promo.put(image, promo.shadow(right.size), (1400, 220), a)
    promo.put(image, right, (1460, 280 + 18 * (1 - a)), a)
    return image


def configure(lang):
    promo.OUT = HERE
    promo.LANG = lang
    promo.DURATION = DURATION
    promo.ending = ending_with_cta
    promo.SCENES = [
        (0.0, intro_scene),
        (4.0, background_scene),
        (12.0, expand_scene),
        (20.0, widget_scene),
        (25.0, ending_with_cta),
    ]


def make_audio(lang):
    output = HERE / f"soundtrack-{lang}.wav"
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-stream_loop", "-1", "-i", str(SOURCE_AUDIO), "-t", str(DURATION),
        "-af", "afade=t=out:st=29:d=1", "-c:a", "pcm_s16le", str(output),
    ], check=True)
    return output


def make_storyboard(lang):
    times = (2.0, 8.0, 11.0, 16.0, 22.5, 28.0)
    board = Image.new("RGB", (1920, 1080), (10, 11, 15))
    draw = ImageDraw.Draw(board)
    for index, timestamp in enumerate(times):
        frame = promo.frame(timestamp).resize((640, 360), Image.Resampling.LANCZOS)
        x, y = (index % 3) * 640, (index // 3) * 540
        board.paste(frame, (x, y))
        draw.text((x + 18, y + 374), f"{timestamp:04.1f}s", fill=(156, 157, 166))
    board.save(HERE / f"storyboard-{lang}.jpg", quality=94)
    promo.frame(28.0).save(HERE / f"poster-{lang}.jpg", quality=95)


def render(lang):
    configure(lang)
    make_storyboard(lang)
    audio = make_audio(lang)
    output = HERE / f"glance-social-promo-30s-{lang}.mp4"
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{promo.W}x{promo.H}",
        "-r", str(FPS), "-i", "pipe:0", "-i", str(audio),
        "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "medium",
        "-crf", "17", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
        "-t", str(DURATION), "-movflags", "+faststart", str(output),
    ]
    encoder = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert encoder.stdin is not None
    try:
        for index in range(FPS * DURATION):
            encoder.stdin.write(promo.frame(index / FPS).tobytes())
            if index % 150 == 0:
                print(f"{lang}: rendered {index}/{FPS * DURATION} frames", flush=True)
    finally:
        encoder.stdin.close()
    if encoder.wait() != 0:
        raise RuntimeError(f"Video encoding failed: {output}")
    print(output, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", choices=("en", "zh"), required=True)
    render(parser.parse_args().lang)
