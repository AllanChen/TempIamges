"""Glance 30 s intro (zh / en): view → compare → fix with AI, one window.

Run from the repo root: .venv/bin/python design/marketing/videos/glance-intro-30s/render.py [--lang zh|en] [--preview] [--at T ...]
Writes glance-intro-30s-<lang>-voice.mp4 (narrated: Tingting / Samantha) and glance-intro-30s-<lang>.mp4 (music only).
Reuses the UI helpers in ../glance-ai-intro-43s/render.py. Product animation, not a screen recording.
"""
from pathlib import Path
import argparse
import importlib.util
import math
import multiprocessing as mp
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('intro', OUT.parent / 'glance-ai-intro-43s/render.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
LANG = sys.argv[sys.argv.index('--lang') + 1] if '--lang' in sys.argv else 'zh'
TAG = f'-{LANG}'
g.LANG = LANG
g.rebuild_localized()
ui = g.ui

W, H, FPS, DURATION = 1920, 1080, 30, 30
WHITE, WARM, GRAY, GREEN, INK, RED = g.WHITE, g.WARM, g.GRAY, g.GREEN, g.INK, g.RED
BG, txt, tw, put, rr = g.BG, g.txt, g.tw, g.put, g.rr
ease, smooth, clamp, lerp = g.ease, g.smooth, g.clamp, g.lerp


def L(en, zh):
    return en if LANG == 'en' else zh

LAKE = g.LAKE
LAKE_WARM = Image.open(g.BRAND / 'glance-alpine-after.png').convert('RGB').crop((0, 60, 1086, 1300))
VOICE_AT = [0.25, 5.2, 8.2, 13.2, 18.3, 25.2]
SRC = g.SOURCES
SRC['lake_warm'] = LAKE_WARM


# ---------- generic pieces ----------
def mac_window(size, title, body=None):
    p = Image.new('RGBA', size)
    rr(p, (0, 0, size[0] - 1, size[1] - 1), 18, fill=(30, 31, 36), outline=(78, 72, 70), width=2)
    rr(p, (2, 2, size[0] - 3, 50), 16, fill=(40, 41, 47))
    d = ImageDraw.Draw(p)
    for j, c in enumerate([(237, 106, 94), (245, 191, 79), (98, 197, 84)]):
        d.ellipse((20 + j * 24, 20, 33 + j * 24, 33), fill=c)
    txt(p, (size[0] / 2, 27), title, 19, GRAY, 'm', 'mm')
    return p


def photo(img, size, r=10):
    return ui.rounded(img, size, r)


def copy(im, a, first, second, detail=None):
    g.copy_block(im, first, second, detail, a, y=350, size=L(68, None))


# ---------- 0–5 s: the pain ----------
THUMBS = [g.LAKE, g.PORTRAIT, g.PARIS, LAKE_WARM, g.PARK, g.PARIS_WIDE, g.LAKE, g.PORTRAIT]
NAMES = ['IMG_2041.jpg', 'IMG_2042.jpg', 'paris.png', 'IMG_2043.jpg', 'park.png', 'paris_2.png', 'IMG_2044.jpg', 'portrait.png']


def w_finder(t, highlight=None, names=NAMES):
    p = mac_window((700, 480), L('Downloads', '下载'))
    for i in range(8):
        x, y = 40 + (i % 4) * 160, 80 + (i // 4) * 190
        if highlight == i:
            rr(p, (x - 10, y - 8, x + 138, y + 168), 12, fill=(70, 52, 40))
        put(p, photo(THUMBS[i], (128, 128), 8), (x, y))
        txt(p, (x + 64, y + 150), names[i], 15, WHITE if highlight == i else GRAY, 'r', 'mm', 'en')
    return p


def w_preview(t):
    p = mac_window((620, 520), L('IMG_2042.jpg — Preview', 'IMG_2042.jpg — 预览'))
    put(p, photo(ImageOps.fit(g.PORTRAIT, (300, 450)), (300, 450), 4), (160, 60))
    return p


def w_upload(t):
    p = mac_window((720, 480), L('Online Photo Editor · Upload', '在线修图工具 · 上传图片'))
    rr(p, (60, 90, 660, 330), 16, outline=(110, 100, 96), width=3)
    txt(p, (360, 180), '⬆', 54, GRAY, 'r', 'mm', 'en')
    txt(p, (360, 260), L('Drop an image, or click to upload', '拖入图片，或点击上传'), 22, GRAY, 'm', 'mm')
    q = clamp(t / .6)
    rr(p, (60, 380, 660, 396), 8, fill=(52, 50, 54))
    rr(p, (60, 380, 60 + 600 * q, 396), 8, fill=WARM)
    txt(p, (60, 430), L(f'Uploading {round(q * 100)}%', f'上传中 {round(q * 100)}%'), 19, GRAY, 'r', 'lm')
    return p


def w_wait(t):
    p = mac_window((700, 460), L('Online Photo Editor · Processing', '在线修图工具 · 处理中'))
    d = ImageDraw.Draw(p)
    a0 = (t * 360) % 360
    d.arc((290, 120, 410, 240), a0, a0 + 270, fill=WARM, width=10)
    txt(p, (350, 300), L('In queue: 12 people ahead of you', '排队中，前面还有 12 人'), 24, WHITE, 'm', 'mm')
    rr(p, (210, 350, 490, 400), 12, fill=(52, 50, 54))
    txt(p, (350, 375), L('Download (sign-in required)', '下载结果（需登录）'), 19, GRAY, 'm', 'mm')
    return p


def w_compare_old(t):
    p = mac_window((760, 440), L('Preview — 2 windows', '预览 — 2 个窗口'))
    for j, (img, n) in enumerate([(g.PORTRAIT, 'IMG_2042.jpg'), (g.PARK, 'IMG_2042 (1).jpg')]):
        x = 40 + j * 350
        rr(p, (x, 70, x + 330, 410), 10, fill=(22, 22, 26))
        put(p, photo(ImageOps.fit(img, (200, 290)), (200, 290), 4), (x + 65, 80))
        txt(p, (x + 165, 390), n, 15, GRAY, 'r', 'mm', 'en')
    return p


PILE = [(0.15, w_finder, (760, 150)), (0.85, w_preview, (1180, 230)), (1.45, w_upload, (860, 380)),
        (2.1, w_wait, (1150, 470)), (2.75, lambda t: w_finder(t, 1, NAMES[:1] + ['IMG_2042 (1).jpg'] + NAMES[2:]), (800, 560)),
        (3.4, w_compare_old, (1080, 600))]


def pain(t):
    im = BG.copy()
    txt(im, (110, 280), L('Just want to edit one photo…', '想修一张图……'), 36, GRAY, 'm')
    copy(im, ease(t / .3), L('One photo.', '修一张图，'), L('How many windows?', '要开几个窗口？'))
    shake = 6 * math.sin(t * 40) * clamp((t - 4.2) / .2) if t > 4.2 else 0
    for i, (at, fn, (x, y)) in enumerate(PILE):
        a = ease((t - at) / .22)
        if a <= 0:
            continue
        p = fn(t - at)
        dim = 1 - .12 * sum(1 for at2, _, _ in PILE if at2 > at and t > at2)
        g.place_card(im, p, x + shake * (i % 2 * 2 - 1), y + 30 * (1 - a), a * max(.55, dim))
    n = sum(1 for at, _, _ in PILE if t > at)
    if n:
        chip = Image.new('RGBA', (300, 60))
        rr(chip, (0, 0, 299, 59), 16, fill=(64, 34, 32), outline=(150, 80, 70))
        txt(chip, (150, 30), L(f'{n} windows open', f'已打开 {n} 个窗口'), 24, (240, 160, 140), 'm', 'mm')
        put(im, chip, (110, 760))
    return im


# ---------- 5–8 s: reveal ----------
_PAIN_END = None


def reveal(t):
    global _PAIN_END
    if _PAIN_END is None:
        _PAIN_END = pain(4.99)
    im = BG.copy()
    k = smooth(t / .5)
    if k < 1:
        s = 1 - .25 * k
        shot = _PAIN_END.resize((round(W * s), round(H * s)), Image.Resampling.LANCZOS)
        put(im, shot, ((W - shot.width) / 2, (H - shot.height) / 2), 1 - k)
    a = ease((t - .35) / .35)
    if a > 0:
        layer = Image.new('RGBA', (W, H))
        put(layer, ui.rounded(g.LOGO, (150, 150), 38), (885, 230))
        txt(layer, (960, 470), 'Glance', 120, WHITE, 'b', 'mm', 'en')
        txt(layer, (960, 640), L('With Glance, one window is enough.', '用 Glance，一个窗口就够了。'), 64, WARM, 's', 'mm')
        put(im, layer, (0, 18 * (1 - a)), a)
    return im


# ---------- 8–13 s: view ----------
STRIP = ['lake', 'portrait', 'paris', 'lake_warm']


def zoom_key(base, z, cx=.5, cy=.32):
    key = f'{base}@{z:.3f}'
    if key not in SRC:
        img = SRC[base]
        w, h = img.width / z, img.height / z
        x = min(max(cx * img.width - w / 2, 0), img.width - w)
        y = min(max(cy * img.height - h / 2, 0), img.height - h)
        SRC[key] = img.crop((round(x), round(y), round(x + w), round(y + h)))
    return key


def pill(im, s, xy, a=1, color=WHITE, bg=(20, 20, 24, 225)):
    w = round(tw(s, 22, 'm')) + 40
    p = Image.new('RGBA', (w, 46))
    rr(p, (0, 0, w - 1, 45), 12, fill=bg)
    txt(p, (w / 2, 23), s, 22, color, 'm', 'mm')
    put(im, p, xy, a)


def view(t):
    im = BG.copy(); g.header(im)
    copy(im, ease(t / .3), L('Double-click.', '双击打开，'), L('See every detail.', '看清每一处细节。'), L('Zoom · Pan · Browse the folder', '放大 · 平移 · 翻看同组图片'))
    # Browse: switch image every ~0.6 s after 3.0 s.
    idx = 0 if t < 3.0 else min(3, 1 + int((t - 3.0) / .6))
    key = STRIP[idx]
    if t < 3.0:
        z = 1 + 1.6 * smooth((t - .9) / .9) - 1.6 * smooth((t - 2.3) / .6)
        if z > 1.001:
            key = zoom_key('lake', round(z, 3))
    tiles = tuple(('sel' if i == idx else 'plain', k, None) for i, k in enumerate(STRIP))
    layer = g.window(key, tiles=tiles)
    s = .9 + .1 * ease(t / .35)
    a = ease(t / .3)
    if s < 1:
        layer = layer.resize((round(layer.width * s), round(layer.height * s)), Image.Resampling.LANCZOS)
        big = Image.new('RGBA', g.WIN)
        big.alpha_composite(layer, ((g.WIN[0] - layer.width) // 2, (g.WIN[1] - layer.height) // 2))
        layer = big
    g.place_window(im, layer, a)
    if 1.0 < t < 2.9:
        z = 1 + 1.6 * smooth((t - .9) / .9) - 1.6 * smooth((t - 2.3) / .6)
        pill(im, f'{round(z * 100)}%', (g.WX + g.WW - 130, g.WY + 24))
    # Cursor: double-click at start, then clicks the next tiles.
    if t < .6:
        ui.cursor(im, 1310, 560, clamp(t / .3))
    elif t > 2.8:
        n = min(3, 1 + int((t - 3.0) / .6)) if t > 3.0 else 1
        tx = g.WX + (g.WIN[0] / 2 - (94 + 106 * 3) / 2 + 106 * n + 47) * g.WS
        ty = g.WY + (g.WIN[1] - 59) * g.WS
        ui.cursor(im, round(tx), round(ty), clamp(((t - 3.0) % .6) / .3) if t > 3.0 else 0)
    return im


# ---------- 13–18 s: compare ----------
def compare_key(mode, split=.5):
    key = f'cmp-{mode}-{split:.3f}'
    if key not in SRC:
        a, b = LAKE, LAKE_WARM
        if mode == 'side':
            c = Image.new('RGB', (a.width * 2 + 24, a.height), (16, 16, 19))
            c.paste(a, (0, 0)); c.paste(b, (a.width + 24, 0))
        else:
            c = a.copy()
            x = round(a.width * split)
            c.paste(b.crop((x, 0, b.width, b.height)), (x, 0))
            d = ImageDraw.Draw(c)
            d.line((x, 0, x, c.height), fill=WHITE, width=6)
            d.ellipse((x - 34, c.height / 2 - 34, x + 34, c.height / 2 + 34), fill=WHITE)
            d.polygon([(x - 8, c.height / 2), (x - 20, c.height / 2 - 12), (x - 20, c.height / 2 + 12)], fill=INK)
            d.polygon([(x + 8, c.height / 2), (x + 20, c.height / 2 - 12), (x + 20, c.height / 2 + 12)], fill=INK)
        SRC[key] = c
    return key


def compare(t):
    im = BG.copy(); g.header(im)
    copy(im, ease(t / .3), L('Two images.', '两张图，'), L('Spot the difference.', '差别一眼看清。'), L('Side by side · Slider', '并排对比 · 滑杆对比'))
    tiles = (('sel', 'lake', None), ('sel', 'lake_warm', None))
    if t < 2.4:
        key = compare_key('side')
    else:
        q = (t - 2.4)
        split = .5 + .32 * math.sin(q * 2.2) if q < 2.6 else .5
        key = compare_key('slider', round(split, 3))
    g.place_window(im, g.window(key, tiles=tiles), 1)
    if t < 2.4:
        pill(im, L('A  Original', 'A  原图'), (g.WX + 70, g.WY + 600), ease(t / .3))
        pill(im, L('B  Edited', 'B  调色后'), (g.WX + g.WW - 220, g.WY + 600), ease(t / .3))
    else:
        q = t - 2.4
        split = .5 + .32 * math.sin(q * 2.2) if q < 2.6 else .5
        # window canvas: compare image is contain-fit; map split to screen x
        fit_w = LAKE.width * (g.WIN[1] / LAKE.height)
        x = g.WX + ((g.WIN[0] - fit_w) / 2 + fit_w * split) * g.WS
        ui.cursor(im, round(x + 6), round(g.WY + g.WH / 2 + 12))
    if 2.2 < t < 2.7:
        pill(im, L('Switch to slider', '切换到滑杆对比'), (g.WX + g.WW / 2 - 110, g.WY + 90), clamp((t - 2.2) / .15) * clamp((2.7 - t) / .15))
    return im


# ---------- 18–25 s: fix with AI ----------
BG_DEMO = g.demo_scene(dict(widget='bgpro', before='portrait', after='cutout',
                            first=L('Not quite right?', '不满意？'), second=L('Fix it with AI.', '右键，用 AI 改。'),
                            menu_label=L('Background Remover Pro', '人物背景分离'),
                            done=L('Background removed', '背景已移除'), note=L('Product animation · example result', '产品动效示意 · 示例效果')))
CHECKS = L(['Remove background', 'Expand', 'Upscale'], ['去背景', '扩图', '高清放大'])


CK = L(25, 30)


def checks(im, n, t):
    x = 112
    for i, s in enumerate(CHECKS):
        on = i < n
        a = 1 if on else .35
        layer = Image.new('RGBA', (round(tw(s, CK, 'm')) + 70, 56))
        ImageDraw.Draw(layer).ellipse((0, 8, 40, 48), outline=GREEN if on else GRAY, width=3,
                                      fill=(20, 40, 32) if on else None)
        if on:
            txt(layer, (20, 28), '✓', 24, GREEN, 'b', 'mm', 'en')
        txt(layer, (60, 28), s, CK, WHITE, 'm', 'lm')
        put(im, layer, (x, 610), a)
        x += 60 + tw(s, CK, 'm') + 40


def fix(t):
    if t < 3.8:
        im = BG_DEMO(t)
        checks(im, 1 if t > 3.5 else 0, t)
        return im
    im = BG.copy(); g.header(im)
    # Same size/position as the demo scene's headline, so the cut doesn't jump.
    g.copy_block(im, L('Not quite right?', '不满意？'), L('Fix it with AI.', '右键，用 AI 改。'), None, 1)
    if t < 5.4:
        q = smooth((t - 4.05) / 1.0)
        layer = g.window('paris', 'paris_wide', q, 'zoom',
                         (('sel', 'paris', None),) if q < 1 else (('plain', 'paris', None), ('sel', 'paris_wide', 'NEW')))
        label, done, n = L('Expand Image', '智能扩图'), L('Image expanded', '扩图完成'), 2 if q >= 1 else 1
    else:
        q = smooth((t - 5.55) / .8)
        layer = g.window('lake_soft', 'lake', q, 'wipe',
                         (('sel', 'lake_soft', None),) if q < 1 else (('plain', 'lake_soft', None), ('sel', 'lake', 'NEW')))
        label, done, n = L('Upscale', '高清放大'), L('Upscaled', '放大完成'), 3 if q >= 1 else 2
    g.place_window(im, layer, 1)
    g.step_path(im, label, 1)
    checks(im, n, t)
    if q >= 1:
        g.done_badge(im, done, 1)
    g.footnote(im, L('Product animation · example result', '产品动效示意 · 示例效果'))
    return im


# ---------- 25–30 s: end ----------
def ending(t):
    im = BG.copy()
    a = ease(t / .3)
    layer = Image.new('RGBA', (W, H))
    put(layer, ui.rounded(g.LOGO, (150, 150), 38), (885, 120))
    txt(layer, (960, 370), 'Glance', 120, WHITE, 'b', 'mm', 'en')
    txt(layer, (960, 510), L('View. Fix. Compare. One window.', '看、改、比，一个窗口。'), 70, WARM, 's', 'mm')
    txt(layer, (960, 600), L('Viewing, compare, capture & OCR free forever · 14-day full trial', '看图、对比、截图、OCR 永久免费 · 14 天完整试用'), 27, GRAY, 'r', 'mm')
    put(im, layer, (0, 16 * (1 - a)), a)
    b = ease((t - .6) / .35)
    if b > 0:
        tip = Image.new('RGBA', (W, 80))
        s1, s3 = L('Bonus: select a file path and press ', '彩蛋：选中文件路径，按 '), L(' Space to preview it', ' 空格 直接预览')
        w1 = tw(s1, 25, 'r'); w2 = tw('⌥', 25, 'r', 'en') + tw(s3, 25, 'm')
        x0 = 960 - (w1 + w2 + 48) / 2
        rr(tip, (x0, 6, x0 + w1 + w2 + 48, 70), 18, fill=(36, 30, 27), outline=(118, 86, 66))
        txt(tip, (x0 + 24, 38), s1, 25, GRAY, 'r', 'lm')
        txt(tip, (x0 + 24 + w1, 38), '⌥', 25, WARM, 's', 'lm', 'en')
        txt(tip, (x0 + 24 + w1 + tw('⌥', 25, 'r', 'en'), 38), s3, 25, WARM, 'm', 'lm')
        put(im, tip, (0, 680 + 10 * (1 - b)), b)
    c = ease((t - 1.0) / .35)
    if c > 0:
        cta = Image.new('RGBA', (W, 100))
        s = 'glancepreview.com'
        w = tw(s, 34, 's', 'en') + 90
        rr(cta, (960 - w / 2, 10, 960 + w / 2, 84), 37, fill=WARM)
        txt(cta, (960, 47), s, 34, INK, 's', 'mm', 'en')
        put(im, cta, (0, 830 + 10 * (1 - c)), c)
    return im


SCENES = [(0, pain), (5.0, reveal), (8.0, view), (13.0, compare), (18.0, fix), (25.0, ending)]


def frame(t):
    i = max(i for i, s in enumerate(SCENES) if s[0] <= t)
    start, fn = SCENES[i]
    im = fn(t - start)
    if i == 2 and t - start < .2:
        ps, pf = SCENES[i - 1]
        im = Image.blend(pf(t - ps).convert('RGBA'), im.convert('RGBA'), smooth((t - start) / .2))
    if t > DURATION - .5:
        im = Image.blend(im.convert('RGBA'), Image.new('RGBA', (W, H), (0, 0, 0, 255)), smooth((t - DURATION + .5) / .5) * .9)
    return im.convert('RGB')


# ---------- audio ----------
SR = 48000


def music():
    n = SR * DURATION; sig = np.zeros((n, 2)); rng = np.random.default_rng(3)
    time = np.arange(n) / SR

    def tone(at, dur, hz, amp, soft=False, pan=0):
        b = round(at * SR); c = min(round(dur * SR), n - b)
        if c <= 0: return
        ts = np.arange(c) / SR
        env = (1 - np.exp(-ts / (.18 if soft else .004))) * np.exp(-ts / (2.2 if soft else .3)) * np.clip((dur - ts) / .15, 0, 1)
        v = (np.sin(2 * np.pi * hz * ts) + .15 * np.sin(4 * np.pi * hz * ts)) * env * amp
        sig[b:b + c] += v[:, None] * np.array([1 - pan * .3, 1 + pan * .3])

    def noise(at, dur, amp, sweep=False):
        b = round(at * SR); c = min(round(dur * SR), n - b)
        if c <= 0: return
        ts = np.arange(c) / SR
        v = np.convolve(rng.normal(size=c), np.ones(16) / 16, mode='same')
        v *= (np.sin(np.pi * ts / dur) ** 2 if sweep else np.exp(-ts * 110)) * amp
        sig[b:b + c] += v[:, None]

    k = 0
    while k * .32 < 4.9:
        tone(k * .32, .25, [146.83, 155.56, 164.81][k % 3], .05); noise(k * .32, .04, .06); k += 1
    for at, _, _ in PILE:
        noise(at, .18, .1, True)
    noise(4.7, .4, .16, True)
    chords = [(130.81, 164.81, 196.0, 246.94), (110.0, 130.81, 164.81, 196.0),
              (87.31, 110.0, 130.81, 164.81), (98.0, 123.47, 146.83, 196.0)]
    at, j = 5.0, 0
    while at < DURATION:
        for q, hz in enumerate(chords[j % 4]):
            tone(at, 3.1, hz, .034, True, (-1) ** q * .4)
        tone(at, .6, chords[j % 4][0] / 2, .045)
        at += 2.5; j += 1
    at, j = 5.0, 0
    while at < DURATION - 1.5:
        tone(at, .9, [523.25, 659.25, 783.99, 659.25][j % 4], .016); at += .625; j += 1
    for q, hz in enumerate((523.25, 659.25, 783.99, 1046.5)):
        tone(5.3 + q * .12, 1.4, hz, .045)
    noise(8.15, .05, .25); noise(8.3, .05, .25)                       # double-click
    for q in range(3): noise(11.0 + q * .6, .05, .2)                  # browse clicks
    noise(15.3, .3, .07, True)                                        # slider
    T = g.DEMO_TIMING
    noise(18 + T['click'], .05, .28); noise(18 + T['pick'], .05, .25)
    for at in (18 + T['reveal'] + .8, 18 + 5.05, 18 + 6.35):
        tone(at, 1, 1046.5, .045); tone(at + .1, 1, 1318.5, .04)
    for q, hz in enumerate((523.25, 659.25, 783.99, 1046.5)):
        tone(25.05 + q * .12, 2.5, hz, .045)
    sig *= (np.clip(time / .03, 0, 1) * np.clip((DURATION - time) / 1.0, 0, 1))[:, None]
    return sig / max(.01, np.max(np.abs(sig)))


def voice():
    n = SR * DURATION; v = np.zeros(n)
    for i, at in enumerate(VOICE_AT):
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(OUT / f"voice{TAG}/{i}.aiff"), '-ac', '1', '-ar', str(SR),
                              '-f', 's16le', '-'], capture_output=True, check=True).stdout
        x = np.frombuffer(raw, '<i2').astype(float) / 32768
        b = round(at * SR); x = x[:n - b]
        v[b:b + len(x)] += x
    return v / max(.01, np.max(np.abs(v)))


def write_wav(path, sig):
    sig = sig * (.89 / max(.01, np.max(np.abs(sig))))
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes((sig * 32767).astype('<i2').tobytes())


def soundtracks():
    m = music()
    write_wav(OUT / f'soundtrack{TAG}.wav', m * .85)
    v = voice()
    env = np.convolve((np.abs(v) > .02).astype(float), np.ones(SR // 4) / (SR // 4), mode='same')
    duck = 1 - .62 * np.clip(env * 3, 0, 1)
    write_wav(OUT / f'soundtrack{TAG}-voice.wav', m * .55 * duck[:, None] + v[:, None] * .95)


def frame_bytes(i):
    return frame(i / FPS).tobytes()


def previews():
    times = [2.5, 4.6, 6.8, 9.6, 11.6, 14.2, 16.6, 19.2, 21.6, 22.9, 24.6, 27.8]
    board = Image.new('RGB', (1920, 310 * 3), (12, 12, 16))
    for i, t in enumerate(times):
        x, y = (i % 4) * 480, (i // 4) * 310
        board.paste(frame(t).resize((480, 270), Image.Resampling.LANCZOS), (x, y))
        ImageDraw.Draw(board).text((x + 12, y + 278), f'{t:.1f}s', fill=GRAY, font=g.font(20, 'r', 'en'))
    board.save(OUT / f'storyboard{TAG}.jpg', quality=92)
    frame(28).save(OUT / f'poster{TAG}.jpg', quality=94)


def encode(audio, out):
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0', '-i', str(audio), '-map', '0:v', '-map', '1:a',
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
           '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(6) as pool:
        for i, data in enumerate(pool.imap(frame_bytes, range(FPS * DURATION), chunksize=4)):
            enc.stdin.write(data)
            if i % 150 == 0: print(f'{i}/{FPS * DURATION}', flush=True)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('encode failed')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lang', default='zh', choices=['zh', 'en'])
    ap.add_argument('--preview', action='store_true')
    ap.add_argument('--at', type=float, nargs='*')
    args = ap.parse_args()
    if args.at:
        for t in args.at: frame(t).save(OUT / f'check-{LANG}-{t:.1f}.jpg', quality=90)
        return
    previews()
    if args.preview: return
    soundtracks()
    encode(OUT / f'soundtrack{TAG}.wav', OUT / f'glance-intro-30s-{LANG}.mp4')
    # Same picture, narrated mix: remux instead of re-rendering.
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(OUT / f'glance-intro-30s-{LANG}.mp4'), '-i', str(OUT / f'soundtrack{TAG}-voice.wav'),
                    '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION),
                    '-movflags', '+faststart', str(OUT / f'glance-intro-30s-{LANG}-voice.mp4')], check=True)
    print('done')


if __name__ == '__main__':
    main()
