"""Vertical 9:16 cut (1080x1920) of the 30 s intro, for 小红书 / 抖音.

Run from the repo root (after render.py): .venv/bin/python design/marketing/videos/glance-intro-30s/vertical.py --lang zh [--no-url] [--preview] [--at T ...]
Re-composes each 16:9 frame from render.py: headline area on top, product window below.
Uses the soundtracks render.py already wrote (soundtrack-<lang>.wav / soundtrack-<lang>-voice.wav).
"""
from pathlib import Path
import multiprocessing as mp
import subprocess
import sys

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent
sys.argv = [a for a in sys.argv]  # render.py reads --lang from argv at import
import importlib.util
spec = importlib.util.spec_from_file_location('h', OUT / 'render.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
g, ui = h.g, h.ui

VW, VH, FPS, DURATION = 1080, 1920, h.FPS, h.DURATION
BG_V = h.BG.resize((VH * 16 // 9, VH)).crop(((VH * 16 // 9 - VW) // 2, 0, (VH * 16 // 9 + VW) // 2, VH))
CENTERED = {1, 5}               # reveal, ending: centred layouts
COPY_BOX = (60, 240, 755, 840)  # headline column of the 16:9 frame
SHOT_BOX = (760, 120, 1910, 1050)
PAIN_COPY, PAIN_SHOT = (60, 240, 740, 840), (740, 120, 1920, 1050)


@lru_cache(None)
def feather(size, edge=48):
    """Soft-edged mask so the 16:9 background seams disappear."""
    w, h_ = size
    x = np.minimum(np.arange(w), np.arange(w)[::-1]) / edge
    y = np.minimum(np.arange(h_), np.arange(h_)[::-1]) / edge
    m = np.clip(np.minimum.outer(y, x), 0, 1)
    return Image.fromarray(np.uint8(m * 255))


def paste_scaled(dst, src, box, width, y):
    """Scale a 16:9 region into the vertical frame, swapping its background
    gradient for the vertical one so no seam shows."""
    s = width / (box[2] - box[0])
    size = (width, round((box[3] - box[1]) * s))
    crop = np.asarray(src.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    bg_h = np.asarray(h.BG.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    x0, y0 = (VW - width) // 2, round(y)
    region = np.asarray(dst.crop((x0, y0, x0 + size[0], y0 + size[1])).convert('RGB'), np.int16)
    out = np.clip(region + crop - bg_h, 0, 255).astype(np.uint8)
    dst.paste(Image.fromarray(out).convert('RGBA'), (x0, y0))
    return size[1]


def header(im):
    ui_logo = ui.rounded(g.LOGO, (64, 64), 18)
    im.alpha_composite(ui_logo, (60, 70))
    h.txt(im, (142, 102), 'Glance', 40, h.WHITE, 's', 'lm', 'en')
    if not h.NO_URL:
        h.txt(im, (VW - 60, 102), 'glancepreview.com', 26, h.GRAY, 'r', 'rm', 'en')


def vframe(t):
    src = h.frame(t)
    i = max(i for i, s in enumerate(h.SCENES) if s[0] <= t)
    im = BG_V.copy().convert('RGBA')
    if i in CENTERED:
        paste_scaled(im, src, (300, 60, 1620, 1020), VW, 480)
    else:
        header(im)
        copy_box, shot_box = (PAIN_COPY, PAIN_SHOT) if i == 0 else (COPY_BOX, SHOT_BOX)
        paste_scaled(im, src, copy_box, 1000 * (copy_box[2] - copy_box[0]) // 740, 190)
        paste_scaled(im, src, shot_box, VW, 1000)
    return im.convert('RGB')


def frame_bytes(i):
    return vframe(i / FPS).tobytes()


def main():
    tag = h.TAG
    vtag = '-xhs' if h.NO_URL else ''
    args = sys.argv[1:]
    if '--at' in args:
        for t in [float(x) for x in args[args.index('--at') + 1:]]:
            vframe(t).save(OUT / f'vcheck-{h.LANG}-{t:.1f}.jpg', quality=90)
        return
    times = [2.5, 6.8, 9.6, 14.2, 16.6, 19.2, 21.6, 24.6, 27.8]
    board = Image.new('RGB', (360 * 9, 640), (12, 12, 16))
    for k, t in enumerate(times):
        board.paste(vframe(t).resize((360, 640), Image.Resampling.LANCZOS), (360 * k, 0))
    board.save(OUT / f'storyboard-vertical{tag}{vtag}.jpg', quality=90)
    if '--preview' in args:
        return
    out = OUT / f'glance-intro-30s-{h.LANG}-vertical{vtag}.mp4'
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{VW}x{VH}', '-r', str(FPS), '-i', 'pipe:0', '-i', str(OUT / f'soundtrack{tag}.wav'),
           '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'medium', '-crf', '19',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(6) as pool:
        for n, data in enumerate(pool.imap(frame_bytes, range(FPS * DURATION), chunksize=4)):
            enc.stdin.write(data)
            if n % 150 == 0: print(f'{n}/{FPS * DURATION}', flush=True)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('encode failed')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(out), '-i', str(OUT / f'soundtrack{tag}-voice.wav'),
                    '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION),
                    '-movflags', '+faststart', str(OUT / f'glance-intro-30s-{h.LANG}-vertical{vtag}-voice.mp4')], check=True)
    print('done')


if __name__ == '__main__':
    main()
