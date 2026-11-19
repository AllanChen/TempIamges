"""Glance 1.1.0 静 Shizuka (Sumi dark) UI, redrawn for the Widget daily videos.

Values follow clients/macos/Glance/Sources at commit 271daaa: PanelStyle.swift (palette, type),
ImageInspectWindow.swift / Inspect/InspectChrome.swift (window, toolbar, bottom bar),
Inspect/ImageFilmstrip.swift, Inspect/ActionMenu.swift (custom right-click panel + compact
Widget submenu), WidgetInputPanel.swift, Inspect/TaskRunningViews.swift, Inspect/ImageRevealView.swift.
Widget names and credit costs come from server/widgets/*/widget.json.
The app is drawn at a smaller logical window (920x700 pt, min is 560x360) so text stays legible.
"""
import math
import subprocess
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

REPO = Path(__file__).resolve().parents[4]
LANG = 'zh'
# Fixed closing line for every widget video (user rule, 2026-11-15): voice and end-card text match.
OUTRO_VOICE = {'zh': 'Glance，看图顺手就改。', 'en': 'Right-click. Glance. Done.'}
OUTRO_TEXT = {'zh': '看图顺手就改。', 'en': 'Right-click. Glance. Done.'}   # shown under the big "Glance" title
EN = {'操作': 'Actions', '复制图片': 'Copy Image', '存储到 Documents': 'Save to Documents', '识别文字': 'Recognize Text',
      '向左旋转': 'Rotate Left', '向右旋转': 'Rotate Right', '翻转': 'Flip', '导出': 'Export', '存储为…': 'Save as…',
      '压缩…': 'Compress…', '调整尺寸…': 'Resize…', '拷贝为 Base64': 'Copy as Base64', '工具': 'Tools', '截图…': 'Capture…',
      'Base64 转图片…': 'Base64 → Image…', '打开图片链接…': 'Open image URL…', '在 Finder 中显示': 'Reveal in Finder',
      '图片信息': 'Image information', '置顶': 'Pin on Top', '自动隐藏': 'Automatic hide', '键盘快捷键': 'Keyboard Shortcuts',
      '已安装': 'Installed', '点/次': 'pts/task', 'Widget 市场…': 'Widget Market…', '适应窗口': 'Fit to Window',
      '滑杆': 'Slider', '左右并排': 'Side by side', '取消': 'Cancel',
      '可以继续查看主图，完成后结果会出现在下方。': 'You can keep inspecting; the result appears in the filmstrip.',
      'WIDGET  ·  图片 + 提示词': 'WIDGET  ·  IMAGES AND PROMPT', '用提示词告诉 Widget 要生成或修改什么。': 'The prompt tells the Widget what to make or change.',
      '提示词': 'Prompt', '描述希望 Widget 执行的操作…': 'Describe what the Widget should do…', '费用': 'Cost', '运行 Widget': 'Run Widget',
      '右键': 'Right-click',
      '人物背景分离': 'Background Remover Pro', '高清放大': 'Upscale', '图生图': 'Redraw & Reframe', '移除物体': 'Remove Objects',
      '局部编辑': 'Edit Area', 'AI 换装': 'Outfit Swap', '智能扩图': 'Expand Image', '图片去水印': 'Watermark Remover',
      '图片转提示词': 'Image to Prompt', '免费图床': 'Free Image Host',
      '选择图片，描述修改内容，然后绘制遮罩。': 'Choose the image, describe the edit, then draw the mask.', '遮罩': 'Mask',
      '已绘制': 'Drawn', '选择需要修改的区域': 'Select the area to change', '在图片上涂抹。': 'Paint it on the image.', '绘制遮罩': 'Draw mask'}


def tr(s): return EN.get(s, s) if LANG == 'en' else s
APP = REPO / 'clients/macos/Glance'

