"""Glance Widget tutorial: 高清放大 (Upscale). Composed from the current Figma UI
exports with Chinese narration (macOS `say`, Tingting) and subtitles.
Run: /private/tmp/glance-promo-venv/bin/python outputs/glance-upscale-tutorial/render.py [--preview]
"""
from pathlib import Path
from functools import lru_cache
import math, subprocess, wave, argparse, multiprocessing as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
A = OUT / 'assets'
VOICE = OUT / 'voice'
W, H, FPS = 1920, 1080, 30
WHITE = (243, 238, 232); GRAY = (170, 164, 160); DIM = (114, 109, 105)
WARM = (232, 168, 124); INK = (33, 19, 13); SURFACE = (17, 17, 20); GREEN = (143, 208, 175)
PF = '/System/Library/AssetsV2/com_apple_MobileAsset_Font7/3419f2a427639ad8c8e139149a287865a90fa17e.asset/AssetData/PingFang.ttc'
FONTS = {'r': (PF, 3), 'm': (PF, 7), 's': (PF, 11), 'en': ('/System/Library/Fonts/SFNS.ttf', 0), 'mono': ('/System/Library/Fonts/Menlo.ttc', 0)}

# ---------- narration timeline ----------
SEG_DUR = [9.82, 17.37, 12.79, 15.85, 20.44, 15.53, 18.29]
SCENE_START = [0, 11.0, 29.6, 43.6, 60.6, 82.2, 98.8]
LEAD = 0.6
DURATION = 118.6
SCRIPT = [l.strip() for l in (VOICE / 'script.txt').read_text().splitlines() if l.strip()]

def clamp(v): return max(0, min(1, v))
def ease(v): return 1 - (1 - clamp(v)) ** 3
def smooth(v):
    v = clamp(v); return v * v * (3 - 2 * v)
def lerp(a, b, v): return a + (b - a) * v
@lru_cache(None)
def font(size, fam='r'):
    p, i = FONTS[fam]; return ImageFont.truetype(p, size, index=i)
def txt(im, xy, s, size, color=WHITE, fam='r', anchor=None):
    ImageDraw.Draw(im).text(xy, s, font=font(size, fam), fill=color, anchor=anchor)
def tw(s, size, fam='r'): return font(size, fam).getlength(s)
def put(im, layer, xy, alpha=1):
    if alpha <= 0: return
    if alpha < 1:
        layer = layer.copy(); layer.putalpha(layer.getchannel('A').point(lambda v: round(v * alpha)))
    im.alpha_composite(layer, (round(xy[0]), round(xy[1])))
def rounded(src, size, radius=12):
    p = ImageOps.fit(src, size, method=Image.Resampling.LANCZOS).convert('RGBA')
    m = Image.new('L', size); ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    p.putalpha(m); return p
def rrect(im, box, radius, fill=None, outline=None, width=1):
    ImageDraw.Draw(im).rounded_rectangle(box, radius, fill=fill, outline=outline, width=width)
@lru_cache(None)
def shadow(size, blur=26, alpha=150, pad=60):
    p = Image.new('RGBA', (size[0] + pad * 2, size[1] + pad * 2))
    ImageDraw.Draw(p).rounded_rectangle((pad, pad + 10, size[0] + pad, size[1] + pad + 10), 24, fill=(0, 0, 0, alpha))
    return p.filter(ImageFilter.GaussianBlur(blur))
def cover(im, box, color): ImageDraw.Draw(im).rectangle(box, fill=color)
def relabel(im, box, s, size, color, fam='r', bg=None, align='l'):
    """Replace a Figma text node: cover its frame, draw text vertically centred in it."""
    x, y, w, h = box
    if bg is not None: cover(im, (x, y, x + w, y + h), bg)
    cy = y + h / 2
    if align == 'l': txt(im, (x, cy), s, size, color, fam, 'lm')
    elif align == 'r': txt(im, (x + w, cy), s, size, color, fam, 'rm')
    else: txt(im, (x + w / 2, cy), s, size, color, fam, 'mm')
def wrap(s, size, width, fam='r'):
    lines, cur = [], ''
    for ch in s:
        if tw(cur + ch, size, fam) > width: lines.append(cur); cur = ch
        else: cur += ch
    if cur: lines.append(cur)
    return lines
def sample(im, xy): return im.convert('RGB').getpixel(xy)
def dominant(im, box=None):
    a = np.array((im.crop(box) if box else im).convert('RGB')).reshape(-1, 3)
    vals, counts = np.unique(a, axis=0, return_counts=True); return tuple(int(v) for v in vals[counts.argmax()])

# ---------- source assets ----------
focus = Image.open(ROOT / 'layout/brand-assets/focus-alpine.png').convert('RGBA')
compare_src = Image.open(ROOT / 'layout/brand-assets/compare-alpine.png').convert('RGBA').crop((48, 30, 1602, 1042))
market_src = Image.open(A / 'market.png').convert('RGBA')
logo = Image.open(A / 'logo-character.png').convert('RGBA')
lake = Image.open(ROOT / 'layout/brand-assets/glance-alpine-after.png').convert('RGB')
lake2 = Image.open(ROOT / 'layout/brand-assets/glance-alpine-before.png').convert('RGB')
portrait = Image.open(ROOT / 'layout/brand-assets/glance-alpine-before.png').convert('RGB')
def soften(img, f=3.2):
    small = img.resize((max(1, round(img.width / f)), max(1, round(img.height / f))), Image.Resampling.BOX)
    return small.resize(img.size, Image.Resampling.BICUBIC)
portrait_soft = soften(portrait)
small_logo = rounded(logo, (56, 56), 15)

# Inspect window geometry in the 1554x1012 Figma frame.
CANVAS = (360, 0, 1290, 1012)
TOOLBAR = {'focus': (672, 50), 'compare': (726, 50), 'slider': (777, 50), 'grid': (830, 50), 'more': (881, 50)}
TOOLBAR_BOX = (630, 14, 925, 86)
STRIP_Y = 893
TILE_Y, TILE_W, PITCH = 906, 94, 106
tile_sel = focus.crop((623, 906, 717, 1000))
tile_new = focus.crop((729, 906, 823, 1000))
tile_plain = focus.crop((835, 906, 929, 1000))
badge_new = tile_new.crop((49, 66, 92, 89))

