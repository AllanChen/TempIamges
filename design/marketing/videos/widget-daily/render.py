"""Daily Glance Widget spotlight, 15 s. One run = PC 16:9 + phone 9:16 (both with voice).

Run from the repo root: .venv/bin/python design/marketing/videos/widget-daily/render.py --lang zh --widget bgpro [--no-url] [--preview]
UI: Glance 1.1.0 静 Shizuka (shizuka.py). Sample images still come from ../glance-intro-30s/render.py -> ../glance-ai-intro-43s/render.py.
The pre-Shizuka version is render_v1_old-ui.py.
Add a widget by adding an entry to WIDGETS.
"""
import importlib.util
import multiprocessing as mp
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
# Some brand-assets images were removed from the working tree; fall back to copies in ./assets.
_open = Image.open
def _open_fallback(fp, *a, **k):
    if isinstance(fp, (str, Path)) and not Path(fp).exists() and (HERE / 'assets' / Path(fp).name).exists():
        fp = HERE / 'assets' / Path(fp).name
    return _open(fp, *a, **k)
Image.open = _open_fallback
spec = importlib.util.spec_from_file_location('h', HERE.parent / 'glance-intro-30s/render.py')
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
g, ui, L, txt, tw, put, rr = h.g, h.ui, h.L, h.txt, h.tw, h.put, h.rr
W, H, FPS, DURATION, SR = 1920, 1080, 30, 15, h.SR
args = sys.argv[1:]
KEY = args[args.index('--widget') + 1] if '--widget' in args else 'bgpro'