# ---------- tokens (PanelStyle.swift, Sumi) ----------
def hx(s, a=255): s = s.lstrip('#'); return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)
INK0, INK1, INK2, INK3, INK4 = hx('0F0F0E'), hx('151514'), hx('1B1B1A'), hx('242422'), hx('2E2E2B')
LINE, LINE_STRONG = hx('262624'), hx('34342F')
TEXT1, TEXT2, TEXT3, TEXT4 = hx('EAE7E0'), hx('A19D94'), hx('6B6862'), hx('47453F')
SHU, MOSS, AI = hx('C65A40'), hx('8C9C72'), hx('6F8AA0')
def alpha(c, a): return (*c[:3], round(255 * a))
TRAFFIC = [hx('ED6A5E'), hx('F4BF4F'), hx('61C554')]

INTER = {w: str(APP / f'Resources/Fonts/Inter-{n}.otf') for w, n in (('r', 'Regular'), ('m', 'Medium'), ('s', 'SemiBold'))}
MONO = '/System/Library/Fonts/SFNSMono.ttf'
PF = '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc'
PF_INDEX = {'r': 3, 'm': 7, 's': 11, 'b': 11}
MINCHO = '/System/Library/Fonts/ヒラギノ明朝 ProN.ttc'
SONG = '/System/Library/Fonts/Supplemental/Songti.ttc'   # Simplified-Chinese Mincho-style fallback


@lru_cache(None)
def font(fam, size, w='r'):
    size = max(1, round(size))
    if fam == 'inter': return ImageFont.truetype(INTER[w], size)
    if fam == 'mono': return ImageFont.truetype(MONO, size)
    if fam == 'pf': return ImageFont.truetype(PF, size, index=PF_INDEX[w])
    if fam == 'mincho': return ImageFont.truetype(MINCHO, size, index=0 if w == 'r' else 2)
    if fam == 'song': return ImageFont.truetype(SONG, size, index={'r': 6, 'b': 1, 'k': 0}[w])
    raise ValueError(fam)


def cjk(s): return any(ord(c) > 0x2e7f for c in s)


def txt(im, xy, s, size, color=TEXT1, w='r', anchor='la', fam=None):
    s = tr(s)
    fam = fam or ('pf' if cjk(s) else 'inter')
    ImageDraw.Draw(im).text(xy, s, font=font(fam, size, w), fill=color, anchor=anchor)


def tw(s, size, w='r', fam=None):
    s = tr(s)
    fam = fam or ('pf' if cjk(s) else 'inter')
    return font(fam, size, w).getlength(s)


def _translucent(c): return c is not None and len(c) == 4 and c[3] < 255


def rr(im, box, r, fill=None, outline=None, width=1):
    box = [round(v) for v in box]
    if not (_translucent(fill) or _translucent(outline)):
        ImageDraw.Draw(im).rounded_rectangle(box, round(r), fill=fill, outline=outline, width=width); return
    x0, y0 = box[0], box[1]
    layer = Image.new('RGBA', (box[2] - x0 + 1, box[3] - y0 + 1))
    ImageDraw.Draw(layer).rounded_rectangle((0, 0, layer.width - 1, layer.height - 1), round(r), fill=fill, outline=outline, width=width)
    put(im, layer, (x0, y0))


def hline(im, x0, x1, y, color, width):
    layer = Image.new('RGBA', (round(x1 - x0) + 1, max(1, round(width))), color)
    put(im, layer, (x0, y - width / 2))


def put(dst, src, xy, a=1.0):
    if a <= 0: return
    if a < 1:
        src = src.copy(); src.putalpha(src.getchannel('A').point(lambda v: round(v * a)))
    dst.alpha_composite(src, (round(xy[0]), round(xy[1]))) if (xy[0] >= 0 and xy[1] >= 0 and xy[0] + src.width <= dst.width and xy[1] + src.height <= dst.height) \
        else dst.paste(src, (round(xy[0]), round(xy[1])), src)


def clamp(x, a=0., b=1.): return max(a, min(b, x))
def smooth(x): x = clamp(x); return x * x * (3 - 2 * x)
def ease(x): x = clamp(x); return 1 - (1 - x) ** 3
def lerp(a, b, t): return a + (b - a) * t
def move(a, b, t): t = smooth(t); return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))


@lru_cache(None)
def icon(name, px, color=TEXT2):
    svg = next((APP / 'Resources/Assets.xcassets').glob(f'Shizuka{name}.imageset/*.svg'))
    png = subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), str(svg)], capture_output=True, check=True).stdout
    from io import BytesIO
    m = Image.open(BytesIO(png)).convert('RGBA').getchannel('A')
    out = Image.new('RGBA', m.size, color); out.putalpha(m); return out


