"""Glance intro video (~40 s): AI workflow pain -> just right-click.

Run from the repo root: .venv/bin/python design/marketing/videos/glance-ai-intro-43s/render.py --lang en|zh [--preview]
Reuses Glance UI exports and sample photos from the Glance repo. Product animation,
not a screen recording. Needs Pillow, NumPy and ffmpeg.
"""
from pathlib import Path
from functools import lru_cache
import argparse
import importlib.util
import math
import multiprocessing as mp
import subprocess
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

OUT = Path(__file__).resolve().parent
REPO = OUT.parents[3]
BRAND = REPO / 'design/marketing/brand-assets'
spec = importlib.util.spec_from_file_location('tutorial', REPO / 'design/marketing/videos/glance-upscale-tutorial/render.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)

W, H, FPS = 1920, 1080, 30
WHITE, WARM, GRAY, GREEN, INK = ui.WHITE, ui.WARM, ui.GRAY, ui.GREEN, ui.INK
DIM = (120, 115, 112)
RED = (226, 112, 98)
BG = ui.BG
ease, smooth, clamp, lerp, put, rr = ui.ease, ui.smooth, ui.clamp, ui.lerp, ui.put, ui.rrect
LANG = 'en'


def L(en, zh):
    return en if LANG == 'en' else zh


# ---------- fonts ----------
SF = '/System/Library/Fonts/SFNS.ttf'
import glob
PF = (glob.glob('/System/Library/AssetsV2/**/PingFang.ttc', recursive=True) or [ui.PF])[0]
PF_INDEX = {'r': 3, 'm': 7, 's': 11, 'b': 11}
SF_NAME = {'r': b'Regular', 'm': b'Medium', 's': b'Semibold', 'b': b'Bold'}


@lru_cache(None)
def font(size, w='r', fam=None):
    fam = fam or ('en' if LANG == 'en' else 'zh')
    if fam == 'mono':
        return ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', size)
    if fam == 'en':
        f = ImageFont.truetype(SF, size)
        f.set_variation_by_name(SF_NAME[w])
        return f
    return ImageFont.truetype(PF, size, index=PF_INDEX[w])


def txt(im, xy, s, size, color=WHITE, w='r', anchor=None, fam=None):
    ImageDraw.Draw(im).text(xy, s, font=font(size, w, fam), fill=color, anchor=anchor)


def tw(s, size, w='r', fam=None):
    return font(size, w, fam).getlength(s)


# ---------- source images ----------
def rgb(name):
    return Image.open(BRAND / name).convert('RGB')


PORTRAIT = rgb('clipboard-DA224852-373C-472B-A405-9260B85880B6.png')
PARK = rgb('clipboard-DA224852-373C-472B-A405-9260B85880B6.Remove Objects.png')
CUTOUT = Image.open(OUT / 'assets/cutout-birefnet-portrait.png').convert('RGBA')
PARIS = rgb('Screenshot 2026-11-06 at 10.52.24.png')
PARIS_WIDE = rgb('Screenshot 2026-11-06 at 10.52.24.Expand.png')
LAKE = rgb('glance-alpine-before.png').crop((0, 60, 1086, 1300))
LAKE_SOFT = ui.soften(LAKE, 4.2).filter(ImageFilter.GaussianBlur(1.2))
LOGO = ui.logo
FOCUS = ui.focus


def checker(size, cell=22):
    im = Image.new('RGB', size, (228, 228, 230))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(196, 196, 200))
    return im


CUTOUT_VIEW = checker(CUTOUT.size)
CUTOUT_VIEW = CUTOUT_VIEW.convert('RGBA')
CUTOUT_VIEW.alpha_composite(CUTOUT)
CUTOUT_VIEW = CUTOUT_VIEW.convert('RGB')

# ---------- Glance window (Image Inspect) ----------
WIN = (1180, 1012)
TOOLBAR = FOCUS.crop((640, 23, 914, 79))
_m = Image.new('L', TOOLBAR.size)
ImageDraw.Draw(_m).rounded_rectangle((0, 0, TOOLBAR.width - 1, TOOLBAR.height - 1), 14, fill=255)
TOOLBAR.putalpha(_m)


@lru_cache(None)
def fill_layers(key):
    img = SOURCES[key]
    bg = ImageOps.fit(img, WIN, method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(38))
    bg = Image.blend(bg, Image.new('RGB', WIN, (12, 12, 15)), .35)
    fit = ImageOps.contain(img, (WIN[0], WIN[1]), method=Image.Resampling.LANCZOS)
    return bg, fit


SOURCES = {'portrait': PORTRAIT, 'cutout': CUTOUT_VIEW, 'park': PARK, 'paris': PARIS,
           'paris_wide': PARIS_WIDE, 'lake_soft': LAKE_SOFT, 'lake': LAKE}


ZOOM_BIG = PARIS_WIDE.resize((1568, 2048), Image.Resampling.LANCZOS)
ZOOM_ORIG = PARIS.resize((784, 1032), Image.Resampling.LANCZOS)


def zoom_source(q):
    """Expanded result, camera pulling back from the original framing (2x)."""
    q = round(q, 3)
    key = f'zoom{q}'
    if key not in SOURCES:
        big = ZOOM_BIG.copy()
        k = 1 - clamp((q - .7) / .3)
        if k > 0:
            layer = ZOOM_ORIG.convert('RGBA')
            layer.putalpha(round(255 * k))
            big = big.convert('RGBA'); big.alpha_composite(layer, (392, 508)); big = big.convert('RGB')
        z = lerp(2, 1, q)
        w, h = 1568 / z, 2048 / z
        SOURCES[key] = big.crop((round(784 - w / 2), round(1024 - h / 2), round(784 + w / 2), round(1024 + h / 2)))
    return key