WIDGETS = {
    'bgpro': dict(
        widget='bgpro', before='portrait', after='cutout',
        menu_label=L('Background Remover Pro', '人物背景分离'), done=L('Background removed', '背景已移除'),
        hook=(L('Need a cutout?', '想把人像抠出来？'), L('No upload needed.', '不用再上传网站。')),
        demo=(L('Right-click.', '右键，'), L('Background gone.', '背景一键去掉。')),
        result=(L('Clean edges.', '发丝边缘，'), L('Even on hair.', '也干净利落。')),
        detail=L('Transparent PNG, ready for posters and slides', '透明 PNG，直接用在海报、PPT、电商图'),
        voice=L(['Need a cutout? No more upload sites.', 'In Glance, right-click, choose Background Remover Pro.',
                 'Seconds later, clean edges, even on hair.', 'Glance. Right-click, done.'],
                ['想把人像抠出来，还在找网站上传？', '在 Glance 里右键，选人物背景分离。',
                 '几秒出图，发丝边缘也干净。', 'Glance，看图顺手就改。']),
        tagline=L('See it. Right-click. Fixed.', '看图顺手，右键就改。')),
    'expand': dict(
        widget='expand', before='paris', after='paris_wide', mode='zoom', reveal_dur=1.1,
        menu_label=L('Expand Image', '智能扩图'), done=L('Image expanded', '扩图完成'),
        hook=(L('Framed too tight?', '照片拍得太满？'), L('No need to reshoot.', '不用重拍。')),
        demo=(L('Right-click.', '右键，'), L('Expand the frame.', '画面向外扩。')),
        result=(L('Room to breathe,', '构图留白，'), L('filled in by AI.', 'AI 帮你补。')),
        detail=L('Fits covers, posters and wallpapers', '封面、海报、壁纸，比例不够也能用'),
        voice=L(['Photo framed too tight to crop?', 'In Glance, right-click and choose Expand Image.',
                 'AI fills in beyond the edges.', 'Glance. Right-click, done.'],
                ['照片拍得太满，想换个比例却不够裁？', '在 Glance 里右键，选智能扩图。',
                 '画面向外延伸，AI 自动补全。', 'Glance，看图顺手就改。']),
        tagline=L('See it. Right-click. Fixed.', '看图顺手，右键就改。')),
    'upscale': dict(
        widget='upscale', before='lake_soft', after='lake',
        menu_label=L('Upscale', '高清放大'), done=L('Upscaled', '放大完成'),
        hook=(L('Blurry photo?', '照片太糊？'), L('Too soft to print.', '放大全是马赛克。')),
        demo=(L('Right-click.', '右键，'), L('Make it sharp.', '一键变高清。')),
        result=(L('More pixels,', '分辨率更高，'), L('finer detail.', '细节更清楚。')),
        detail=L('For wallpapers, prints and big screens', '做壁纸、打印、投屏都够用'),
        voice=L(['Photo too blurry to use?', 'In Glance, right-click and choose Upscale.',
                 'Sharper edges, finer detail.', 'Glance. Right-click, done.'],
                ['照片太糊，一放大全是马赛克？', '在 Glance 里右键，选高清放大。',
                 '分辨率更高，细节一下就清楚了。', 'Glance，看图顺手就改。']),
        tagline=L('See it. Right-click. Fixed.', '看图顺手，右键就改。')),
    'objects': dict(
        widget='objects', before='portrait', after='park', prompt_time=1.1, prompt='city, people',
        scenes_at=[0, 3.6, 9.0, 12.2], voice_at=[0.2, 3.8, 9.2, 12.4],
        menu_label=L('Remove Objects', '移除物体'), done=L('Done', '已完成'),
        hook=(L('Messy background?', '背景太乱？'), L('Crowds, buildings, clutter.', '路人全入镜。')),
        demo=(L('Type what to remove.', '写下要去掉的，'), L('AI clears it.', 'AI 帮你清走。')),
        result=(L('Same person,', '人还是那个人，'), L('cleaner scene.', '画面清爽了。')),
        detail=L('AI fills in what was behind', 'AI 自动补全被去掉的地方'),
        voice=L(['Background full of crowds and buildings?', 'Right-click, Remove Objects, type what to remove.',
                 'Same person, a much cleaner scene.', 'Glance. Right-click, done.'],
                ['背景里路人、楼房太乱？', '右键选移除物体，写下要去掉的东西。',
                 '人还是那个人，画面清爽多了。', 'Glance，看图顺手就改。']),
        tagline=L('See it. Right-click. Fixed.', '看图顺手，右键就改。')),
    'editarea': dict(
        widget='editarea', before='portrait', after='nobag',
        scenes_at=[0, 3.6, 9.3, 12.3], voice_at=[0.2, 3.8, 9.5, 12.5],
        menu_label=L('Edit Area', '局部编辑'), done=L('Done', '已完成'),
        hook=(L('Love the shot,', '照片很满意，'), L('not the bag?', '就是包有点多余？')),
        demo=(L('Paint it, say it.', '涂一下，说一句，'), L('Only that part changes.', '只改涂的地方。')),
        result=(L('Bag gone.', '包没了，'), L('Everything else stays.', '其他都没动。')),
        detail=L('Paint an area, describe the change in words', '涂抹区域，再用一句话描述想要的效果'),
        voice=L(['Love the photo, but not the bag?', 'Right-click, Edit Area. Paint it, then say what you want.',
                 'The bag is gone. The rest stays.', ''],
                ['照片很满意，就是包有点多余？', '右键选局部编辑，把包涂掉，再写一句要的效果。',
                 '包没了，其他地方都没动。', '']),
        tagline=L('', '')),
    'watermark': dict(
        widget='watermark', before='wm_before', after='wm_after',
        menu_label=L('Watermark Remover', '图片去水印'), done=L('Done', '已完成'),
        hook=(L('Your own photo,', '自己的图，'), L('buried under a watermark?', '被水印挡住了？')),
        demo=(L('Right-click.', '右键，'), L('Remove the watermark.', '去掉水印。')),
        result=(L('Watermark gone,', '水印没了，'), L('picture clean.', '画面干净了。')),
        detail=L('Only for images you have the rights to edit', '仅用于你有权处理的图片'),
        voice=L(['Your own photo, covered by a watermark?', 'In Glance, right-click and choose Watermark Remover.',
                 'Watermark gone, picture clean.', ''],
                ['自己的图，被一层水印挡住了？', '在 Glance 里右键，选图片去水印。',
                 '水印没了，画面干净了。', '']),
        tagline=L('', '')),
}
S = WIDGETS[KEY]
# User rule (2026-11-15): no landscape/scenery images (mountains, lakes, nature) in any promo material.
# Use portraits, products, street or interior shots. Old videos are exempt via --allow-landscape (re-renders only).
LANDSCAPE = {'lake', 'lake_soft', 'lake_warm', 'park', 'alpine'}
if {S['before'], S['after']} & LANDSCAPE and '--allow-landscape' not in args:
    raise SystemExit(f"{KEY}: sample image is a landscape ({S['before']} → {S['after']}); pick a portrait/product/street/interior pair")