def rounded(img, size, r):
    img = ImageOps.fit(img.convert('RGBA'), size, method=Image.Resampling.LANCZOS)
    m = Image.new('L', size); ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255)
    img.putalpha(m); return img


LOGO = Image.open(REPO / 'design/marketing/brand-assets/logo.png').convert('RGBA')


@lru_cache(None)
def logo(px): return LOGO.resize((px, px), Image.Resampling.LANCZOS)


# ---------- inspect window ----------
K = 2                       # supersampling
LW, LH = 920, 700           # logical window
CANVAS = (1000, 760)        # logical canvas (window + room for menus)
SCALE = 1.2                 # logical pt -> video px
WX, WY = 790, 150           # window origin in the 1920x1080 frame
STAGE = (44, 44, LW - 44, LH - 92 - 16)


def P(v): return v * K


def fit_rect(img):
    sx0, sy0, sx1, sy1 = STAGE
    s = min((sx1 - sx0) / img.width, (sy1 - sy0) / img.height)
    w, h = img.width * s, img.height * s
    x, y = sx0 + (sx1 - sx0 - w) / 2, sy0 + (sy1 - sy0 - h) / 2
    return x, y, w, h


_FIT = {}


def fitted(img):
    k = id(img)
    if k not in _FIT:
        if len(_FIT) > 80: _FIT.clear()
        x, y, w, h = fit_rect(img)
        _FIT[k] = (img, img.convert('RGBA').resize((round(P(w)), round(P(h))), Image.Resampling.LANCZOS))
    return _FIT[k][1]


def stage_image(c, img, rect=None, crop=None):
    x, y, w, h = rect or fit_rect(img)
    im = fitted(img)
    if crop is not None:                      # crop = (x0, x1) logical, for the compare slider
        a, b = [round(P(v - x)) for v in crop]
        a, b = max(0, a), min(im.width, b)
        if b <= a: return
        put(c, im.crop((a, 0, b, im.height)), (P(x) + a, P(y)))
    else:
        put(c, im, (P(x), P(y)))


def chrome(c, mode='image'):
    rr(c, (0, 0, P(LW) - 1, P(LH) - 1), P(12), fill=INK0, outline=LINE_STRONG, width=P(1))
    d = ImageDraw.Draw(c)
    for j, col in enumerate(TRAFFIC):
        cx = 20 + j * 20 + 6
        d.ellipse((P(cx - 6), P(16), P(cx + 6), P(28)), fill=col)
    names = ['Image', 'Compare', 'Adjust', 'Grid']
    x0 = LW / 2 - (4 * 28 + 3 * 2) / 2
    for i, n in enumerate(names):
        x = x0 + i * 30
        on = (n == 'Image' and mode == 'image') or (n == 'Compare' and mode == 'compare')
        if on: rr(c, (P(x), P(8), P(x + 28), P(36)), P(6), fill=INK4)
        put(c, icon(n, P(16), TEXT1 if on else TEXT2), (P(x + 6), P(14)))
    for i, n in enumerate(['More', 'Info', 'Text']):
        x = LW - 20 - 28 - i * 32
        put(c, icon(n, P(16), TEXT2), (P(x + 6), P(14)))


def bottom_bar(c, name, meta, right='适应窗口', pos='1 / 1', modes=False):
    y0 = LH - 92
    txt(c, (P(28), P(y0 + 29)), name, P(13), TEXT1, 'm', 'lm')
    txt(c, (P(28), P(y0 + 50)), meta, P(11), TEXT3, 'r', 'lm', 'mono')
    xr = LW - 28
    txt(c, (P(xr), P(y0 + 45.5)), pos, P(11), TEXT3, 'r', 'rm', 'mono')
    xr -= tw(pos, 11, fam='mono') + 16
    if modes:
        txt(c, (P(xr), P(y0 + 45.5)), '左右并排', P(12), TEXT3, 'r', 'rm')
        xr -= tw('左右并排', 12) + 12
        txt(c, (P(xr), P(y0 + 45.5)), '滑杆', P(12), TEXT1, 'm', 'rm')
    else:
        txt(c, (P(xr), P(y0 + 45.5)), right, P(12), TEXT2, 'r', 'rm')