def tile(kind, thumb, badge=None):
    base = {'sel': tile_sel, 'new': tile_new, 'plain': tile_plain}[kind].copy()
    put(base, rounded(thumb, (TILE_W - 12, TILE_W - 12), 6), (6, 6))
    if badge == 'NEW': put(base, badge_new, (49, 66))
    elif badge:
        rrect(base, (49, 66, 91, 88), 5, fill=(16, 32, 24))
        txt(base, (70, 77), badge, 11, GREEN, 's', 'mm')
    return base

def canvas_fill(img):
    """Aspect-fit `img` into the canvas over a blurred fill, like Image Inspect."""
    size = (CANVAS[2] - CANVAS[0], CANVAS[3] - CANVAS[1])
    bg = ImageOps.fit(img, size, method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(30))
    fit = ImageOps.contain(img, size, method=Image.Resampling.LANCZOS)
    bg.paste(fit, ((size[0] - fit.width) // 2, (size[1] - fit.height) // 2))
    return bg.convert('RGBA')

@lru_cache(None)
def inspect_screen(canvas, tiles):
    """canvas: 'soft' | 'sharp' | 'lake'. tiles: tuple of (kind, thumb, badge)."""
    im = focus.copy()
    if canvas == 'soft':
        region = focus.crop(CANVAS).convert('RGB'); im.paste(soften(region, 3.0), CANVAS[:2])
    elif canvas == 'lake':
        im.paste(canvas_fill(lake), CANVAS[:2])
    im.paste(focus.crop(TOOLBAR_BOX), TOOLBAR_BOX[:2])
    im.paste(focus.crop((0, STRIP_Y, 1554, 1012)), (0, STRIP_Y))
    thumbs = {'src': portrait_soft, 'res': portrait, 'lake': lake, 'lake2': lake2}
    n = len(tiles); x0 = round(777 - (TILE_W + PITCH * (n - 1)) / 2)
    for i, (kind, th, badge) in enumerate(tiles):
        put(im, tile(kind, thumbs[th], badge), (x0 + PITCH * i, TILE_Y))
    return im

TILES_BEFORE = (('sel', 'src', None), ('plain', 'lake', None), ('plain', 'lake2', None))
def tiles_running(p, focused_src=True):
    return (('sel', 'src', f'{min(99, p)}%'), ('sel' if not focused_src else 'plain', 'lake', None), ('plain', 'lake2', None))
TILES_AFTER = (('plain', 'src', None), ('sel', 'res', 'NEW'), ('plain', 'lake', None), ('plain', 'lake2', None))

def running_border(im, alpha):
    glow = Image.new('RGBA', (1554, 1012))
    rrect(glow, (CANVAS[0] + 6, 6, CANVAS[2] - 6, 1006), 12, outline=(*WARM, 255), width=6)
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    put(im, glow, (0, 0), 0.28 * alpha)
    line = Image.new('RGBA', (1554, 1012))
    rrect(line, (CANVAS[0] + 6, 6, CANVAS[2] - 6, 1006), 12, outline=(*WARM, 204), width=2)
    put(im, line, (0, 0), alpha)
    d = ImageDraw.Draw(im)
    dot_a = round(255 * (0.55 + 0.45 * alpha))
    d.ellipse((CANVAS[0] + 14, 1012 - 30, CANVAS[0] + 30, 1012 - 14), fill=(94, 200, 140, dot_a))

# ---------- context menu (ActionMenuPanel, 216 wide, 26 rows) ----------
def menu(entries, highlight=None):
    rows = [e for e in entries]
    h = 12 + sum(9 if e is None else 26 for e in rows)
    p = Image.new('RGBA', (216, h))
    rrect(p, (0, 0, 215, h - 1), 10, fill=(*SURFACE, 252), outline=(243, 238, 232, 26))
    y = 6
    for e in rows:
        if e is None:
            ImageDraw.Draw(p).line((12, y + 4, 204, y + 4), fill=(243, 238, 232, 26)); y += 9; continue
        title, extra, sub = e
        hl = title == highlight
        if hl: rrect(p, (6, y, 210, y + 26), 5, fill=WARM)
        col = INK if hl else WHITE
        txt(p, (16, y + 13), title, 13, col, 'm', 'lm')
        if sub: txt(p, (196, y + 13), '›', 14, col, 'm', 'rm')
        elif extra: txt(p, (204, y + 13), extra, 12, INK if hl else GRAY, 'en', 'rm')
        y += 26
    return p
MAIN_MENU = [('Widget', None, True), None, ('复制图片', '⌘C', False), ('编辑', None, True), ('导出', None, True), ('工具', None, True), None, ('在 Finder 中显示', None, False), ('图片信息', '⌘I', False)]
WIDGET_SUB = [('高清放大 · 每次 1 积分', None, False), None, ('Widget 市场…', None, False)]
EXPORT_SUB = [('存储为 PNG…', None, False), ('存储为 JPG…', None, False), ('存储为 WebP…', None, False), ('Save as Icon…', None, False)]
def row_y(entries, title):
    y = 6
    for e in entries:
        if e is None: y += 9; continue
        if e[0] == title: return y
        y += 26
    return y

# ---------- Widget Market panel, localised ----------
MARKET_ROWS = [  # (name, summary, author, version, official, state)
    ('人物背景分离', '把人物从背景中精准分离，保留发丝细节。', 'Glance', 'v1.0.1', True, 'installed'),
    ('高清放大', '提升图片分辨率，让细节更清晰。', 'Glance', 'v1.0.1', True, 'install'),
    ('图生图', '重新生成图片，并按指定画幅比例输出。', 'Allan', 'v0.1.2', False, 'update'),
    ('视频去水印', '将较长视频分段去水印，按原顺序合成。', 'Allan', 'v0.2.2', False, 'installed'),
    ('AI 换装', '把第二张图的服装穿到第一张图的人物上。', 'Allan', 'v0.1.1', False, 'update'),
    ('智能扩图', '向四周延展画面，自动补全图片之外的内容。', 'Allan', 'v0.1.1', False, 'update'),
]
btn_install = Image.open(A / 'btn-install.png').convert('RGBA')
btn_installed = Image.open(A / 'btn-installed.png').convert('RGBA')
def market_button(state):
    if state == 'installed':
        b = btn_installed.copy(); cover(b, (6, 6, 82, 26), (40, 50, 50)); txt(b, (44, 16), '已安装', 12, GREEN, 's', 'mm')
    elif state == 'install':
        b = btn_install.copy(); cover(b, (4, 4, 72, 28), WARM); txt(b, (38, 16), '安装', 12, INK, 's', 'mm')
    else:
        b = btn_install.copy(); cover(b, (4, 4, 72, 28), WARM); txt(b, (38, 16), '更新', 12, INK, 's', 'mm')
    return b
@lru_cache(None)
def market_panel(upscale_state):
    p = market_src.copy(); bg = (11, 12, 15); rowbg = (23, 24, 29)
    relabel(p, (0, 12, 448, 16), 'Widget 市场', 13, WHITE, 's', bg, 'c')
    relabel(p, (0, 31, 448, 13), '9 个可用  ·  8 个已安装  ·  5 个更新', 11, GRAY, 'r', bg, 'c')
    relabel(p, (62, 78, 300, 16), '搜索 9 个 Widget', 13, DIM, 'r', (20, 21, 26))
    for (x, w, lab, cnt, col) in [(24, 114, '市场', '9', WARM), (146, 100, '已安装', '8', GRAY), (254, 86, '更新', '5', GRAY)]:
        fill = sample(p, (x + 6, 133))
        relabel(p, (x + 12, 125, w - 24, 15), lab, 12, col, 'm', fill)
        relabel(p, (x + w - 30, 125, 18, 15), cnt, 12, col, 'm', None, 'r')
    for i, (name, summ, author, ver, official, state) in enumerate(MARKET_ROWS):
        y = 166 + 92 * i
        if i == 1: state = upscale_state
        cover(p, (24 + 72, y + 12, 24 + 300, y + 72), rowbg)
        txt(p, (96, y + 22), name, 13, WHITE, 's', 'lm')
        for j, line in enumerate(wrap(summ, 11, 220)[:2]): txt(p, (96, y + 34 + j * 12), line, 11, GRAY, 'r')
        mx = 96
        if official:
            ImageDraw.Draw(p).ellipse((96, y + 63, 103, y + 70), fill=GREEN); mx = 108
        txt(p, (mx, y + 66), f'{author} · {ver} · 1 个命令', 10, DIM, 'r', 'lm')
        cover(p, (24 + 296, y + 24, 24 + 392, y + 60), rowbg)
        b = market_button(state); put(p, b, (24 + 388 - b.width, y + 26))
    relabel(p, (24, 802, 230, 13), '9 个 Widget  •  市场', 11, DIM, 'r', bg)
    relabel(p, (298, 802, 126, 13), '滚动查看更多', 11, DIM, 'r', bg, 'r')
    return p
MARKET_POS = (553, 94)
def market_install_btn_center(): return (MARKET_POS[0] + 24 + 350, MARKET_POS[1] + 258 + 42)

# ---------- Task Center, localised and composed from the board parts ----------
tc_list = Image.open(A / 'tc-list.png').convert('RGBA')
tc_source = Image.open(A / 'tc-source.png').convert('RGBA')
tc_result = Image.open(A / 'tc-result.png').convert('RGBA')
tc_timeline = Image.open(A / 'tc-timeline.png').convert('RGBA')
tc_details = Image.open(A / 'tc-details.png').convert('RGBA')
tc_cancel = Image.open(A / 'tc-cancel.png').convert('RGBA')
tc_show = Image.open(A / 'tc-showsource.png').convert('RGBA')
tc_lights = Image.open(A / 'tc-lights.png').convert('RGBA')
chips = {k: Image.open(A / f'chip-{k}.png').convert('RGBA').crop((30, 20, 390, 96)) for k in ['1', '2', '3', '4', 'done']}
def chip(kind, dots_t=0):
    c = chips[kind].copy(); fill = sample(c, (200, 8))
    if kind == 'done':
        cover(c, (84, 10, 300, 32), fill); txt(c, (84, 21), '完成', 13, WHITE, 's', 'lm'); txt(c, (84 + tw('完成', 13, 's') + 10, 21), '✓', 13, GREEN, 'm', 'lm')
        cover(c, (84, 34, 340, 52), fill); txt(c, (84, 43), '高清放大 · 12.4 s', 11, GRAY, 'r', 'lm')
    else:
        cover(c, (84, 10, 300, 32), fill); txt(c, (84, 21), '生成中', 13, WHITE, 's', 'lm')
        x = 84 + tw('生成中', 13, 's') + 8
        for k in range(3):
            a = 0.35 + 0.65 * (0.5 + 0.5 * math.sin((dots_t * 3 - k * 0.9)))
            ImageDraw.Draw(c).ellipse((x + k * 8, 24, x + k * 8 + 4, 28), fill=(243, 238, 232, round(255 * a)))
        cover(c, (84, 34, 340, 52), fill); txt(c, (84, 43), '高清放大', 11, GRAY, 'r', 'lm')
    return c
def relabel_list_row(p, y, title, detail, state, text_col):
    rowbg = sample(p, (200, y + 60))
    relabel(p, (96, y + 17, 150, 16), title, 13, WHITE, 's', rowbg)
    relabel(p, (96, y + 43, 170, 13), detail, 11, GRAY, 'r', rowbg)
    cfill = sample(p, (14 + 254, y + 41))
    relabel(p, (14 + 254, y + 32, 62, 18), state, 11, text_col, 'm', cfill, 'c')
@lru_cache(None)
def task_center_base():
    im = Image.new('RGBA', (1554, 1012), (11, 12, 15, 255))
    put(im, tc_lights, (20, 16))
    txt(im, (777, 20), '任务中心', 13, WHITE, 's', 'mm'); txt(im, (777, 37), '3 个任务  •  1 个进行中', 11, GRAY, 'r', 'mm')
    lst = tc_list.copy(); lbg = (14, 15, 19)
    relabel(lst, (24, 22, 100, 21), '任务', 17, WHITE, 's', lbg)
    relabel(lst, (62, 78, 200, 16), '搜索任务', 13, DIM, 'r', sample(lst, (200, 86)))
    for (x, w, lab, cnt, col) in [(24, 58, '全部', '3', WARM), (90, 86, '进行中', '1', GRAY), (184, 65, '完成', '1', GRAY), (257, 79, '失败', '1', GRAY)]:
        fill = sample(lst, (x + 5, 133)); relabel(lst, (x + 10, 125, w - 20, 15), lab, 12, col, 'm', fill); relabel(lst, (x + w - 24, 125, 14, 15), cnt, 12, col, 'm', None, 'r')
    relabel_list_row(lst, 166, '高清放大', '刚刚 · alpine-lake.jpg', '运行中…', WARM)
    relabel_list_row(lst, 258, '人物背景分离', '12 分钟前 · input.png', '完成', GREEN)
    relabel_list_row(lst, 350, '图片转提示词', '昨天 · product.webp', '失败', (241, 139, 134))
    # Row thumbnails: a soft portrait under the running scrim, plain thumbs below.
    peek = lst.crop((38, 189, 70, 221)); scrim = sample(lst, (30, 182))
    for ry, th in [(166, portrait_soft), (258, lake), (350, lake2)]:
        put(lst, rounded(th, (56, 56), 6), (26, ry + 13))
    ov = Image.new('RGBA', (56, 56)); rrect(ov, (0, 0, 55, 55), 6, fill=(*scrim, 215)); put(lst, ov, (26, 179))
    pm = np.array(peek.convert('RGB')).astype(int); mask = (np.abs(pm - np.array(scrim)).sum(axis=2) > 30).astype(np.uint8) * 255
    peek.putalpha(Image.fromarray(mask)); put(lst, peek, (38, 189))
    put(im, lst, (0, 52))
    txt(im, (392, 89), '高清放大', 17, WHITE, 's', 'lm')
    show = tc_show.copy(); cover(show, (36, 8, 125, 28), dominant(show, (30, 6, 125, 30))); txt(show, (74, 18), '查看源图', 12, WHITE, 'm', 'lm')
    put(im, show, (1554 - 48 - 94 - 8 - 129 + 0, 76))
    can = tc_cancel.copy(); cover(can, (36, 8, 86, 28), dominant(can, (30, 6, 88, 30))); txt(can, (58, 18), '取消', 12, (241, 139, 134), 'm', 'lm')
    put(im, can, (1428, 76))
    src = tc_source.copy(); put(src, rounded(portrait_soft, (532, 336), 8), (12, 12))
    sh = Image.new('RGBA', (532, 60)); ImageDraw.Draw(sh).rectangle((0, 20, 532, 60), fill=(0, 0, 0, 110)); sh = sh.filter(ImageFilter.GaussianBlur(10)); put(src, sh, (12, 290))
    txt(src, (18, 328), '来源 · alpine-lake.jpg', 10, WHITE, 'm', 'lm')
    put(im, src, (392, 152))
    tl = tc_timeline.copy(); tbg = (16, 17, 21)
    relabel(tl, (24, 20, 100, 16), '时间线', 13, WHITE, 's', tbg)
    for (y, t1, t2, tm, cur) in [(60, '任务已提交', '客户端已上传源图', '14:32:06', False), (132, 'Worker 已领取', 'GPU Worker eu-02', '14:32:08', False), (204, '处理中', '每 2 秒轮询一次', '现在', True), (276, '下载结果', '等待输出文件', '等待中', False)]:
        relabel(tl, (58, y, 240, 16), t1, 13, WHITE, 'm', tbg); relabel(tl, (58, y + 22, 240, 13), t2, 11, GRAY, 'r', tbg)
        relabel(tl, (420, y + 3, 120, 13), tm, 11, WARM if cur else DIM, 'r', tbg, 'r')
    put(im, tl, (392, 542))
    dt = tc_details.copy()
    relabel(dt, (24, 20, 120, 16), '任务详情', 13, WHITE, 's', tbg)
    for i, (k, v) in enumerate([('Widget', '高清放大'), ('输入', 'alpine-lake.jpg'), ('Worker', 'eu-02'), ('进度', ''), ('轮询', '2 秒')]):
        y = 60 + 38 * i
        relabel(dt, (36, y, 120, 16), k, 12, GRAY, 'r', tbg); relabel(dt, (174, y, 220, 16), v, 12, WHITE, 'r', tbg)
    put(im, dt, (966, 542))
    return im
def task_center(progress, chip_kind, dots_t):
    im = task_center_base().copy()
    res = tc_result.copy(); put(res, chip(chip_kind, dots_t), (98, 142)); put(im, res, (966, 152))
    cover(im, (392, 98, 900, 116), (11, 12, 15))
    x = 392
    for s, col in [('任务 7E20', DIM), ('  •  ', DIM), ('进行中' if chip_kind != 'done' else '完成', WARM if chip_kind != 'done' else GREEN), ('  •  ', DIM), (f'{progress}%', DIM)]:
        txt(im, (x, 107), s, 11, col, 'r', 'lm'); x += tw(s, 11)
    relabel(im, (966 + 174, 542 + 60 + 38 * 3, 220, 16), f'{progress}%', 12, WHITE, 'r', (16, 17, 21))
    return im

# ---------- compare screen ----------
@lru_cache(None)
def compare_screen():
    im = compare_src.copy()
    face_soft = ImageOps.fit(portrait_soft.crop((150, 0, 780, 560)), (777, 1012), method=Image.Resampling.LANCZOS)
    face_sharp = ImageOps.fit(portrait.crop((150, 0, 780, 560)), (777, 1012), method=Image.Resampling.LANCZOS)
    im.paste(face_soft, (0, 0)); im.paste(face_sharp, (777, 0))
    ImageDraw.Draw(im).line((777, 0, 777, 1012), fill=(243, 238, 232, 140), width=2)
    im.paste(compare_src.crop(TOOLBAR_BOX), TOOLBAR_BOX[:2])
    im.paste(focus.crop((0, STRIP_Y, 1554, 1012)), (0, STRIP_Y))
    thumbs = {'src': portrait_soft, 'res': portrait, 'lake': lake, 'lake2': lake2}
    tiles = (('sel', 'src', None), ('sel', 'res', 'NEW'), ('plain', 'lake', None), ('plain', 'lake2', None))
    x0 = round(777 - (TILE_W + PITCH * 3) / 2)
    for i, (kind, th, badge) in enumerate(tiles): put(im, tile(kind, thumbs[th], badge), (x0 + PITCH * i, TILE_Y))
    return im

# ---------- in-screen overlays ----------
def notification(im, alpha, dx):
    p = Image.new('RGBA', (372, 78))
    rrect(p, (0, 0, 371, 77), 18, fill=(44, 44, 48, 238), outline=(255, 255, 255, 34))
    put(p, rounded(logo, (46, 46), 11), (14, 16))
    txt(p, (74, 20), 'Glance', 12, WHITE, 's', 'lm'); txt(p, (355, 20), '现在', 10, GRAY, 'r', 'rm')
    txt(p, (74, 40), 'Widget 已完成', 12, WHITE, 'r', 'lm'); txt(p, (74, 58), 'alpine-lake.高清放大.png', 11, GRAY, 'r', 'lm')
    put(im, shadow((372, 78), 18, 120, 40), (1554 - 372 - 16 + dx - 40, 12 - 40), alpha * 0.8)
    put(im, p, (1554 - 372 - 16 + dx, 12), alpha)
def toast(im, text, alpha, rise):
    w = round(tw(text, 13, 'm')) + 44
    p = Image.new('RGBA', (w, 40)); rrect(p, (0, 0, w - 1, 39), 20, fill=(*SURFACE, 240), outline=(243, 238, 232, 30))
    txt(p, (w / 2, 20), text, 13, WHITE, 'm', 'mm')
    put(im, p, (777 - w / 2, 836 + 14 * (1 - rise)), alpha)
def callout_ring(im, cx, cy, r, alpha):
    p = Image.new('RGBA', (1554, 1012)); ImageDraw.Draw(p).ellipse((cx - r, cy - r, cx + r, cy + r), outline=WARM, width=3); put(im, p, (0, 0), alpha)

# ---------- video frame chrome ----------
yy, xx = np.mgrid[:H, :W]
g = np.exp(-(((xx - 1330) / 720) ** 2 + ((yy - 550) / 720) ** 2))
g2 = np.exp(-(((xx - 80) / 950) ** 2 + ((yy - 1100) / 720) ** 2))
grain = np.random.default_rng(45).normal(0, .36, (H, W))
BG = Image.fromarray(np.uint8(np.clip(np.stack([9 + 12 * g + 3 * g2 + grain, 10 + 8 * g + 3 * g2 + grain, 14 + 7 * g + 5 * g2 + grain], axis=-1), 0, 255))).convert('RGBA')
STEPS = ['', '打开图片', '安装 Widget', '运行高清放大', '等待结果', '查看结果', '保存与导出']
def header(im, step):
    put(im, rounded(logo, (40, 40), 11), (104, 22))
    txt(im, (158, 42), 'Glance', 26, WHITE, 'en', 'lm')
    txt(im, (270, 43), '高清放大 Widget · 使用教程', 17, GRAY, 'r', 'lm')
    if step:
        label = f'{step:02d} / 06   {STEPS[step]}'
        txt(im, (1816, 42), label, 18, WARM, 'm', 'rm')
        d = ImageDraw.Draw(im)
        for i in range(6): d.rounded_rectangle((1816 - 6 * 34 + i * 34, 60, 1816 - 6 * 34 + i * 34 + 26, 63), 2, fill=WARM if i < step else (60, 57, 58))
CARD = (270, 86, 1380, 898)
def card(im, screen, cam, alpha=1):
    cx, cy, zoom = cam
    vw, vh = 1554 / zoom, 1012 / zoom
    cx = min(max(cx, vw / 2), 1554 - vw / 2); cy = min(max(cy, vh / 2), 1012 - vh / 2)
    box = (cx - vw / 2, cy - vh / 2, cx + vw / 2, cy + vh / 2)
    view = screen.crop(tuple(round(v) for v in box)).resize((CARD[2], CARD[3]), Image.Resampling.LANCZOS if zoom <= 1.001 else Image.Resampling.BICUBIC)
    m = Image.new('L', view.size); ImageDraw.Draw(m).rounded_rectangle((0, 0, view.width - 1, view.height - 1), 18, fill=255); view.putalpha(m)
    put(im, shadow((CARD[2], CARD[3])), (CARD[0] - 60, CARD[1] - 60), alpha)
    put(im, view, (CARD[0], CARD[1]), alpha)
    s = CARD[2] / vw
    return lambda sx, sy: (CARD[0] + (sx - box[0]) * s, CARD[1] + (sy - box[1]) * s)
def cursor(im, x, y, pulse=0, alpha=1):
    p = Image.new('RGBA', (160, 160)); d = ImageDraw.Draw(p)
    if pulse:
        r = round(14 + 44 * pulse); d.ellipse((80 - r, 80 - r, 80 + r, 80 + r), outline=(*WARM, round(200 * (1 - pulse))), width=3)
    d.polygon([(80, 80), (80, 113), (90, 104), (98, 121), (105, 117), (97, 101), (114, 101)], fill=WHITE, outline=(12, 13, 16), width=2)
    put(im, p, (x - 80, y - 80), alpha)
def move(a, b, t): return (lerp(a[0], b[0], smooth(t)), lerp(a[1], b[1], smooth(t)))
def cam_move(a, b, t): return tuple(lerp(a[i], b[i], smooth(t)) for i in range(3))
CAM0 = (777, 506, 1.0)

def margin_notes(im, notes, t, x=56, y=420):
    for i, (when, icon, text) in enumerate(notes):
        a = ease((t - when) / .45)
        if a <= 0: continue
        p = Image.new('RGBA', (200, 96))
        txt(p, (0, 4), icon, 22, WARM, 'en')
        for j, line in enumerate(wrap(text, 16, 198)[:2]): txt(p, (0, 42 + j * 23), line, 16, WHITE, 'm')
        put(im, p, (x, y + i * 118 + 12 * (1 - a)), a)
def key_chip(im, keys, xy, pressed):
    w = round(tw(keys, 22, 'en')) + 70
    p = Image.new('RGBA', (w, 60))
    rrect(p, (0, 0, w - 1, 59), 14, fill=(round(25 + 35 * pressed), round(25 + 18 * pressed), 28), outline=WARM, width=2)
    txt(p, (w / 2, 30), keys, 22, WHITE, 'en', 'mm')
    put(im, p, xy)

# ---------- subtitles ----------
def split_lines(s):
    parts, cur = [], ''
    for ch in s:
        cur += ch
        if ch in '。，！？；':
            parts.append(cur); cur = ''
    if cur: parts.append(cur)
    lines, cur = [], ''
    for part in parts:
        if cur and len(cur) + len(part) > 24: lines.append(cur); cur = part
        else: cur += part
    if cur: lines.append(cur)
    return [l.rstrip('，。') for l in lines]
SUBS = []
for i, seg in enumerate(SCRIPT):
    lines = split_lines(seg); total = sum(len(l) for l in lines); t0 = SCENE_START[i] + LEAD
    for l in lines:
        d = SEG_DUR[i] * len(l) / total; SUBS.append((t0, t0 + d, l)); t0 += d
def subtitle(im, t):
    for (a, b, s) in SUBS:
        if a <= t < b:
            f = min(1, (t - a) / .2, (b - t) / .2 + .6)
            p = Image.new('RGBA', (W, 80)); txt(p, (W / 2 + 2, 42), s, 30, (0, 0, 0, 170), 'm', 'mm'); p = p.filter(ImageFilter.GaussianBlur(3))
            txt(p, (W / 2, 40), s, 30, WHITE, 'm', 'mm'); put(im, p, (0, 996), f); return

# ---------- scenes ----------
def s0(t):
    im = BG.copy(); header(im, 0)
    a = ease(t / .7)
    put(im, shadow((160, 160)), (960 - 80 - 60, 150 - 60 + 16 * (1 - a)), a)
    put(im, rounded(logo, (160, 160), 38), (880, 150 + 16 * (1 - a)), a)
    layer = Image.new('RGBA', (W, H))
    txt(layer, (960, 388), '高清放大', 96, WHITE, 's', 'mm')
    txt(layer, (960, 470), 'Glance Widget · 使用教程', 30, WARM, 'm', 'mm')
    put(im, layer, (0, 14 * (1 - a)), a)
    b = ease((t - 1.1) / .6)
    for i, (img, lab) in enumerate([(portrait_soft, '原图'), (portrait, '高清放大')]):
        crop = ImageOps.fit(img.crop((300, 40, 640, 300)), (520, 400), method=Image.Resampling.LANCZOS)
        p = rounded(crop, (520, 400), 20); x = 400 + i * 600
        put(im, shadow((520, 400)), (x - 60, 540 - 60), b); put(im, p, (x, 540 + 20 * (1 - b)), b)
        chipw = round(tw(lab, 18, 'm')) + 36; c = Image.new('RGBA', (chipw, 38)); rrect(c, (0, 0, chipw - 1, 37), 19, fill=(*SURFACE, 230)); txt(c, (chipw / 2, 19), lab, 18, WARM if i else WHITE, 'm', 'mm')
        put(im, c, (x + 18, 540 + 18 + 20 * (1 - b)), b)
    return im

def s1(t):
    im = BG.copy(); header(im, 1)
    show_card = ease((t - 5.0) / .7)
    if show_card < 1:
        a = ease(t / .6) * (1 - show_card)
        p = Image.new('RGBA', (1100, 520)); d = ImageDraw.Draw(p)
        d.rounded_rectangle((0, 0, 1099, 300), 28, fill=(23, 24, 30), outline=(65, 58, 53), width=2)
        txt(p, (48, 36), '在任何应用里选中图片路径', 24, GRAY)
        d.rounded_rectangle((46, 120, 1054, 190), 11, fill=(66, 48, 37))
        txt(p, (66, 134), '~/Pictures/alpine-lake.jpg', 34, WARM, 'mono')
        pressed = smooth((t - 3.4) / .25) * (1 - smooth((t - 4.4) / .3))
        key_chip(p, '⌥ Option  +  Space', (380, 380), pressed)
        put(im, p, (410, 300 + 24 * (1 - a)), a)
        cursor(im, 1360, 395, clamp((t - 3.3) / .4) if 3.3 < t < 3.7 else 0, a)
    if show_card > 0:
        screen = inspect_screen('soft', TILES_BEFORE)
        cam = (777, 506, lerp(.92, 1.0, show_card))
        card(im, screen, cam, show_card)
    margin_notes(im, [(5.6, '01', '选中路径，按 Option + Space'), (10.2, '02', '访达里右键，用 Glance 打开'), (14.0, '03', '把图片拖进 Glance 主页')], t)
    return im

def s2(t):
    im = BG.copy(); header(im, 2)
    screen = inspect_screen('soft', TILES_BEFORE).copy()
    open_a = ease((t - 1.3) / .45)
    if open_a > 0:
        state = 'installed' if t >= 5.45 else 'install'
        panel = market_panel(state)
        if 5.2 <= t < 5.45: panel = Image.blend(market_panel('install'), market_panel('installed'), smooth((t - 5.2) / .25))
        close_a = 1 - ease((t - 10.0) / .4)
        a = open_a * close_a
        put(screen, shadow((448, 824), 30, 170), (MARKET_POS[0] - 60, MARKET_POS[1] - 60 + 10 * (1 - a)), a)
        put(screen, panel, (MARKET_POS[0], MARKET_POS[1] + 10 * (1 - a)), a)
    if t < 1.3 + .2: callout_ring(screen, *TOOLBAR['grid'], 24, smooth((t - .2) / .3) * (1 - smooth((t - 1.2) / .25)))
    zoom_in = smooth((t - 1.6) / .8) * (1 - smooth((t - 8.6) / .8))
    cam = cam_move(CAM0, (777, 445, 1.3), zoom_in)
    tr = card(im, screen, cam)
    grid = TOOLBAR['grid']; btn = market_install_btn_center()
    if t < 1.3: pos = move((1000, 600), grid, (t - .2) / .9)
    elif t < 3.0: pos = grid
    elif t < 4.6: pos = move(grid, btn, (t - 3.0) / 1.4)
    elif t < 9.4: pos = btn
    else: pos = move(btn, (1000, 560), (t - 9.4) / .8)
    pulse = clamp((t - 1.2) / .4) if 1.2 < t < 1.6 else (clamp((t - 5.2) / .4) if 5.2 < t < 5.6 else 0)
    cursor(im, *tr(*pos), pulse)
    return im

def s3(t):
    im = BG.copy(); header(im, 3)
    running = t >= 6.5
    if running:
        p = min(12, 3 + int((t - 6.5) * 1.2))
        screen = inspect_screen('soft', tiles_running(p)).copy()
        running_border(screen, ease((t - 6.5) / .6) * (0.6 + 0.4 * math.sin(t * 3.5)))
    else:
        screen = inspect_screen('soft', TILES_BEFORE).copy()
    anchor = (980, 520)
    menu_a = ease((t - 1.8) / .22) * (1 - ease((t - 6.35) / .18))
    if menu_a > 0:
        hl = 'Widget' if 3.7 <= t else None
        m = menu(MAIN_MENU, hl); put(screen, m, anchor, menu_a)
        if t >= 4.0:
            sub_a = ease((t - 4.0) / .2)
            shl = '高清放大 · 每次 1 积分' if t >= 5.5 else None
            sm = menu(WIDGET_SUB, shl); put(screen, sm, (anchor[0] + 224, anchor[1] + row_y(MAIN_MENU, 'Widget') - 6), sub_a * menu_a)
    if 2.6 < t < 5.2: callout_ring(screen, *TOOLBAR['more'], 24, smooth((t - 2.6) / .3) * (1 - smooth((t - 4.8) / .3)))
    zoom = smooth((t - 2.0) / .7) * (1 - smooth((t - 7.4) / .8))
    cam = cam_move(CAM0, (1130, 560, 1.32), zoom)
    tr = card(im, screen, cam)
    widget_row = (anchor[0] + 60, anchor[1] + row_y(MAIN_MENU, 'Widget') + 13)
    sub_row = (anchor[0] + 224 + 70, anchor[1] + row_y(MAIN_MENU, 'Widget') - 6 + row_y(WIDGET_SUB, '高清放大 · 每次 1 积分') + 13)
    if t < 1.8: pos = move((760, 760), anchor, (t - .5) / 1.1)
    elif t < 3.0: pos = anchor
    elif t < 3.8: pos = move(anchor, widget_row, (t - 3.0) / .8)
    elif t < 4.6: pos = widget_row
    elif t < 5.6: pos = move(widget_row, sub_row, (t - 4.6) / 1.0)
    elif t < 7.6: pos = sub_row
    else: pos = move(sub_row, (1100, 700), (t - 7.6) / 1.0)
    pulse = clamp((t - 1.8) / .4) if 1.8 < t < 2.2 else (clamp((t - 6.3) / .4) if 6.3 < t < 6.7 else 0)
    cursor(im, *tr(*pos), pulse)
    return im

def s4(t):
    im = BG.copy(); header(im, 4)
    p = int(12 + 70 * smooth(t / 21.0))
    tc_a = ease((t - 11.5) / .6)
    if tc_a < 1:
        focused_src = t < 8.6
        screen = inspect_screen('lake' if not focused_src else 'soft', tiles_running(p, focused_src)).copy()
        if focused_src: running_border(screen, 0.6 + 0.4 * math.sin(t * 3.5))
        cam = CAM0
        tr = card(im, screen, cam, 1 - tc_a)
        tile2 = (729, 953)
        if t < 6.5: pos = (1100, 700)
        elif t < 8.0: pos = move((1100, 700), tile2, (t - 6.5) / 1.5)
        else: pos = tile2
        cursor(im, *tr(*pos), clamp((t - 8.4) / .4) if 8.4 < t < 8.8 else 0, 1 - tc_a)
    if tc_a > 0:
        cyc = ['1', '2', '3', '4', '2', '1']
        kind = cyc[int(t / .35) % len(cyc)]
        screen = task_center(p, kind, t)
        cam = cam_move(CAM0, (1244, 420, 1.3), smooth((t - 14.0) / .9) * (1 - smooth((t - 19.8) / .8)))
        card(im, screen, cam, tc_a)
    return im

def s5(t):
    im = BG.copy(); header(im, 5)
    cmp_a = ease((t - 8.0) / .5)
    if cmp_a < 1:
        screen = inspect_screen('sharp', TILES_AFTER).copy()
        na = ease((t - .3) / .4) * (1 - ease((t - 5.4) / .4))
        if na > 0: notification(screen, na, 40 * (1 - na))
        cam = cam_move(CAM0, (780, 860, 1.4), smooth((t - 1.6) / .8) * (1 - smooth((t - 5.0) / .8)))
        tr = card(im, screen, cam, 1 - cmp_a)
        cmpb = TOOLBAR['compare']
        if t < 6.4: pos = (1120, 640)
        elif t < 7.5: pos = move((1120, 640), cmpb, (t - 6.4) / 1.1)
        else: pos = cmpb
        cursor(im, *tr(*pos), clamp((t - 7.8) / .4) if 7.8 < t < 8.2 else 0, 1 - cmp_a)
    if cmp_a > 0:
        screen = compare_screen().copy()
        la = ease((t - 9.0) / .4)
        for i, lab in enumerate(['原图', '高清放大']):
            w = round(tw(lab, 15, 'm')) + 32; c = Image.new('RGBA', (w, 34)); rrect(c, (0, 0, w - 1, 33), 17, fill=(*SURFACE, 225)); txt(c, (w / 2, 17), lab, 15, WARM if i else WHITE, 'm', 'mm')
            put(screen, c, (24 + 777 * i, 104), la)
        cam = cam_move(CAM0, (777, 420, 1.18), smooth((t - 10.0) / 3.5))
        card(im, screen, cam, cmp_a)
    return im

def s6(t):
    im = BG.copy(); header(im, 6)
    end_a = ease((t - 12.6) / .7)
    if end_a < 1:
        screen = inspect_screen('sharp', TILES_AFTER).copy()
        anchor = (980, 520)
        menu_a = ease((t - 8.4) / .22) * (1 - ease((t - 12.4) / .3))
        if menu_a > 0:
            put(screen, menu(MAIN_MENU, '导出' if t >= 9.1 else None), anchor, menu_a)
            if t >= 9.3: put(screen, menu(EXPORT_SUB, None), (anchor[0] + 224, anchor[1] + row_y(MAIN_MENU, '导出') - 6), ease((t - 9.3) / .2) * menu_a)
        ta = ease((t - 5.2) / .3) * (1 - ease((t - 7.9) / .3))
        if ta > 0: toast(screen, '已保存 ✓  ~/Documents/Glance/alpine-lake.高清放大.png', ta, ease((t - 5.2) / .4))
        cam = cam_move(CAM0, (1130, 560, 1.32), smooth((t - 8.8) / .7) * (1 - smooth((t - 12.3) / .5)))
        tr = card(im, screen, cam, 1 - end_a)
        if 4.2 < t < 8.2:
            ka = ease((t - 4.2) / .3) * (1 - ease((t - 7.8) / .3))
            kp = Image.new('RGBA', (240, 60)); key_chip(kp, '⌘  +  S', (0, 0), smooth((t - 4.9) / .2) * (1 - smooth((t - 5.5) / .3)))
            put(im, kp, (56, 430), ka)
        margin_notes(im, [(0.5, '01', '已自动保存到 下载/Glance 文件夹')], t, 56, 300)
        exp_row = (anchor[0] + 60, anchor[1] + row_y(MAIN_MENU, '导出') + 13)
        if t < 8.4: pos = (1100, 700)
        elif t < 9.1: pos = move((1100, 700), exp_row, (t - 8.4) / .7)
        else: pos = exp_row
        if t > 8.0: cursor(im, *tr(*pos), clamp((t - 8.3) / .4) if 8.3 < t < 8.7 else 0, (1 - end_a) * ease((t - 8.0) / .3))
    if end_a > 0:
        layer = Image.new('RGBA', (W, H))
        icon = rounded(logo, (206, 206), 48)
        put(layer, shadow(icon.size), (797, 125), 1); put(layer, icon, (857, 185))
        txt(layer, (960, 504), 'Glance', 126, WHITE, 'en', 'mm')
        txt(layer, (960, 642), '高清放大 Widget · 一眼即见，继续创作。', 48, WARM, 's', 'mm')
        txt(layer, (960, 722), '安装一次，右键即用。', 27, GRAY, 'r', 'mm')
        txt(layer, (960, 841), '⌥  Option + Space', 29, WHITE, 'en', 'mm')
        put(im, layer, (0, 18 * (1 - end_a)), end_a)
    return im

SCENES = [s0, s1, s2, s3, s4, s5, s6]
def frame(t):
    idx = max(i for i, s in enumerate(SCENE_START) if s <= t)
    im = SCENES[idx](t - SCENE_START[idx])
    if idx and t - SCENE_START[idx] < .4:
        prev = SCENES[idx - 1](t - SCENE_START[idx - 1])
        im = Image.blend(prev, im, smooth((t - SCENE_START[idx]) / .4))
    subtitle(im, t)
    return im.convert('RGB')
def frame_bytes(i): return frame(i / FPS).tobytes()

# ---------- audio ----------
def audio():
    sr = 48000; n = int(sr * DURATION); sig = np.zeros((n, 2))
    for i, d in enumerate(SEG_DUR):
        with wave.open(str(VOICE / f'seg{i}.wav')) as f:
            data = np.frombuffer(f.readframes(f.getnframes()), dtype='<i2').reshape(-1, 2) / 32767
        at = int((SCENE_START[i] + LEAD) * sr); sig[at:at + len(data)] += data[:n - at] * 0.95
    def note(at, dur, hz, amp, pan=0):
        b = int(at * sr); L = min(int(dur * sr), n - b)
        if L <= 0: return
        tt = np.arange(L) / sr
        env = (1 - np.exp(-tt / .4)) * np.exp(-tt / 3.2) * np.clip((dur - tt) / .5, 0, 1)
        v = (np.sin(2 * np.pi * hz * tt) + .08 * np.sin(4 * np.pi * hz * tt)) * env * amp
        sig[b:b + L, 0] += v * (1 - pan * .3); sig[b:b + L, 1] += v * (1 + pan * .3)
    chords = [(130.81, 164.81, 196.0, 246.94), (110, 130.81, 164.81, 196.0), (87.31, 130.81, 174.61, 220), (98.0, 146.83, 196.0, 246.94)]
    bar = 0; at = 0
    while at < DURATION:
        for k, hz in enumerate(chords[bar % 4]): note(at, 5.2, hz, .012, (-1) ** k * .5); note(at + 1.2, 3.5, hz * 2, .004, (-1) ** k * .3)
        at += 4.8; bar += 1
    rng = np.random.default_rng(8)
    clicks = [SCENE_START[2] + 1.2, SCENE_START[2] + 5.2, SCENE_START[2] + 10.0, SCENE_START[3] + 1.8, SCENE_START[3] + 6.4, SCENE_START[4] + 8.5, SCENE_START[5] + 7.8, SCENE_START[6] + 8.3, SCENE_START[1] + 3.45]
    for c in clicks:
        i = int(c * sr); tt = np.arange(int(.06 * sr)) / sr; click = rng.normal(size=len(tt)) * np.exp(-tt * 110) * .05; sig[i:i + len(tt)] += click[:, None]
    for k, hz in enumerate((1046.5, 1318.5)):
        note(SCENE_START[5] + .35 + k * .12, 1.2, hz, .05, (-1) ** k * .4)
    tt = np.arange(n) / sr; sig *= (np.clip(tt / .2, 0, 1) * np.clip((DURATION - tt) / 1.2, 0, 1))[:, None]
    peak = np.max(np.abs(sig)); sig *= .9 / max(peak, .01)
    with wave.open(str(OUT / 'soundtrack.wav'), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(sr); f.writeframes((sig * 32767).astype('<i2').tobytes())

SAMPLES = [2.5, 15.5, 23.0, 36.0, 49.5, 54.5, 66.0, 76.0, 84.0, 93.0, 106.0, 114.0]
def previews():
    board = Image.new('RGB', (1920, 1080), (10, 11, 15))
    for i, t in enumerate(SAMPLES):
        im = frame(t); im.save(OUT / f'frame-{t:.1f}s.jpg', quality=92)
        board.paste(im.resize((480, 270), Image.Resampling.LANCZOS), ((i % 4) * 480, (i // 4) * 360))
        ImageDraw.Draw(board).text(((i % 4) * 480 + 14, (i // 4) * 360 + 274 + 50), f'{t:.1f}s', font=font(20, 'en'), fill=GRAY)
    board.save(OUT / 'storyboard.jpg', quality=92)
    frame(2.5).save(OUT / 'poster.jpg', quality=95)

def main(preview=False):
    previews()
    if preview: return
    audio()
    total = int(FPS * DURATION)
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0', '-i', str(OUT / 'soundtrack.wav'), '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart', str(OUT / 'glance-upscale-tutorial.mp4')]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    mp.set_start_method('fork')
    with mp.Pool(8) as pool:
        for i, data in enumerate(pool.imap(frame_bytes, range(total), chunksize=6)):
            enc.stdin.write(data)
            if i % 300 == 0: print(f'Rendered {i}/{total}', flush=True)
    enc.stdin.close()
    if enc.wait() != 0: raise RuntimeError('Encoding failed')
    print(OUT / 'glance-upscale-tutorial.mp4', flush=True)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--preview', action='store_true')
    main(ap.parse_args().preview)