VOICE_AT = S.get('voice_at', [0.2, 4.1, 8.8, 12.2])
SCENES_AT = S.get('scenes_at', [0, 3.9, 8.6, 12.0])
NOTE = L('Animated demo · Example effect', '产品动效示意 · 示例效果')
import shizuka as z
z.LANG = h.LANG
S = dict(S, voice=list(S['voice'][:-1]) + [z.OUTRO_VOICE[h.LANG]], tagline=z.OUTRO_TEXT[h.LANG])
ease, smooth, clamp = z.ease, z.smooth, z.clamp
SRC = g.SOURCES
CMD = L({'bgpro': 'Remove Background', 'expand': 'Expand', 'upscale': 'Upscale', 'objects': 'Remove Objects', 'editarea': 'Edit Area', 'watermark': 'Remove Watermark'},
        {'bgpro': '移除背景', 'expand': '扩图', 'upscale': '高清放大', 'objects': '移除物体', 'editarea': '局部编辑', 'watermark': '去水印'})   # command names, widget.json
# Watermark Remover samples: widget-daily/watermark/samples/before.png (watermark overlaid on a clean photo) + after.png (the clean photo)
WM = HERE / 'watermark' / 'samples'
if KEY == 'watermark':
    if not (WM / 'before.png').exists() and '--script' not in args:
        raise SystemExit(f'missing {WM}/before.png and after.png (run watermark/make_samples.py)')
    if (WM / 'before.png').exists():
        SRC.setdefault('wm_before', Image.open(WM / 'before.png').convert('RGB'))
        SRC.setdefault('wm_after', Image.open(WM / 'after.png').convert('RGB'))
COST = {z.tr(k): v for k, v in z.WIDGET_ROWS}
FILES = {'portrait': 'IMG_2042.jpg', 'paris': 'IMG_2051.jpg', 'lake_soft': 'IMG_2044.jpg', 'wm_before': 'IMG_2063.jpg'}
SRC.setdefault('nobag', Image.open(REPO_ROOT / 'design/website/GlanceUnslopFigmaPlugin/portable/photos/portrait-handbag-removed.png').convert('RGB'))
BEFORE_NAME = FILES[S['before']]
AFTER_NAME = BEFORE_NAME.rsplit('.', 1)[0] + ' 2.png'
PROMPT = {'objects': 'Remove people and buildings', 'editarea': L('Remove the bag', '去掉这个包')}.get(KEY, '')
T = dict(click=.75, pick=2.05)
EXTRA = {'objects': 1.2, 'editarea': 2.0}.get(KEY, 0)
MASK = (640, 800, 880, 1160) if KEY == 'editarea' else None   # handbag, source px
RUN, REVEAL = 2.2 + EXTRA, 2.95 + EXTRA
ZH_LABEL = {'bgpro': '人物背景分离', 'expand': '智能扩图', 'upscale': '高清放大', 'objects': '移除物体', 'editarea': '局部编辑', 'watermark': '图片去水印'}[KEY]
OX, OY = 330, 60                    # right-click point, window-logical


def meta(img, fmt): return f'{img.width} × {img.height}   {fmt}'


def app(main_key, tiles, name, fmt, pos, mode='image', overlay=None, slider=None):
    c = Image.new('RGBA', (z.P(z.CANVAS[0]), z.P(z.CANVAS[1])))
    win = Image.new('RGBA', (z.P(z.LW), z.P(z.LH)))
    z.chrome(win, mode)
    if slider is not None:
        z.slider(win, SRC[S['before']], SRC[S['after']], slider, [('B', BEFORE_NAME), ('A', AFTER_NAME)])
    else:
        z.stage_image(win, SRC[main_key])
    if overlay: overlay(win)
    z.filmstrip(win, tiles, overlay.t if overlay else 0)
    z.bottom_bar(win, name, meta(SRC[S['after']] if str(main_key).startswith('zoom') else SRC[main_key], fmt), pos=pos, modes=slider is not None)
    m = Image.new('L', win.size); ImageDraw.Draw(m).rounded_rectangle((0, 0, win.width - 1, win.height - 1), z.P(12), fill=255)
    win.putalpha(ImageChops.multiply(win.getchannel('A'), m))
    c.paste(win, (0, 0), win)
    return c