def filmstrip(c, tiles, t=0):
    """tiles: list of (image, state); state in sel, plain, b, running, new, newsel."""
    n = len(tiles)
    x = LW / 2 - (n * 48 + (n - 1) * 8) / 2
    y = LH - 22 - 48
    for img, st in tiles:
        tile = Image.new('RGBA', (P(48), P(48)))
        if st != 'running' or img is not None:
            th = rounded(img, (P(40), P(40)), P(3))
            put(tile, th, (P(4), P(4)), 1 if st in ('sel', 'newsel', 'b', 'running') else .55)
        if st in ('sel', 'newsel', 'b'):
            rr(tile, (0, 0, P(48) - 1, P(48) - 1), P(6), outline=TEXT1 if st != 'b' else TEXT2, width=P(1))
        if st == 'running':
            rr(tile, (P(4), P(4), P(44), P(44)), P(3), fill=alpha(INK1, .86))
            d = ImageDraw.Draw(tile)
            b = (P(14), P(14), P(34), P(34))
            ring = Image.new('RGBA', tile.size); ImageDraw.Draw(ring).arc(b, 0, 360, fill=alpha(TEXT1, .18), width=P(2)); put(tile, ring, (0, 0))
            a0 = (t * 360 * 1.2) % 360
            d.arc(b, a0, a0 + 100, fill=AI, width=P(2))
        put(c, tile, (P(x), P(y)))
        if st in ('new', 'newsel'):
            ImageDraw.Draw(c).ellipse((P(x + 40), P(y - 1), P(x + 45), P(y + 4)), fill=SHU)
        x += 56


def running_overlay(c, rect, t, pct, name):
    x, y, w, h = rect
    veil = Image.new('RGBA', (round(P(w)), round(P(h))), alpha(INK0, .35))
    sw = min(220, w)
    sx = lerp(-sw, w, smooth((t % 2.1) / 2.1))
    g = Image.new('RGBA', (round(P(sw)), 1))
    for i in range(g.width):
        u = i / max(1, g.width - 1)
        g.putpixel((i, 0), (255, 255, 255, round(255 * .08 * math.sin(math.pi * u))))
    g = g.resize((g.width, veil.height))
    put(veil, g, (P(sx), 0)) if 0 <= P(sx) and P(sx) + g.width <= veil.width else veil.paste(g, (round(P(sx)), 0), g)
    put(c, veil, (P(x), P(y)))
    rr(c, (P(x), P(y + h - 2), P(x + w), P(y + h)), 0, fill=INK4)
    rr(c, (P(x), P(y + h - 2), P(x + w * pct / 100), P(y + h)), 0, fill=TEXT1)
    label, num, cancel = name, f'{pct}%', '取消'
    pw = 28 + tw(label, 13) + 8 + tw(num, 11, fam='mono') + 16 + tw(cancel, 12) + 14
    px, py = x + w / 2 - pw / 2, y + h - 24 - 31
    rr(c, (P(px), P(py), P(px + pw), P(py + 31)), P(15.5), fill=alpha(INK1, .92), outline=LINE_STRONG, width=P(1))
    ImageDraw.Draw(c).ellipse((P(px + 11), P(py + 12.5), P(px + 17), P(py + 18.5)), fill=AI)
    txt(c, (P(px + 28), P(py + 15.5)), label, P(13), TEXT1, 'r', 'lm')
    txt(c, (P(px + 28 + tw(label, 13) + 8), P(py + 15.5)), num, P(11), TEXT3, 'r', 'lm', 'mono')
    txt(c, (P(px + pw - 14), P(py + 15.5)), cancel, P(12), TEXT2, 'r', 'rm')
    hint = '可以继续查看主图，完成后结果会出现在下方。'
    txt(c, (P(x + w / 2), P(min(y + h + 14, LH - 92 - 4))), hint, P(12), TEXT3, 'r', 'mt')