def window(before, after=None, q=0, mode='wipe', tiles=(), running=0):
    """Glance window showing `before`, revealing `after` by wipe or fade amount q."""
    if after and mode == 'zoom':
        before, after, q = zoom_source(q), None, 0
    bg, fit = fill_layers(before)
    im = bg.copy().convert('RGBA')
    x0 = (WIN[0] - fit.width) // 2
    im.paste(fit, (x0, (WIN[1] - fit.height) // 2))
    if after and q > 0:
        bg2, fit2 = fill_layers(after)
        im2 = bg2.copy().convert('RGBA')
        im2.paste(fit2, ((WIN[0] - fit2.width) // 2, (WIN[1] - fit2.height) // 2))
        if mode == 'fade':
            im = Image.blend(im, im2, q)
        else:
            split = round(WIN[0] * (1 - q))
            im.paste(im2.crop((split, 0, WIN[0], WIN[1])), (split, 0))
            if 0 < q < 1:
                ImageDraw.Draw(im).line((split, 0, split, WIN[1]), fill=WARM, width=5)
    d = ImageDraw.Draw(im)
    for j, c in enumerate([(237, 106, 94), (245, 191, 79), (98, 197, 84)]):
        d.ellipse((20 + j * 26, 17, 34 + j * 26, 31), fill=c)
    put(im, TOOLBAR, ((WIN[0] - TOOLBAR.width) // 2, 23))
    # Filmstrip
    strip = Image.new('RGBA', (WIN[0], 119), (22, 22, 26, 205))
    im.alpha_composite(strip, (0, WIN[1] - 119))
    n = len(tiles)
    if n:
        x = round(WIN[0] / 2 - (94 + 106 * (n - 1)) / 2)
        for i, (kind, key, badge) in enumerate(tiles):
            base = {'sel': ui.tile_sel, 'plain': ui.tile_plain}[kind].copy()
            put(base, ui.rounded(SOURCES[key], (82, 82), 6), (6, 6))
            if badge == 'NEW':
                put(base, ui.badge_new, (49, 66))
            elif badge:
                rr(base, (46, 66, 91, 88), 5, fill=(16, 32, 24))
                txt(base, (68, 77), badge, 12, GREEN, 's', 'mm', 'en')
            put(im, base, (x + 106 * i, WIN[1] - 106))
    if running:
        glow = Image.new('RGBA', WIN)
        rr(glow, (8, 8, WIN[0] - 8, WIN[1] - 8), 16, outline=(*WARM, 255), width=8)
        put(im, glow.filter(ImageFilter.GaussianBlur(16)), (0, 0), .35 * running)
        line = Image.new('RGBA', WIN)
        rr(line, (6, 6, WIN[0] - 6, WIN[1] - 6), 16, outline=(*WARM, 220), width=3)
        put(im, line, (0, 0), running)
    return im


WX, WY, WS = 812, 150, 0.84          # window placement / scale on the video frame
WW, WH = round(WIN[0] * WS), round(WIN[1] * WS)


def place_window(im, layer, alpha=1, dy=0):
    layer = layer.resize((WW, WH), Image.Resampling.LANCZOS)
    m = Image.new('L', layer.size)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, WW - 1, WH - 1), 18, fill=255)
    layer.putalpha(ImageChops_multiply(layer.getchannel('A'), m))
    put(im, ui.shadow((WW, WH), 28, 170), (WX - 60, WY - 60 + dy), alpha)
    put(im, layer, (WX, WY + dy), alpha)
    ImageDraw.Draw(im)


def ImageChops_multiply(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a, b)


# ---------- context menu ----------
ROW, MW, SW = 40, 300, 420
MAIN = [('Widget', True, ''), None, (L('Copy Image', '复制图片'), False, '⌘C'), (L('Edit', '编辑'), True, ''),
        (L('Export', '导出'), True, ''), (L('Tools', '工具'), True, ''), None,
        (L('Show in Finder', '在 Finder 中显示'), False, ''), (L('Image Info', '图片信息'), False, '⌘I')]
WIDGETS = [('bgpro', L('Background Remover Pro', '人物背景分离')), ('upscale', L('Upscale', '高清放大')),
           ('redraw', L('Redraw & Reframe', '图生图')), ('objects', L('Remove Objects', '移除物体')),
           ('outfit', L('Outfit Swap', 'AI 换装')), ('expand', L('Expand Image', '智能扩图')),
           ('watermark', L('Watermark Remover', '图片去水印')), ('prompt', L('Image to Prompt', '图片转提示词')),
           ('host', L('Free Image Host', '免费图床'))]


def menu_panel(rows, width, hl=None, header=None):
    h = 16 + (44 if header else 0) + sum(14 if r is None else ROW for r in rows)
    p = Image.new('RGBA', (width, h))
    rr(p, (0, 0, width - 1, h - 1), 14, fill=(21, 21, 25, 250), outline=(243, 238, 232, 34))
    y = 8
    if header:
        txt(p, (22, y + 20), header, 17, GRAY, 'r', 'lm')
        y += 44
    for i, r in enumerate(rows):
        if r is None:
            ImageDraw.Draw(p).line((16, y + 7, width - 16, y + 7), fill=(243, 238, 232, 30), width=1)
            y += 14
            continue
        label, sub, short = r
        on = hl == i
        if on:
            rr(p, (8, y + 2, width - 9, y + ROW - 2), 8, fill=WARM)
        col = INK if on else WHITE
        txt(p, (24, y + ROW / 2), label, 21, col, 'm' if on else 'r', 'lm')
        if sub:
            txt(p, (width - 22, y + ROW / 2), '›', 24, col, 'm', 'rm', 'en')
        elif short:
            txt(p, (width - 22, y + ROW / 2), short, 18, INK if on else GRAY, 'r', 'rm', 'en')
        y += ROW
    return p


def widget_rows():
    return [(name, False, '') for _, name in WIDGETS] + [None, (L('Widget Market…', 'Widget 市场…'), True, '')]


def draw_menus(im, origin, target, t):
    """Right-click menu sequence starting at local time t (0 = right click)."""
    ox, oy = origin
    a_main = ease(t / .14)
    if a_main <= 0:
        return
    main = menu_panel(MAIN, MW, hl=0 if t > .22 else None)
    put(im, ui.shadow(main.size, 20, 150), (ox - 60, oy - 60), a_main)
    put(im, main, (ox, oy), a_main)
    a_sub = ease((t - .25) / .15)
    if a_sub <= 0:
        return
    idx = [k for k, _ in WIDGETS].index(target)
    hop = clamp((t - .4) / .5)
    cur = round(lerp(0, idx, smooth(hop))) if t > .4 else None
    sub = menu_panel(widget_rows(), SW, hl=cur, header=L('Installed', '已安装'))
    sx, sy = ox + MW - 6, oy - 8
    put(im, ui.shadow(sub.size, 20, 150), (sx - 60, sy - 60), a_sub)
    put(im, sub, (sx, sy), a_sub)
    return (sx, sy, idx)


def menu_alpha_cursor(t, origin, target):
    """Cursor position for the menu sequence."""
    ox, oy = origin
    idx = [k for k, _ in WIDGETS].index(target)
    sx, sy = ox + MW - 6, oy - 8
    p_widget = (ox + 120, oy + 8 + ROW / 2)
    p_item = (sx + 170, sy + 8 + 44 + idx * ROW + ROW / 2)
    if t < .22:
        return ui.move(origin, p_widget, t / .22)
    if t < .4:
        return p_widget
    return ui.move(p_widget, p_item, (t - .4) / .5)


# ---------- layout pieces ----------
def header(im, tag=''):
    put(im, ui.rounded(LOGO, (50, 50), 14), (92, 46))
    txt(im, (158, 72), 'Glance', 30, WHITE, 's', 'lm', 'en')
    if tag:
        txt(im, (1828, 72), tag, 20, GRAY, 'm', 'rm')


def footnote(im, s):
    txt(im, (1828, 1036), s, 17, (118, 113, 110), 'r', 'rm')


def copy_block(im, first, second, detail=None, a=1, x=108, y=360, size=None):
    size = size or (84 if LANG == 'en' else 82)
    layer = Image.new('RGBA', (720, 560))
    txt(layer, (0, 0), first, size, WHITE, 'b' if LANG == 'en' else 's')
    txt(layer, (0, size * 1.3), second, size, WARM, 'b' if LANG == 'en' else 's')
    if detail:
        txt(layer, (4, size * 2.9), detail, 26, GRAY, 'r')
    put(im, layer, (x, y + 24 * (1 - a)), a)


def step_path(im, label, a):
    s = f"{L('Right-click', '右键')}  →  Widget  →  {label}"
    w = tw(s, 23, 'm') + 44
    p = Image.new('RGBA', (round(w), 52))
    rr(p, (0, 0, round(w) - 1, 51), 14, fill=(38, 30, 27), outline=(118, 86, 66))
    txt(p, (22, 26), s, 23, WARM, 'm', 'lm')
    put(im, p, (110, 760 + 14 * (1 - a)), a)


def done_badge(im, s, a):
    w = round(tw(s, 23, 'm')) + 60
    p = Image.new('RGBA', (w, 52))
    rr(p, (0, 0, w - 1, 51), 14, fill=(20, 34, 28, 240), outline=(70, 120, 96))
    txt(p, (w / 2, 26), '✓  ' + s, 23, GREEN, 'm', 'mm')
    put(im, p, (WX + WW - w - 24, WY + 24 + 10 * (1 - a)), a)


def panel(size, title=None):
    p = Image.new('RGBA', size)
    rr(p, (0, 0, size[0] - 1, size[1] - 1), 26, fill=(22, 23, 28), outline=(68, 62, 60), width=2)
    d = ImageDraw.Draw(p)
    for j, c in enumerate([(210, 103, 92), (216, 172, 86), (113, 170, 120)]):
        d.ellipse((26 + j * 26, 24, 40 + j * 26, 38), fill=c)
    if title:
        txt(p, (size[0] / 2, 31), title, 18, GRAY, 'm', 'mm')
    return p


def place_card(im, p, x, y, a=1):
    put(im, ui.shadow(p.size, 26, 160), (x - 60, y - 60), a)
    put(im, p, (x, y), a)


# ---------- scene 1: the pain ----------
def pain_question(im, a):
    txt(im, (110, 260), L('Just want AI to edit one photo?', '只是想用 AI 修一张图？'), 36, GRAY, 'm')


def pain_workflow(t):
    im = BG.copy(); header(im)
    pain_question(im, 1)
    copy_block(im, L('Build a workflow', '先搭一套'), L('node by node?', '工作流？'), a=ease(t / .25))
    p = panel((1000, 640), L('workflow.json', '工作流.json'))
    d = ImageDraw.Draw(p)
    for x in range(24, 1000, 28):
        for y in range(70, 640, 28):
            d.ellipse((x, y, x + 2, y + 2), fill=(50, 47, 49))
    nodes = [(40, 260, L('Load Image', '加载图片')), (270, 110, L('Load Model', '加载模型')),
             (270, 420, L('Settings', '配置参数')), (520, 260, L('Sampler', '采样器')),
             (770, 120, L('Save Image', '保存图片')), (770, 430, L('Custom Node', '自定义节点'))]
    edges = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (5, 3), (2, 5)]
    for j, (a_, b_) in enumerate(edges):
        x, y, _ = nodes[a_]; X, Y, _ = nodes[b_]
        path = [(x + 180, y + 40), (x + 210, y + 40), (X - 30, Y + 40), (X, Y + 40)]
        d.line(path, fill=(122, 89, 71), width=3, joint='curve')
        q = (t * .8 + j * .17) % 1
        px = sum(c * pt[0] for c, pt in zip(((1-q)**3, 3*(1-q)**2*q, 3*(1-q)*q*q, q**3), path))
        py = sum(c * pt[1] for c, pt in zip(((1-q)**3, 3*(1-q)**2*q, 3*(1-q)*q*q, q**3), path))
        d.ellipse((px - 5, py - 5, px + 5, py + 5), fill=WARM)
    for j, (x, y, label) in enumerate(nodes):
        broken = j == 5 and int(t * 4) % 2 == 0
        rr(p, (x, y, x + 180, y + 80), 12, fill=(36, 34, 37), outline=RED if broken else (92, 76, 68), width=2)
        rr(p, (x, y, x + 6, y + 80), 3, fill=RED if j == 5 else WARM)
        txt(p, (x + 92, y + 40), label, 22, WHITE, 'm', 'mm')
    rr(p, (300, 560, 700, 612), 12, fill=(64, 34, 32))
    txt(p, (500, 586), L('⚠  Missing node: install it first', '⚠  缺少节点，请先安装'), 21, (238, 150, 130), 'm', 'mm')
    place_card(im, p, 820, 220 + 18 * (1 - ease(t / .3)))
    return im


def pain_gpu(t):
    im = BG.copy(); header(im)
    pain_question(im, 1)
    copy_block(im, L('No GPU?', '没有显卡？'), L('Out of memory.', '显存不够。'), a=ease(t / .25))
    p = panel((1000, 640), L('Local AI model', '本地 AI 模型'))
    # Chip icon with a cross.
    cx, cy = 500, 230
    rr(p, (cx - 110, cy - 80, cx + 110, cy + 80), 18, fill=(40, 38, 42), outline=(110, 96, 90), width=3)
    d = ImageDraw.Draw(p)
    for k in range(6):
        x = cx - 90 + k * 36
        d.line((x, cy - 100, x, cy - 82), fill=(110, 96, 90), width=5)
        d.line((x, cy + 82, x, cy + 100), fill=(110, 96, 90), width=5)
    txt(p, (cx, cy), 'GPU', 54, (150, 140, 136), 'b', 'mm', 'en')
    k = ease((t - .3) / .25)
    if k > 0:
        d.line((cx - 140, cy - 110, cx - 140 + 280 * k, cy - 110 + 220 * k), fill=RED, width=10)
    lines = [L('Requires a GPU with 12 GB+ memory', '需要 12 GB 以上显存的显卡'),
             'RuntimeError: out of memory',
             L('Estimated time on CPU: 47 min', 'CPU 预计耗时：47 分钟')]
    for i, s in enumerate(lines):
        a = ease((t - .35 - i * .22) / .2)
        if a > 0:
            layer = Image.new('RGBA', (900, 50))
            txt(layer, (450, 25), s, 26, RED if i == 1 else WHITE, 'm', 'mm', 'mono' if i == 1 else None)
            put(p, layer, (50, 390 + i * 62), a)
    place_card(im, p, 820, 220)
    return im


TERM = ['$ pip install -r requirements.txt', 'Collecting torch==2.3.1 (2.1 GB)',
        'ERROR: Could not build wheels', '$ git clone …/custom-nodes', '$ python main.py',
        'ModuleNotFoundError: No module named …', '$ pip install --upgrade …', 'ERROR: version conflict', '$ python main.py']


def pain_setup(t):
    im = BG.copy(); header(im)
    pain_question(im, 1)
    copy_block(im, L('Install. Debug.', '安装、调试、'), L('Try again?', '再重来？'), a=ease(t / .25))
    p = panel((1000, 640), 'Terminal')
    rr(p, (22, 62, 977, 618), 14, fill=(13, 14, 17))
    shown = min(len(TERM), int(t * 6.5) + 2)
    start = max(0, shown - 8)
    for i, s in enumerate(TERM[start:shown]):
        col = RED if s.startswith(('ERROR', 'Module')) else ((230, 225, 220) if s.startswith('$') else GRAY)
        txt(p, (50, 92 + i * 62), s, 25, col, 'r', 'lm', 'mono')
    if int(t * 3) % 2 == 0:
        rr(p, (50, 92 + (shown - start) * 62 - 16, 64, 92 + (shown - start) * 62 + 16), 2, fill=WHITE)
    place_card(im, p, 820, 220)
    return im


def reveal(t):
    im = BG.copy()
    a = ease(t / .3)
    txt(im, (960, 360), L('There is an easier way.', '换个简单的方式。'), 44, GRAY, 'm', 'mm')
    layer = Image.new('RGBA', (W, 300))
    icon = ui.rounded(LOGO, (124, 124), 32)
    word = 'Glance'
    tw_ = tw(word, 140, 'b', 'en')
    x0 = 960 - (124 + 36 + tw_) / 2
    put(layer, icon, (x0, 88))
    txt(layer, (x0 + 160, 150), word, 140, WHITE, 'b', 'lm', 'en')
    put(im, layer, (0, 380 + 20 * (1 - a)), a)
    b = ease((t - .55) / .3)
    if b > 0:
        layer = Image.new('RGBA', (W, 120))
        txt(layer, (960, 60), L('Just right-click.', '右键一下就行。'), 64, WARM, 's', 'mm')
        put(im, layer, (0, 730 + 14 * (1 - b)), b)
    return im


# ---------- right-click demos ----------
DEMO_TIMING = dict(enter=.0, click=.75, menu=1.0, pick=2.05, run=2.2, reveal=2.75, done=3.6)


def demo_scene(spec):
    def scene(t):
        im = BG.copy(); header(im)
        T = DEMO_TIMING
        extra = spec.get('prompt_time', 0)
        a = ease(t / .3)
        copy_block(im, spec['first'], spec['second'], spec.get('detail'), a)
        step_path(im, spec['menu_label'], ease((t - .3) / .3))
        run_start = T['run'] + extra
        rev_start = T['reveal'] + extra
        running = 0
        if run_start <= t < rev_start + .2:
            running = (.55 + .45 * math.sin((t - run_start) * 9) ** 2) * clamp((rev_start + .2 - t) / .2)
        q = smooth((t - rev_start) / spec.get('reveal_dur', .85))
        tiles = (('sel', spec['before'], None),)
        if t >= run_start and q < 1:
            pct = round(12 + 87 * clamp((t - run_start) / (rev_start - run_start)))
            tiles = (('sel', spec['before'], f'{min(99, pct)}%'),)
        if q >= 1:
            tiles = (('plain', spec['before'], None), ('sel', spec['after'], 'NEW'))
        layer = window(spec['before'], spec['after'], q, spec.get('mode', 'wipe'), tiles, running)
        place_window(im, layer, a, 20 * (1 - a))
        origin = spec.get('origin', (1120, 360))
        tm = t - T['click']
        if T['click'] <= t < T['pick'] + .15:
            draw_menus(im, origin, spec['widget'], tm * (1.0 / .95))
        # Optional prompt popover (Remove Objects asks what to remove).
        if extra and T['pick'] <= t < run_start + .1:
            pa = ease((t - T['pick']) / .15) * clamp((run_start + .1 - t) / .1)
            pop = Image.new('RGBA', (560, 170))
            rr(pop, (0, 0, 559, 169), 16, fill=(24, 24, 29, 250), outline=(243, 238, 232, 40))
            txt(pop, (26, 34), L('What to remove?', '要移除什么？'), 21, GRAY, 'm', 'lm')
            rr(pop, (22, 62, 400, 112), 10, fill=(14, 14, 17), outline=(90, 80, 74))
            typed = spec['prompt'][:max(0, int((t - T['pick'] - .1) * 28))]
            txt(pop, (40, 87), typed, 23, WHITE, 'r', 'lm', 'en')
            rr(pop, (414, 62, 538, 112), 10, fill=WARM)
            txt(pop, (476, 87), L('Run', '运行'), 22, INK, 's', 'mm')
            txt(pop, (26, 140), L('Uses AI to fill the background', 'AI 自动补全背景'), 17, DIM, 'r', 'lm')
            put(im, ui.shadow(pop.size, 20, 150), (1060 - 60, 430 - 60), pa)
            put(im, pop, (1060, 430), pa)
        # Cursor
        if t < T['click']:
            cx, cy = ui.move((1500, 760), origin, (t - .25) / .5)
            pulse = 0
        elif t < T['pick'] + .15:
            cx, cy = menu_alpha_cursor(tm * (1.0 / .95), origin, spec['widget'])
            pulse = clamp(tm / .35) if tm < .35 else (clamp((t - T['pick']) / .3) if t > T['pick'] else 0)
        elif extra and t < run_start + .1:
            cx, cy = ui.move((1300, 600), (1536, 517), (t - T['pick'] - .15) / .5)
            pulse = clamp((t - run_start + .25) / .3) if t > run_start - .25 else 0
        else:
            cx, cy = None, None
        if cx is not None:
            ui.cursor(im, round(cx), round(cy), pulse)
        if t >= rev_start + .8:
            done_badge(im, spec['done'], ease((t - rev_start - .8) / .25))
        footnote(im, spec.get('note', L('Product animation · example result', '产品动效示意 · 示例效果')))
        return im
    return scene


DEMOS = [
    dict(widget='bgpro', before='portrait', after='cutout',
         first=L('Remove the', '一键'), second=L('background.', '去掉背景。'),
         menu_label=L('Background Remover Pro', '人物背景分离'), done=L('Background removed', '背景已移除'),
         detail=L('Hair and edges stay clean.', '发丝边缘，也干净利落。')),
    dict(widget='objects', before='portrait', after='park', prompt_time=1.1, prompt='city, people',
         first=L('Same pose.', '人还是那个人，'), second=L('New scene.', '换个场景。'),
         menu_label=L('Remove Objects', '移除物体'), done=L('Done', '已完成'),
         detail=L('Keep the person. Change the world.', '保留人物，背景焕然一新。')),
    dict(widget='expand', before='paris', after='paris_wide', mode='zoom', reveal_dur=1.1,
         first=L('Need more room?', '画面太窄？'), second=L('Expand it.', '向外扩展。'),
         menu_label=L('Expand Image', '智能扩图'), done=L('Image expanded', '扩图完成'),
         detail=L('AI fills in beyond the edges.', 'AI 补全画面之外的内容。')),
    dict(widget='upscale', before='lake_soft', after='lake',
         first=L('Blurry photo?', '图片模糊？'), second=L('Make it sharp.', '高清放大。'),
         menu_label=L('Upscale', '高清放大'), done=L('Upscaled', '放大完成'),
         detail=L('More pixels, finer detail.', '分辨率更高，细节更清晰。'),
         note=L('Product animation · quality illustration', '产品动效示意 · 画质效果示意')),
]


# ---------- more tools ----------
MORE = [('outfit', L('Outfit Swap', 'AI 换装'), L('Try on any outfit', '一键换上新衣服')),
        ('watermark', L('Watermark Remover', '图片去水印'), L('Clean up marks and text', '去除水印和文字')),
        ('video', L('Video Watermark Remover', '视频去水印'), L('Clean up videos too', '视频也能去水印')),
        ('redraw', L('Redraw & Reframe', '图生图'), L('New ratio, new image', '换画幅重新生成')),
        ('prompt', L('Image to Prompt', '图片转提示词'), L('Turn a picture into words', '把图片变成提示词')),
        ('host', L('Free Image Host', '免费图床'), L('Get a shareable link', '一键获得分享链接'))]


def more_tools(t):
    im = BG.copy(); header(im)
    copy_block(im, L('And much more.', '还有更多。'), L('One right-click away.', '都在右键里。'),
               L('Install new tools from the Widget Market.', '在 Widget 市场随时添加新工具。'), ease(t / .3),
               y=380, size=68 if LANG == 'en' else 76)
    for i, (_, name, desc) in enumerate(MORE):
        col, row = i % 2, i // 2
        x, y = 860 + col * 500, 230 + row * 200
        a = ease((t - .25 - i * .12) / .3)
        if a <= 0:
            continue
        c = Image.new('RGBA', (470, 170))
        rr(c, (0, 0, 469, 169), 22, fill=(26, 26, 31), outline=(74, 66, 62), width=2)
        rr(c, (28, 30, 40, 42), 4, fill=WARM)
        txt(c, (56, 36), name, 28, WHITE, 's', 'lm')
        txt(c, (30, 100), desc, 22, GRAY, 'r', 'lm')
        place_card(im, c, x, y + 20 * (1 - a), a)
    return im


# ---------- the promise ----------
def promise(t):
    im = BG.copy(); header(im)
    items = [L('No workflows to build.', '不用搭工作流。'), L('No GPU needed.', '不用显卡。'),
             L('Nothing to install or debug.', '不用装环境、调参数。')]
    for i, s in enumerate(items):
        a = ease((t - i * .35) / .3)
        if a <= 0:
            continue
        layer = Image.new('RGBA', (1300, 100))
        ImageDraw.Draw(layer).ellipse((0, 18, 64, 82), fill=(20, 40, 32), outline=GREEN, width=3)
        txt(layer, (32, 51), '✓', 36, GREEN, 'b', 'mm', 'en')
        txt(layer, (100, 50), s, 58, WHITE, 's', 'lm')
        put(im, layer, (420, 250 + i * 130 + 16 * (1 - a)), a)
    b = ease((t - 1.3) / .35)
    if b > 0:
        layer = Image.new('RGBA', (1300, 140))
        txt(layer, (100, 70), L('Open the image. Right-click. Done.', '打开图片，右键，搞定。'), 60, WARM, 'b' if LANG == 'en' else 's', 'lm')
        put(im, layer, (420, 680 + 14 * (1 - b)), b)
    return im


# ---------- bonus: Option + Space ----------
def bonus(t):
    im = BG.copy(); header(im)
    a = ease(t / .3)
    txt(im, (110, 300), L('BONUS', '彩蛋'), 26, WARM, 's')
    copy_block(im, L('See a file path?', '看到文件路径？'), L('⌥ Space to open it.', '一按就打开。'),
               L('Select a path in any app and press\nOption + Space. Glance shows it instantly.',
                 '在任何应用里选中路径，按 Option + 空格，\nGlance 马上帮你打开。'), a, y=360, size=72)
    # Chat/terminal-ish panel with a selected path.
    p = panel((960, 300), L('Any app', '任意应用'))
    txt(p, (50, 120), L('Here is the photo:', '照片在这里：'), 26, GRAY, 'r', 'lm')
    sel = ease((t - .35) / .3)
    path = '~/Pictures/alpine-lake.jpg'
    pw = tw(path, 28, 'r', 'mono')
    rr(p, (46, 170, 46 + (pw + 16) * sel, 222), 8, fill=(78, 56, 42))
    txt(p, (54, 196), path, 28, WARM, 'r', 'lm', 'mono')
    place_card(im, p, 840, 150, a)
    k = clamp((t - .9) / .2) * clamp((1.5 - t) / .3) if t < 1.5 else 0
    big_key(im, (1150, 478), k)
    pv = ease((t - 1.25) / .35)
    if pv > 0:
        win = window('lake', tiles=(('sel', 'lake', None),)).resize((520, 446), Image.Resampling.LANCZOS)
        m = Image.new('L', win.size)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, 519, 445), 16, fill=255)
        win.putalpha(m)
        s = .85 + .15 * pv
        win = win.resize((round(520 * s), round(446 * s)), Image.Resampling.LANCZOS)
        x, y = 1060 + (520 - win.width) / 2, 586 + (446 - win.height) / 2
        put(im, ui.shadow(win.size, 24, 160), (x - 60, y - 60), pv)
        put(im, win, (x, y), pv)
    return im


def big_key(im, xy, pressed):
    s = 'Option  +  Space'
    w = round(tw(s, 30, 's', 'en')) + 110
    p = Image.new('RGBA', (w, 76))
    rr(p, (0, 0, w - 1, 75), 18, fill=(round(30 + 40 * pressed), round(27 + 22 * pressed), 26), outline=WARM, width=3)
    txt(p, (36, 38), '⌥', 34, WARM, 's', 'lm', 'en')
    txt(p, (80, 38), s, 30, WHITE, 's', 'lm', 'en')
    put(im, p, xy)


# ---------- end card ----------
def ending(t):
    im = BG.copy()
    a = ease(t / .3)
    layer = Image.new('RGBA', (W, H))
    put(layer, ui.rounded(LOGO, (170, 170), 42), (875, 150))
    txt(layer, (960, 440), 'Glance', 140, WHITE, 'b', 'mm', 'en')
    txt(layer, (960, 580), L('AI photo editing. Just right-click.', 'AI 修图，右键就好。'), 58, WARM, 's', 'mm')
    txt(layer, (960, 670), L('An image & video viewer for Mac, with AI built in.', 'Mac 上的看图看视频工具，内置 AI。'), 28, GRAY, 'r', 'mm')
    put(im, layer, (0, 16 * (1 - a)), a)
    b = ease((t - .5) / .35)
    if b > 0:
        cta = Image.new('RGBA', (W, 140))
        s = 'glancepreview.com'
        w = tw(s, 34, 's', 'en') + 90
        rr(cta, (960 - w / 2, 10, 960 + w / 2, 84), 37, fill=WARM)
        txt(cta, (960, 47), s, 34, INK, 's', 'mm', 'en')
        txt(cta, (960, 120), L('14-day free trial · No card needed · macOS', '14 天免费试用 · 无需绑卡 · macOS'), 23, GRAY, 'r', 'mm')
        put(im, cta, (0, 770 + 10 * (1 - b)), b)
    return im


# ---------- timeline ----------
def build_scenes():
    scenes = [(2.2, pain_workflow), (2.2, pain_gpu), (2.3, pain_setup), (2.2, reveal)]
    for d in DEMOS:
        scenes.append((4.5 + d.get('prompt_time', 0), demo_scene(d)))
    scenes += [(3.8, more_tools), (3.2, promise), (3.6, bonus), (4.6, ending)]
    out, at = [], 0
    for dur, fn in scenes:
        out.append((at, dur, fn)); at += dur
    return out, at


SCENES, DURATION = None, None


def frame(t):
    i = max(i for i, s in enumerate(SCENES) if s[0] <= t)
    start, dur, fn = SCENES[i]
    im = fn(t - start)
    fade = .18
    if i > 0 and t - start < fade and i >= 3:
        ps, pd, pf = SCENES[i - 1]
        im = Image.blend(pf(t - ps), im, smooth((t - start) / fade))
    if t > DURATION - .5:
        im = Image.blend(im, Image.new('RGBA', (W, H), (0, 0, 0, 255)), smooth((t - DURATION + .5) / .5) * .9)
    return im.convert('RGB')


# ---------- sound ----------
def soundtrack(path):
    sr = 48000; n = round(sr * DURATION); sig = np.zeros((n, 2))
    rng = np.random.default_rng(7)
    time = np.arange(n) / sr

    def tone(at, dur, hz, amp, soft=False, pan=0):
        b = round(at * sr); c = min(round(dur * sr), n - b)
        if c <= 0: return
        ts = np.arange(c) / sr
        env = (1 - np.exp(-ts / (.18 if soft else .004))) * np.exp(-ts / (2.2 if soft else .3)) * np.clip((dur - ts) / .15, 0, 1)
        v = (np.sin(2 * np.pi * hz * ts) + .15 * np.sin(4 * np.pi * hz * ts)) * env * amp
        sig[b:b + c] += v[:, None] * np.array([1 - pan * .3, 1 + pan * .3])

    def noise(at, dur, amp, sweep=False):
        b = round(at * sr); c = min(round(dur * sr), n - b)
        if c <= 0: return
        ts = np.arange(c) / sr
        v = np.convolve(rng.normal(size=c), np.ones(16) / 16, mode='same')
        v *= (np.sin(np.pi * ts / dur) ** 2 if sweep else np.exp(-ts * 110)) * amp
        sig[b:b + c] += v[:, None]

    reveal_at = SCENES[3][0]
    # Tense, ticking minor pulse during the pain section.
    beat = .3
    k = 0
    while k * beat < reveal_at - .1:
        tone(k * beat, .25, [146.83, 155.56, 164.81][k % 3], .055)
        noise(k * beat, .04, .08)
        k += 1
    for s in SCENES[1:3]:
        noise(s[0] - .2, .25, .12, True)
    noise(reveal_at - .35, .4, .18, True)
    # Warm progression for the rest.
    chords = [(130.81, 164.81, 196.0, 246.94), (110.0, 130.81, 164.81, 196.0),
              (87.31, 110.0, 130.81, 164.81), (98.0, 123.47, 146.83, 196.0)]
    bar, j = 2.4, 0
    at = reveal_at
    while at < DURATION:
        for q, hz in enumerate(chords[j % 4]):
            tone(at, bar + .6, hz, .036, True, (-1) ** q * .4)
        tone(at, .6, chords[j % 4][0] / 2, .05)
        at += bar; j += 1
    # Gentle plucked arpeggio over the main part.
    notes = [523.25, 659.25, 783.99, 659.25]
    at, j = reveal_at, 0
    while at < DURATION - 1.5:
        tone(at, .9, notes[j % 4] * (1 if (j // 8) % 2 == 0 else 1.122), .018)
        at += .6; j += 1
    for at, hz in [(reveal_at + .05, 523.25), (reveal_at + .2, 659.25), (reveal_at + .35, 783.99), (reveal_at + .6, 1046.5)]:
        tone(at, 1.2, hz, .05)
    # UI sounds for each demo: right click, pick, success chime.
    for start, dur, fn in SCENES:
        for d in DEMOS:
            pass
    for i, d in enumerate(DEMOS):
        start = SCENES[4 + i][0]
        extra = d.get('prompt_time', 0)
        T = DEMO_TIMING
        noise(start + T['click'], .05, .3)
        noise(start + T['pick'], .05, .26)
        if extra:
            noise(start + T['run'] + extra - .1, .05, .26)
        noise(start + T['reveal'] + extra, .5, .08, True)
        rv = start + T['reveal'] + extra + .8
        tone(rv, 1.0, 1046.5, .05); tone(rv + .1, 1.0, 1318.5, .045)
    end = SCENES[-1][0]
    for q, hz in enumerate((523.25, 659.25, 783.99, 1046.5)):
        tone(end + .05 + q * .12, 2.5, hz, .05)
    sig *= (np.clip(time / .03, 0, 1) * np.clip((DURATION - time) / 1.2, 0, 1))[:, None]
    sig *= .85 / max(.01, np.max(np.abs(sig)))
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(sr)
        f.writeframes((sig * 32767).astype('<i2').tobytes())


def frame_bytes(i):
    return frame(i / FPS).tobytes()


def previews(tag):
    times = [s[0] + min(s[1] - .3, 3.9) for s in SCENES]
    board = Image.new('RGB', (1920, 270 * math.ceil(len(times) / 4) + 40 * math.ceil(len(times) / 4)), (12, 12, 16))
    for i, t in enumerate(times):
        im = frame(t)
        x, y = (i % 4) * 480, (i // 4) * 310
        board.paste(im.resize((480, 270), Image.Resampling.LANCZOS), (x, y))
        ImageDraw.Draw(board).text((x + 12, y + 278), f'{t:.1f}s', fill=GRAY, font=font(20, 'r', 'en'))
    board.save(OUT / f'storyboard-{tag}.jpg', quality=92)
    frame(SCENES[-1][0] + 3).save(OUT / f'poster-{tag}.jpg', quality=94)


def main():
    global LANG, SCENES, DURATION
    ap = argparse.ArgumentParser()
    ap.add_argument('--lang', default='en', choices=['en', 'zh'])
    ap.add_argument('--preview', action='store_true')
    ap.add_argument('--at', type=float, nargs='*')
    args = ap.parse_args()
    LANG = args.lang
    rebuild_localized()
    SCENES, DURATION = build_scenes()
    print(f'duration {DURATION:.2f}s', flush=True)
    if args.at:
        for t in args.at:
            frame(t).save(OUT / f'check-{LANG}-{t:.1f}.jpg', quality=90)
        return
    previews(LANG)
    if args.preview:
        return
    wav = OUT / f'soundtrack-{LANG}.wav'
    soundtrack(wav)
    out = OUT / f'glance-ai-intro-43s-{LANG}.mp4'
    nframes = round(FPS * DURATION)
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0', '-i', str(wav), '-map', '0:v', '-map', '1:a',
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
           '-b:a', '192k', '-t', f'{DURATION:.3f}', '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(6) as pool:
        for i, data in enumerate(pool.imap(frame_bytes, range(nframes), chunksize=4)):
            enc.stdin.write(data)
            if i % 150 == 0:
                print(f'{i}/{nframes}', flush=True)
    enc.stdin.close()
    if enc.wait():
        raise RuntimeError('encode failed')
    print(out)


def rebuild_localized():
    """Module-level copy uses L(); re-evaluate it after LANG is set."""
    global MAIN, WIDGETS, DEMOS, MORE
    g = globals()
    src = Path(__file__).read_text()
    for name in ('MAIN', 'WIDGETS', 'DEMOS', 'MORE'):
        start = src.index(f'\n{name} = ') + 1
        end = src.index('\n\n', start)
        exec(src[start:end], g)


if __name__ == '__main__':
    main()