def window_frame(im, c, a=1, dy=0):
    z.window_shadow(im, a, dy)
    z.place_canvas(im, c, a, dy)


def hook(t):
    im = z.BG.copy(); z.header(im)
    a = ease(t / .35)
    z.copy_block(im, *S['hook'], None, a)
    b = ease((t - .2) / .4)
    c = app(S['before'], [(SRC[S['before']], 'sel')], BEFORE_NAME, 'JPEG', '1 / 1')
    window_frame(im, c, b, 20 * (1 - b))
    return im


class Running:
    def __init__(self, t, pct): self.t, self.pct = t, pct
    def __call__(self, win):
        z.running_overlay(win, z.fit_rect(SRC[S['before']]), self.t, self.pct, CMD[KEY])


def demo(t):
    im = z.BG.copy(); z.header(im)
    a = ease(t / .3)
    z.copy_block(im, *S['demo'], None, a)
    z.step_path(im, S['menu_label'], ease((t - .3) / .3))
    before, after = SRC[S['before']], SRC[S['after']]
    if t < RUN:
        c = app(S['before'], [(before, 'sel')], BEFORE_NAME, 'JPEG', '1 / 1')
    elif t < REVEAL:
        pct = round(8 + 91 * clamp((t - RUN) / (REVEAL - RUN)))
        c = app(S['before'], [(before, 'sel'), (None, 'running')], BEFORE_NAME, 'JPEG', '1 / 1', overlay=Running(t - RUN, pct))
    else:
        q = smooth((t - REVEAL) / (1.1 if S.get('mode') == 'zoom' else .35))
        if S.get('mode') == 'zoom':
            key = g.zoom_source(q)
        else:
            key = S['after'] if q >= 1 else None
        tiles = [(before, 'plain'), (after, 'newsel')]
        if key is None:
            c = app(S['before'], tiles, AFTER_NAME, 'PNG', '2 / 2')
            c2 = app(S['after'], tiles, AFTER_NAME, 'PNG', '2 / 2')
            c = Image.blend(c, c2, q)
        else:
            c = app(key, tiles, AFTER_NAME, 'PNG', '2 / 2')
    # menus
    cx = cy = None; pulse = 0
    menu_t = t - T['click']
    if T['click'] <= t < T['pick'] + .15:
        hl_w = menu_t > .3
        mm = z.main_menu(hl_w)
        ma = ease(menu_t / .12) * clamp((T['pick'] + .15 - t) / .1)
        sub_x, sub_y = OX + 262, OY
        if menu_t > .4:
            target_hl = t > T['pick'] - .3
            sm = z.widget_menu(ZH_LABEL, target_hl)
        else:
            sm = None
        layer = Image.new('RGBA', c.size)
        z.put(layer, mm, (z.P(OX), z.P(OY)))
        if sm is not None: z.put(layer, sm, (z.P(sub_x), z.P(sub_y)), ease((menu_t - .4) / .12))
        z.put(c, layer, (0, 0), ma)
    window_frame(im, c)
    # widget input window (Remove Objects asks for a prompt)
    if EXTRA and T['pick'] + .1 <= t < RUN + .1:
        ta = t - T['pick'] - .1
        if MASK:
            paint = clamp((ta - .25) / .8)              # brush strokes over the bag, then type the prompt
            typed = PROMPT[:max(0, int((ta - 1.15) * 14))]
        else:
            paint, typed = None, PROMPT[:max(0, int((ta - .2) * 36))]
        pressed = RUN - .12 < t
        iw, btn = z.input_window(CMD[KEY], COST[S['menu_label']], before, typed, int(t * 2.5) % 2 == 0, pressed,
                                 mask=MASK, paint=paint)
        s_ = 0.92
        small = iw.resize((round(iw.width * s_ / z.K), round(iw.height * s_ / z.K)), Image.Resampling.LANCZOS)
        ix, iy = z.WX, z.WY + (z.LH * z.SCALE - small.height) / 2
        ia = ease(ta / .15) * clamp((RUN + .1 - t) / .1)
        sh = Image.new('RGBA', (small.width + 120, small.height + 120)); z.rr(sh, (60, 70, sh.width - 60, sh.height - 50), 18, fill=(0, 0, 0, 210))
        z.put(im, sh.filter(ImageFilter.GaussianBlur(30)), (ix - 60, iy - 60), ia)
        z.put(im, small, (ix, iy), ia)
        bx, by = ix + btn[0] * s_, iy + btn[1] * s_
        go = 1.75 if MASK else .95
        if MASK and paint is not None and 0 < paint < 1:
            px_, py_ = z.mask_brush_point(MASK, before, paint)
            cx, cy = ix + px_ * s_, iy + py_ * s_
        if ta > go:
            cx, cy = z.move((ix + 700, iy + 300), (bx, by), (ta - go) / .3)
            pulse = clamp((t - (RUN - .12)) / .3) if t > RUN - .12 else 0
    # cursor
    click = z.to_frame(OX, OY)
    wrow = z.to_frame(OX + 90, OY + 6 + 14)
    sub_in = z.to_frame(OX + 262 + 60, OY + 6 + 14)
    trow = z.to_frame(OX + 262 + 70, OY + z.widget_row_y(ZH_LABEL))
    if t < T['click']:
        cx, cy = z.move(z.to_frame(700, 520), click, (t - .2) / .5)
        pulse = 0
    elif t < T['pick'] + .15:
        if menu_t < .4: cx, cy = z.move(click, wrow, menu_t / .3)
        elif menu_t < .65: cx, cy = z.move(wrow, sub_in, (menu_t - .4) / .25)
        else: cx, cy = z.move(sub_in, trow, (menu_t - .65) / .45)
        pulse = clamp(menu_t / .35) if menu_t < .35 else (clamp((t - T['pick']) / .3) if t > T['pick'] else 0)
    if cx is not None and t < RUN + .2:
        z.cursor(im, round(cx), round(cy), pulse)
    z.footnote(im, NOTE)
    return im