def slider(c, before, after, split, names):
    """Compare slider: before on the left, after on the right of `split` (0..1 of the image width)."""
    rect = fit_rect(after)
    x, y, w, h = rect
    sx = x + w * split
    stage_image(c, before, fit_rect(before), crop=(x, sx))
    stage_image(c, after, rect, crop=(sx, x + w))
    put(c, Image.new('RGBA', (2, round(P(h))), alpha(TEXT1, .82)), (P(sx) - 1, P(y)))
    cy = y + h / 2
    d = ImageDraw.Draw(c)
    d.ellipse((P(sx - 14), P(cy - 14), P(sx + 14), P(cy + 14)), fill=INK0, outline=TEXT1, width=P(1))
    for s in (-1, 1):
        d.line([(P(sx + s * 3), P(cy - 3)), (P(sx + s * 6), P(cy)), (P(sx + s * 3), P(cy + 3))], fill=TEXT1, width=round(P(1.25)), joint='curve')
    for (letter, name), lx, anchor in ((names[0], x + 12, 'l'), (names[1], x + w - 12, 'r')):
        lw = 8 + tw(letter, 11, fam='mono') + 6 + tw(name, 11) + 8
        bx = lx if anchor == 'l' else lx - lw
        rr(c, (P(bx), P(y + 12), P(bx + lw), P(y + 33)), P(4), fill=INK0)
        txt(c, (P(bx + 8), P(y + 22.5)), letter, P(11), TEXT1, 'r', 'lm', 'mono')
        txt(c, (P(bx + 8 + tw(letter, 11, fam='mono') + 6), P(y + 22.5)), name, P(11), TEXT2, 'r', 'lm')


# ---------- right-click menu (ActionMenu.swift) ----------
CHEV = '›'
MAIN_MENU = [('item', 'Widget', CHEV), ('sep',), ('hdr', '操作'), ('item', '复制图片', '⌘C'), ('item', '存储到 Documents', '⌘S'),
             ('item', '识别文字', ''), ('sep',), ('item', '向左旋转', '⌘L'), ('item', '向右旋转', '⌘R'), ('item', '翻转', CHEV), ('sep',),
             ('hdr', '导出'), ('item', '存储为…', CHEV), ('item', '压缩…', ''), ('item', '调整尺寸…', ''), ('item', '拷贝为 Base64', ''),
             ('sep',), ('hdr', '工具'), ('item', '截图…', '⌘⇧X'), ('item', 'Base64 转图片…', ''), ('item', '打开图片链接…', ''), ('sep',),
             ('item', '在 Finder 中显示', ''), ('item', '图片信息', '⌘I'), ('sep',), ('item', '置顶', ''), ('item', '自动隐藏', ''),
             ('item', '键盘快捷键', '?')]
# Installed widgets, names + creditCost from server/widgets/*/widget.json
WIDGET_ROWS = [('人物背景分离', 1), ('高清放大', 1), ('图生图', 1), ('移除物体', 30), ('局部编辑', 1), ('AI 换装', 1),
               ('智能扩图', 1), ('图片去水印', 1), ('图片转提示词', 1), ('免费图床', 1)]


def main_menu(hl_widget=False):
    hts = {'item': 28, 'sep': 11, 'hdr': 23}
    H = 12 + sum(hts[r[0]] for r in MAIN_MENU)
    m = Image.new('RGBA', (P(260), P(H)))
    rr(m, (0, 0, P(260) - 1, P(H) - 1), P(10), fill=INK2, outline=LINE_STRONG, width=P(1))
    y = 6
    for r in MAIN_MENU:
        if r[0] == 'sep':
            ImageDraw.Draw(m).line((P(16), P(y + 5.5), P(244), P(y + 5.5)), fill=LINE, width=P(1))
        elif r[0] == 'hdr':
            txt(m, (P(16), P(y + 6)), r[1], P(11), TEXT3)
        else:
            if r[1] == 'Widget' and hl_widget:
                rr(m, (P(6), P(y), P(254), P(y + 28)), P(6), fill=INK4)
            txt(m, (P(16), P(y + 14)), r[1], P(13), TEXT1, 'r', 'lm')
            if r[2] == CHEV:
                txt(m, (P(260 - 20), P(y + 14)), CHEV, P(15), TEXT2, 'r', 'rm', 'inter')
            elif r[2]:
                txt(m, (P(260 - 16), P(y + 14)), r[2], P(12), TEXT3, 'r', 'rm', 'inter' if not cjk(r[2]) else None)
        y += hts[r[0]]
    return m


