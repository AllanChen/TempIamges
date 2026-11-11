"""小红书 cover, 1080x1440 (3:4). Run with the repo venv; writes social/xiaohongshu-cover.jpg."""
from pathlib import Path
import sys

from PIL import Image

OUT = Path(__file__).resolve().parent
sys.argv = [sys.argv[0], '--lang', 'zh']
import importlib.util
spec = importlib.util.spec_from_file_location('v', OUT / 'vertical.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
h, g, ui = v.h, v.g, v.ui

CW, CH = 1080, 1440


def main():
    bg = h.BG.resize((CH * 16 // 9, CH)).crop(((CH * 16 // 9 - CW) // 2, 0, (CH * 16 // 9 + CW) // 2, CH)).convert('RGBA')
    im = bg.copy()
    # Tag: make "Mac computer app" impossible to miss.
    label = 'Mac 电脑软件'
    w = round(h.tw(label, 40, 's')) + 70
    h.rr(im, (60, 64, 60 + w, 64 + 76), 38, fill=h.WARM)
    h.txt(im, (60 + w / 2, 102), label, 40, h.INK, 's', 'mm')
    put_logo = ui.rounded(g.LOGO, (76, 76), 20)
    im.alpha_composite(put_logo, (CW - 60 - 76 - 170, 64))
    h.txt(im, (CW - 60, 102), 'Glance', 44, h.WHITE, 's', 'rm', 'en')
    h.txt(im, (60, 250), 'Mac 看图神器', 128, h.WHITE, 's', 'lm')
    h.txt(im, (60, 410), '右键就能 AI 修图', 104, h.WARM, 's', 'lm')
    h.txt(im, (64, 525), '看图 · 对比 · 去背景 · 扩图 · 高清放大', 36, h.GRAY, 'r', 'lm')
    # Product shot: the background-removal moment from the video, menu included.
    src = h.frame(18 + 1.75)
    v.paste_scaled(im, src, v.SHOT_BOX, CW, 590)
    im.convert('RGB').save(OUT / 'social/xiaohongshu-cover.jpg', quality=94)


if __name__ == '__main__':
    main()