def result(t):
    im = z.BG.copy(); z.header(im)
    z.copy_block(im, *S['result'], S['detail'], ease(t / .3))
    before, after = SRC[S['before']], SRC[S['after']]
    if S.get('mode') == 'zoom':
        q = 1 - smooth((t - .5) / .9) + smooth((t - 1.8) / 1.0)
        c = app(g.zoom_source(q), [(before, 'plain'), (after, 'newsel')], AFTER_NAME, 'PNG', '2 / 2')
    else:
        split = .5 + .5 * np.cos(np.pi * clamp(t / 1.4)) if t < 1.4 else .5 - .5 * np.cos(np.pi * clamp((t - 1.5) / 1.3)) * .7 - .15
        split = clamp(.12 + .76 * split, .1, .9)
        c = app(S['after'], [(before, 'b'), (after, 'newsel')], AFTER_NAME, 'PNG', '2 / 2', mode='compare', slider=split)
    window_frame(im, c)
    z.footnote(im, NOTE)
    return im


def ending(t):
    im = z.BG.copy(); a = ease(t / .3)
    layer = Image.new('RGBA', (W, H))
    z.put(layer, z.logo(150), (885, 150))
    z.txt(layer, (960, 400), 'Glance', 120, z.TEXT1, 's', 'mm', 'inter')
    z.txt(layer, (960, 540), S['tagline'], 66, z.SHU, 'b', 'mm', 'song')
    z.txt(layer, (960, 630), f"Widget · {S['menu_label']}", 30, z.TEXT2, 'r', 'mm')
    z.put(im, layer, (0, 16 * (1 - a)), a)
    c = ease((t - .7) / .35)
    s = L('Mac app · Made for Mac', 'Mac 电脑软件 · 为 Mac 打造') if h.NO_URL else 'glancepreview.com'
    w = z.tw(s, 34, 's') + 90
    cta = Image.new('RGBA', (W, 100))
    z.rr(cta, (960 - w / 2, 10, 960 + w / 2, 84), 37, fill=z.TEXT1)
    z.txt(cta, (960, 47), s, 34, z.INK0, 's', 'mm')
    z.put(im, cta, (0, 760 + 10 * (1 - c)), c)
    return im