def widget_menu(target, hl):
    W_ = 220
    H = 6 + 32 + 28 * len(WIDGET_ROWS) + 14 + 28 + 6
    m = Image.new('RGBA', (P(W_), P(H)))
    rr(m, (0, 0, P(W_) - 1, P(H) - 1), P(10), fill=INK1, outline=alpha(TEXT1, .12), width=P(1))
    txt(m, (P(16), P(6 + 16)), '已安装', P(11), TEXT2, 'm', 'lm')
    txt(m, (P(W_ - 16), P(6 + 16)), '点/次', P(11), TEXT3, 'r', 'rm')
    y = 38
    for name, cost in WIDGET_ROWS:
        on = hl and name == target
        if on: rr(m, (P(6), P(y), P(W_ - 6), P(y + 28)), P(6), fill=TEXT1)
        txt(m, (P(16), P(y + 14)), name, P(13), INK0 if on else TEXT1, 'm', 'lm')
        s = str(cost)
        bw = tw(s, 11, 's') + 12
        rr(m, (P(W_ - 14 - bw), P(y + 4), P(W_ - 14), P(y + 24)), P(5), fill=alpha(INK0, .12) if on else alpha(TEXT1, .06))
        txt(m, (P(W_ - 14 - bw / 2), P(y + 14)), s, P(11), INK0 if on else TEXT2, 's', 'mm')
        y += 28
    hline(m, P(14), P(W_ - 14), P(y + 7), alpha(TEXT1, .09), P(1))
    y += 14
    txt(m, (P(16), P(y + 14)), 'Widget 市场…', P(13), TEXT1, 'm', 'lm')
    txt(m, (P(W_ - 20), P(y + 14)), CHEV, P(15), TEXT2, 'r', 'rm', 'inter')
    return m


def widget_row_y(target):
    return 38 + 28 * [n for n, _ in WIDGET_ROWS].index(target) + 14


# ---------- widget input window (WidgetInputPanel.swift), drawn at a reduced 1200x750 board ----------
IW, IH = 1200, 750