SCENES = list(zip(SCENES_AT, [hook, demo, result, ending]))


def frame(t):
    i = max(i for i, s in enumerate(SCENES) if s[0] <= t)
    im = SCENES[i][1](t - SCENES[i][0]).convert('RGBA')
    if i and t - SCENES[i][0] < .2:
        ps, pf = SCENES[i - 1]
        im = Image.blend(pf(t - ps).convert('RGBA'), im, smooth((t - SCENES[i][0]) / .2))
    if t > DURATION - .5:
        im = Image.blend(im, Image.new('RGBA', (W, H), (0, 0, 0, 255)), smooth((t - DURATION + .5) / .5) * .9)
    return im.convert('RGB'), i


# ---------- phone 9:16: product on top, copy below, bottom kept clear for app overlays ----------
VW, VH = 1080, 1920
BG_V = z.make_bg(VW, VH)
BG_RGB = np.asarray(z.BG.convert('RGB'), np.int16)


def paste_scaled(dst, src, box, width, y):
    s = width / (box[2] - box[0]); size = (width, round((box[3] - box[1]) * s))
    crop = np.asarray(src.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    bg = np.asarray(z.BG.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    x0, y0 = (VW - width) // 2, round(y)
    reg = np.asarray(dst.crop((x0, y0, x0 + size[0], y0 + size[1])).convert('RGB'), np.int16)
    dst.paste(Image.fromarray(np.clip(reg + crop - bg, 0, 255).astype(np.uint8)).convert('RGBA'), (x0, y0))


def vframe(t):
    src, i = frame(t)
    im = BG_V.copy()
    if i == 3:
        paste_scaled(im, src, (300, 100, 1620, 900), VW, 520)
    else:
        z.put(im, z.logo(64), (60, 70))
        z.txt(im, (142, 102), 'Glance', 40, z.TEXT1, 's', 'lm', 'inter')
        paste_scaled(im, src, (760, 120, 1910, 1050), 1040, 190)
        paste_scaled(im, src, (60, 330, 755, 840), 860, 1060)
    return im.convert('RGB')


# ---------- audio ----------
def soundtrack(path, music_path=None, voiced=True):
    n = SR * DURATION; tm = np.arange(n) / SR; m = np.zeros((n, 2)); v = np.zeros(n)
    def tone(at, dur, hz, amp, soft=False):
        b = round(at * SR); c = min(round(dur * SR), n - b); ts = np.arange(c) / SR
        env = (1 - np.exp(-ts / (.18 if soft else .004))) * np.exp(-ts / (2.2 if soft else .3)) * np.clip((dur - ts) / .15, 0, 1)
        m[b:b + c] += ((np.sin(2 * np.pi * hz * ts) + .15 * np.sin(4 * np.pi * hz * ts)) * env * amp)[:, None]
    chords = [(130.81, 164.81, 196.0, 246.94), (110.0, 130.81, 164.81, 196.0), (87.31, 110.0, 130.81, 164.81), (98.0, 123.47, 146.83, 196.0)]
    for j, at in enumerate(np.arange(0, DURATION, 2.5)):
        for hz in chords[j % 4]: tone(at, 3.1, hz, .034, True)
        tone(at, .6, chords[j % 4][0] / 2, .045)
    for j, at in enumerate(np.arange(0, DURATION - 1.5, .625)):
        tone(at, .9, [523.25, 659.25, 783.99, 659.25][j % 4], .016)
    T = g.DEMO_TIMING
    for at in (SCENES_AT[1] + T['click'], SCENES_AT[1] + T['pick']): tone(at, .08, 2400, .05)
    for at in (SCENES_AT[1] + T['reveal'] + .8, 12.05):
        tone(at, 1, 1046.5, .045); tone(at + .1, 1, 1318.5, .04)
    m /= np.max(np.abs(m))
    fade = (np.clip(tm / .03, 0, 1) * np.clip((DURATION - tm) / 1.0, 0, 1))[:, None]
    if music_path:
        mm = m * fade; mm *= .89 / np.max(np.abs(mm))
        _wav(music_path, mm)
    if not voiced: return
    for k, at in enumerate(VOICE_AT):
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(voice_file(k)), '-ac', '1', '-ar', str(SR), '-f', 's16le', '-'],
                             capture_output=True, check=True).stdout
        x = np.frombuffer(raw, '<i2').astype(float) / 32768; b = round(at * SR); x = x[:n - b]; v[b:b + len(x)] += x
    v /= np.max(np.abs(v))
    env = np.convolve((np.abs(v) > .02).astype(float), np.ones(SR // 4) / (SR // 4), mode='same')
    sig = m * .55 * (1 - .62 * np.clip(env * 3, 0, 1))[:, None] + v[:, None] * .95
    sig *= (np.clip(tm / .03, 0, 1) * np.clip((DURATION - tm) / 1.0, 0, 1))[:, None]
    sig *= .89 / np.max(np.abs(sig))
    _wav(path, sig)


def _wav(path, sig):
    import wave
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes((sig * 32767).astype('<i2').tobytes())


def pc_bytes(n): return frame(n / FPS)[0].tobytes()
def phone_bytes(n): return vframe(n / FPS).tobytes()


def encode(fn, size, audio, out):
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{size[0]}x{size[1]}',
           '-r', str(FPS), '-i', 'pipe:0', '-i', str(audio), '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-crf', '19',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(6) as pool:
        for data in pool.imap(fn, range(FPS * DURATION), chunksize=4): enc.stdin.write(data)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('encode failed')


OUTDIR = HERE / KEY
# Voice (user rule, 2026-11-17): the user's own voice, generated per line by 「每日发布」 with local F5-TTS
# into <widget>/voice/<lang>-<n>.wav (n = 1..4). System voices only with --system-voice (old videos).
SYSTEM_VOICE = '--system-voice' in args
VDIR = OUTDIR / (f'voice-{h.LANG}' if SYSTEM_VOICE else 'voice')


def voice_file(k): return VDIR / (f'{k}.aiff' if SYSTEM_VOICE else f'{h.LANG}-{k + 1}.wav')


def slots():
    ends = [SCENES_AT[k + 1] if k + 1 < len(SCENES_AT) else DURATION for k in range(len(VOICE_AT))]
    return list(zip(VOICE_AT, [e - .2 for e in ends]))


def voice_script():
    print(f'# {KEY} {h.LANG}: line, target start-end (s), max length (s); save as voice/{h.LANG}-<n>.wav')
    for k, ((a, b), line) in enumerate(zip(slots(), S['voice'])):
        print(f'{h.LANG}-{k + 1}.wav  {a:.1f}–{b:.1f}s  ≤{b - a:.1f}s  {line}')


def check_voice():
    bad = []
    for k, (a, b) in enumerate(slots()):
        f = voice_file(k)
        if not f.exists():
            raise SystemExit(f'missing voice file {f} — ask 每日发布 for it (run with --script for the line list)')
        d = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(f)],
                                 capture_output=True, text=True).stdout)
        if d > b - a + .05: bad.append(f'{f.name}: {d:.2f}s > {b - a:.2f}s')
    if bad: raise SystemExit('voice too long, ask 每日发布 to redo: ' + '; '.join(bad))