def input_window(name, cost, img, typed, caret, pressed, mask=None, paint=None):
    c = Image.new('RGBA', (P(IW), P(IH)))
    rr(c, (0, 0, P(IW) - 1, P(IH) - 1), P(12), fill=INK1, outline=LINE_STRONG, width=P(1))
    d = ImageDraw.Draw(c)
    for j, col in enumerate(TRAFFIC):
        cx = 26 + j * 20
        d.ellipse((P(cx - 6), P(16), P(cx + 6), P(28)), fill=col)
    txt(c, (P(IW / 2), P(22)), name, P(13), TEXT2, 'm', 'mm')
    sw = 800
    d.rectangle((P(1), P(44), P(sw), P(IH - 2)), fill=INK0)
    d.line((P(sw), P(44), P(sw), P(IH - 2)), fill=LINE, width=P(1))
    s = min((sw - 80) / img.width, (IH - 44 - 80) / img.height)
    iw, ih = img.width * s, img.height * s
    ox, oy = (sw - iw) / 2, 44 + (IH - 44 - ih) / 2
    put(c, img.convert('RGBA').resize((round(P(iw)), round(P(ih))), Image.Resampling.LANCZOS), (P(ox), P(oy)))
    if mask and paint:                     # painted mask overlay in the mask colour (accent, α .55)
        ml = Image.new('L', c.size)
        md = ImageDraw.Draw(ml)
        r = P(26)
        for q in [i / 60 for i in range(int(60 * paint) + 1)]:
            bx, by = mask_brush_point(mask, img, q, (ox, oy, s))
            md.ellipse((P(bx) - r, P(by) - r, P(bx) + r, P(by) + r), fill=round(255 * .55))
        tint = Image.new('RGBA', c.size, TEXT1); tint.putalpha(ml)
        c.alpha_composite(tint)
    fx, fwid = sw + 40, IW - sw - 80
    kinds = '图片 + 提示词 + 遮罩' if mask else '图片 + 提示词'
    txt(c, (P(fx), P(84)), f"WIDGET  ·  {kinds if LANG == 'zh' else ('IMAGE + PROMPT + MASK' if mask else 'IMAGES AND PROMPT')}", P(11), TEXT3, 'r', 'lt')
    txt(c, (P(fx), P(108)), name, P(30), TEXT1, 'r', 'lt', 'song' if LANG == 'zh' else 'mincho')
    txt(c, (P(fx), P(160)), '选择图片，描述修改内容，然后绘制遮罩。' if mask else '用提示词告诉 Widget 要生成或修改什么。', P(13), TEXT2, 'r', 'lt')
    if mask:
        top = 427
        txt(c, (P(fx), P(top)), '遮罩', P(12), TEXT3, 'r', 'lt')
        if paint and paint >= 1: txt(c, (P(fx + fwid), P(top)), '已绘制', P(12), MOSS, 'r', 'rt')
        txt(c, (P(fx), P(top + 25)), '选择需要修改的区域', P(13), TEXT1, 'm', 'lt')
        txt(c, (P(fx), P(top + 46)), '在图片上涂抹。', P(12), TEXT3, 'r', 'lt')
        rr(c, (P(fx), P(top + 74), P(fx + fwid), P(top + 106)), P(6), outline=LINE_STRONG, width=P(1))
        txt(c, (P(fx + fwid / 2), P(top + 90)), '绘制遮罩', P(13), TEXT1, 'm', 'mm')
    txt(c, (P(fx), P(232)), '提示词', P(12), TEXT3, 'r', 'lt')
    rr(c, (P(fx), P(255), P(fx + fwid), P(255 + 148)), P(6), fill=INK0, outline=LINE_STRONG, width=P(1))
    if typed:
        txt(c, (P(fx + 14), P(255 + 12)), typed, P(14), TEXT1, 'r', 'lt')
        if caret:
            cx = fx + 14 + tw(typed, 14) + 2
            d.rectangle((P(cx), P(267), P(cx + 1.2), P(285)), fill=TEXT1)
    else:
        txt(c, (P(fx + 14), P(255 + 12)), '描述希望 Widget 执行的操作…', P(14), TEXT3, 'r', 'lt')
    cy = IH - 64 - 60
    d.line((P(fx), P(cy), P(fx + fwid), P(cy)), fill=LINE, width=P(1))
    d.line((P(fx), P(cy + 40), P(fx + fwid), P(cy + 40)), fill=LINE, width=P(1))
    txt(c, (P(fx), P(cy + 20)), '费用', P(13), TEXT3, 'r', 'lm')
    txt(c, (P(fx + fwid), P(cy + 20)), str(cost), P(13), TEXT1, 'r', 'rm', 'mono')
    by = IH - 64
    bw = (fwid - 12) / 2
    rr(c, (P(fx), P(by), P(fx + bw), P(by + 32)), P(6), outline=LINE_STRONG, width=P(1))
    txt(c, (P(fx + bw / 2), P(by + 16)), '取消', P(13), TEXT1, 'm', 'mm')
    rr(c, (P(fx + bw + 12), P(by), P(fx + fwid), P(by + 32)), P(6), fill=hx('FFFFFF') if pressed else TEXT1)
    txt(c, (P(fx + bw + 12 + bw / 2), P(by + 16)), '运行 Widget', P(13), INK0, 'm', 'mm')
    return c, (fx + bw + 12 + bw / 2, by + 16)


def mask_brush_point(mask, img, q, place=None):
    """Zig-zag brush path over the mask box (source px) at progress q, in input-window logical pt."""
    if place is None:
        sw = 800
        s = min((sw - 80) / img.width, (IH - 44 - 80) / img.height)
        place = ((sw - img.width * s) / 2, 44 + (IH - 44 - img.height * s) / 2, s)
    ox, oy, s = place
    x0, y0, x1, y1 = mask
    rows = 5
    k = min(rows - 1e-6, q * rows)
    row, u = int(k), k - int(k)
    if row % 2: u = 1 - u
    x = x0 + 30 + (x1 - x0 - 60) * u
    y = y0 + 30 + (y1 - y0 - 60) * row / (rows - 1)
    return ox + x * s, oy + y * s


# ---------- cursor ----------
@lru_cache(None)
def arrow(px=30):
    s = px / 30
    pts = [(0, 0), (0, 23), (6, 17.5), (10, 26), (13.5, 24.5), (9.6, 16.4), (17, 16.4)]
    im = Image.new('RGBA', (round(26 * s) + 4, round(30 * s) + 4))
    d = ImageDraw.Draw(im)
    pp = [(2 + x * s, 2 + y * s) for x, y in pts]
    d.polygon(pp, fill=(255, 255, 255, 255))
    inner = [(2 + x * s * .82 + 1.6 * s, 2 + y * s * .82 + 3 * s) for x, y in pts]
    d.polygon(inner, fill=(10, 10, 10, 255))
    sh = Image.new('RGBA', im.size); sh.putalpha(im.getchannel('A').point(lambda v: v // 3))
    out = Image.new('RGBA', (im.width + 6, im.height + 6))
    put(out, sh.filter(ImageFilter.GaussianBlur(2)), (3, 4)); put(out, im, (0, 0))
    return out


def cursor(frame, x, y, pulse=0):
    if pulse > 0:
        r = 10 + 22 * pulse
        ring = Image.new('RGBA', (90, 90))
        ImageDraw.Draw(ring).ellipse((45 - r, 45 - r, 45 + r, 45 + r), outline=TEXT1, width=3)
        put(frame, ring, (x - 45, y - 45), .6 * (1 - pulse))
    put(frame, arrow(), (x - 2, y - 2))


# ---------- frame-level layout ----------
W, H = 1920, 1080


def make_bg(w, h):
    import numpy as np
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w * .3) / w, (yy - h * .2) / h)
    base = np.array(INK0[:3], float); top = np.array(INK2[:3], float)
    k = np.clip(1 - r * 1.3, 0, 1)[..., None] ** 2
    arr = (base + (top - base) * k).astype('uint8')
    return Image.fromarray(arr).convert('RGBA')


BG = make_bg(W, H)


def to_frame(lx, ly): return WX + lx * SCALE, WY + ly * SCALE


def place_canvas(frame, c, a=1, dy=0):
    small = c.resize((round(c.width * SCALE / K), round(c.height * SCALE / K)), Image.Resampling.LANCZOS)
    put(frame, small, (WX, WY + dy), a)


def window_shadow(frame, a=1, dy=0):
    sh = Image.new('RGBA', (round(LW * SCALE) + 120, round(LH * SCALE) + 120))
    rr(sh, (60, 70, sh.width - 60, sh.height - 50), 18, fill=(0, 0, 0, 200))
    put(frame, sh.filter(ImageFilter.GaussianBlur(30)), (WX - 60, WY - 60 + dy), a)


def header(im):
    put(im, logo(50), (92, 46))
    txt(im, (158, 72), 'Glance', 30, TEXT1, 's', 'lm', 'inter')


def copy_block(im, first, second, detail=None, a=1, x=108, y=360, size=82):
    layer = Image.new('RGBA', (720, 560))
    hf = 'song' if cjk(first + second) else 'mincho'
    widest = max(tw(first, size, 'b', hf), tw(second, size, 'b', hf))
    size = min(size, size * 630 / widest)
    txt(layer, (0, 0), first, size, TEXT1, 'b', 'la', hf)
    txt(layer, (0, size * 1.3), second, size, SHU, 'b', 'la', hf)
    if detail:
        txt(layer, (4, size * 2.9), detail, 26, TEXT2, 'r')
    put(im, layer, (x, y + 24 * (1 - a)), a)


def step_path(im, label, a):
    s = f"{tr('右键')}  →  Widget  →  {label}"
    w = tw(s, 23, 'm') + 44
    p = Image.new('RGBA', (round(w), 52))
    rr(p, (0, 0, round(w) - 1, 51), 8, fill=INK2, outline=LINE_STRONG)
    txt(p, (22, 26), s, 23, TEXT1, 'm', 'lm')
    put(im, p, (110, 760 + 14 * (1 - a)), a)


def footnote(im, s):
    txt(im, (1828, 1036), s, 17, TEXT3, 'r', 'rm')