def main():
    OUTDIR.mkdir(exist_ok=True); VDIR.mkdir(exist_ok=True)
    if '--script' in args: return voice_script()
    # User rule (2026-11-17, replaces the 11-16 no-voice rule): voiced cut only, in the user's voice (voice/<lang>-<n>.wav
    # from 每日发布). No -novoice mp4 unless --novoice (music + text only, old behaviour) or --with-novoice (both).
    NOVOICE_ONLY = '--novoice' in args and not SYSTEM_VOICE
    WITH_NOVOICE = '--with-novoice' in args
    if not ('--preview' in args or SYSTEM_VOICE or NOVOICE_ONLY): check_voice()
    times = [1.8, 5.1, 7.6, 9.4, 11.0, 13.5]
    pc = Image.new('RGB', (480 * 3, 270 * 2)); ph = Image.new('RGB', (270 * 6, 480))
    for k, t in enumerate(times):
        pc.paste(frame(t)[0].resize((480, 270)), (480 * (k % 3), 270 * (k // 3)))
        ph.paste(vframe(t).resize((270, 480)), (270 * k, 0))
    tag = f'{KEY}-{h.LANG}'
    pc.save(OUTDIR / f'storyboard-{tag}-pc.jpg', quality=90); ph.save(OUTDIR / f'storyboard-{tag}-phone.jpg', quality=90)
    if '--preview' in args: return
    if SYSTEM_VOICE:                       # only for re-rendering pre-2026-11-15 videos
        voice, rate = ('Tingting', '200') if h.LANG == 'zh' else ('Samantha', '185')
        for k, line in enumerate(S['voice']):
            subprocess.run(['say', '-v', voice, '-r', rate, '-o', str(voice_file(k)), line], check=True)
    audio, music = OUTDIR / f'soundtrack-{tag}.wav', OUTDIR / f'soundtrack-{tag}-novoice.wav'
    soundtrack(audio, music, voiced=not NOVOICE_ONLY)
    for fn, size, kind in (() if '--phone-only' in args else ((pc_bytes, (W, H), 'pc'),)) + (() if '--pc-only' in args else ((phone_bytes, (VW, VH), 'phone'),)):
        out = OUTDIR / f'glance-widget-{tag}-{kind}.mp4'
        if NOVOICE_ONLY:
            encode(fn, size, music, OUTDIR / f'glance-widget-{tag}-{kind}-novoice.mp4'); continue
        encode(fn, size, audio, out)
        if WITH_NOVOICE: subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(out), '-i', str(music), '-map', '0:v', '-map', '1:a', '-c:v', 'copy',
                        '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart',
                        str(OUTDIR / f'glance-widget-{tag}-{kind}-novoice.mp4')], check=True)
    lines = [f"{h.L('Glance Widget daily', 'Glance Widget 日更')} · {S['menu_label']} · {DURATION}s",
             (h.L('Original voice: macOS Samantha, rate 185', '原配音：Mac 婷婷，语速 200') if SYSTEM_VOICE else h.L("Original voice: user's voice (local F5-TTS)", '原配音：用户指定音色（本地 F5-TTS）')), '']
    for k, (at, line) in enumerate(zip(VOICE_AT, S['voice'])):
        end = SCENES_AT[k + 1] if k + 1 < len(SCENES_AT) else DURATION
        lines.append(f'{k + 1}. {at:05.2f}s – {end:05.2f}s  {line}')
    sp = ' ' if h.LANG == 'en' else ''
    lines += ['', h.L('On-screen text:', '画面大字：'),
              f"{SCENES_AT[0]:05.2f}s – {SCENES_AT[1]:05.2f}s  {S['hook'][0]}{sp}{S['hook'][1]}",
              f"{SCENES_AT[1]:05.2f}s – {SCENES_AT[2]:05.2f}s  {S['demo'][0]}{sp}{S['demo'][1]}  [{h.L('Right-click', '右键')} → Widget → {S['menu_label']}]",
              f"{SCENES_AT[2]:05.2f}s – {SCENES_AT[3]:05.2f}s  {S['result'][0]}{sp}{S['result'][1]}  ({S['detail']})",
              f"{SCENES_AT[3]:05.2f}s – {DURATION:05.2f}s  Glance · {S['tagline']} · Widget · {S['menu_label']} · {h.L('Mac app · Made for Mac', 'Mac 电脑软件 · 为 Mac 打造')}",
              h.L('Corner label: Animated demo · Example effect', '角标：产品动效示意 · 示例效果')]
    (OUTDIR / f'narration-{h.LANG}.txt').write_text('\n'.join(lines) + '\n')
    print('done')


if __name__ == '__main__':
    main()
