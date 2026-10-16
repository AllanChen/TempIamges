"""10-second Glance upscale ad. Existing UI assets + original motion and sound.

Run with /private/tmp/glance-promo-venv/bin/python <this file> [--preview].
Requires Pillow, NumPy and ffmpeg. Does not launch or control Glance.
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
from PIL import Image, ImageDraw, ImageFilter, ImageOps

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
spec = importlib.util.spec_from_file_location('tutorial', OUT.parent / 'glance-upscale-tutorial/render.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
W, H, FPS, DURATION = 1920, 1080, 30, 10
WHITE, WARM, GRAY = ui.WHITE, ui.WARM, ui.GRAY
BG = ui.BG
txt, put, rr = ui.txt, ui.put, ui.rrect
ease, smooth, clamp = ui.ease, ui.smooth, ui.clamp
logo = ui.rounded(ui.logo, (54, 54), 15)

# Use the latest exported menu, including the separate credit badge.
menu_board = Image.open(ROOT / 'layout/figma-export/widget-context-menu-compact-credits.png').convert('RGBA')
menu_main = menu_board.crop((16, 68, 159, 210))
menu_sub = menu_board.crop((159, 68, 345, 286))
menu_main = menu_main.resize((286, 284), Image.Resampling.LANCZOS)
menu_sub = menu_sub.resize((372, 436), Image.Resampling.LANCZOS)


def header(im, label='高清放大 Widget'):
    put(im, logo, (92, 48))
    txt(im, (162, 76), 'Glance', 32, WHITE, 'en', 'lm')
    txt(im, (1828, 76), label, 22, GRAY, 'm', 'rm')


def copy(im, first, second, detail=None, amount=1):
    layer = Image.new('RGBA', (660, 640))
    txt(layer, (0, 0), first, 82, WHITE, 's')
    txt(layer, (0, 112), second, 82, WARM, 's')
    if detail:
        txt(layer, (3, 270), detail, 25, GRAY, 'r')
    put(im, layer, (108, 350 + 20 * (1 - amount)), amount)


def card(im, layer, x, y, width, alpha=1):
    height = round(layer.height * width / layer.width)
    layer = ui.rounded(layer, (round(width), height), 20)
    put(im, ui.shadow(layer.size, 26, 150), (x - 60, y - 60), alpha)
    put(im, layer, (x, y), alpha)


def bottom(im, text):
    txt(im, (1828, 1022), text, 18, (129, 124, 122), 'r', 'rm')


def workflow(t):
    im = BG.copy()
    header(im)
    txt(im, (110, 230), '只想放大一张图。', 36, GRAY, 'm')
    copy(im, '还要自己', '搭工作流？', amount=ease(t / .25))
    # Animated, deliberately tangled workflow as a visual metaphor.
    panel = Image.new('RGBA', (1020, 660))
    rr(panel, (0, 0, 1019, 659), 26, fill=(22, 23, 28), outline=(68, 62, 60))
    d = ImageDraw.Draw(panel)
    for x in range(24, 1020, 28):
        for y in range(24, 660, 28):
            d.ellipse((x, y, x + 2, y + 2), fill=(50, 47, 49))
    nodes = [(48, 238, '输入图片'), (278, 92, '加载模型'), (280, 394, '配置参数'),
             (542, 244, '超分处理'), (787, 105, '输出图片'), (785, 414, '依赖检查')]
    edges = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (5, 3), (2, 5)]
    for j, (a, b) in enumerate(edges):
        x, y, _ = nodes[a]; X, Y, _ = nodes[b]
        path = [(x + 160, y + 40), (x + 195, y + 40), (X - 30, Y + 40), (X, Y + 40)]
        d.line(path, fill=(122, 89, 71), width=3, joint='curve')
        q = (t * .75 + j * .17) % 1
        px = (1-q)**3 * path[0][0] + 3*(1-q)**2*q*path[1][0] + 3*(1-q)*q*q*path[2][0] + q**3*path[3][0]
        py = (1-q)**3 * path[0][1] + 3*(1-q)**2*q*path[1][1] + 3*(1-q)*q*q*path[2][1] + q**3*path[3][1]
        d.ellipse((px-4, py-4, px+4, py+4), fill=WARM)
    for j, (x, y, label) in enumerate(nodes):
        rr(panel, (x, y, x + 162, y + 80), 12, fill=(36, 34, 37), outline=(92, 76, 68))
        rr(panel, (x, y, x+5, y+80), 2, fill=WARM)
        txt(panel, (x+81, y+40), label, 23, WHITE, 'm', 'mm')
    rr(panel, (337, 562, 685, 615), 12, fill=(56, 36, 33))
    txt(panel, (511, 588), '安装依赖 · 调试 · 重试', 22, (227, 151, 130), 'm', 'mm')
    card(im, panel, 798, 210 + 18*(1-ease(t/.3)), 1030)
    return im


def ads(t):
    im = BG.copy(); header(im)
    txt(im, (110, 230), '只想放大一张图。', 36, GRAY, 'm')
    copy(im, '还得先', '看完广告？', amount=ease(t / .2))
    p = Image.new('RGBA', (1030, 660))
    rr(p, (0, 0, 1029, 659), 26, fill=(24, 25, 30), outline=(68, 62, 60))
    for j, color in enumerate([(210, 103, 92), (216, 172, 86), (113, 170, 120)]):
        ImageDraw.Draw(p).ellipse((24+j*26, 25, 37+j*26, 38), fill=color)
    rr(p, (167, 17, 862, 48), 8, fill=(36, 37, 44))
    txt(p, (515, 33), '在线图片工具', 17, GRAY, 'r', 'mm')
    # The tool remains obscured behind the advertisement.
    for box in [(40, 94, 190, 621), (840, 94, 990, 621)]:
        rr(p, box, 14, fill=(48, 43, 45))
        txt(p, ((box[0]+box[2])/2, 160), 'AD', 36, (151, 117, 104), 'en', 'mm')
    put(p, ui.rounded(ui.portrait_soft, (560, 470), 14), (235, 112), .45)
    overlay = Image.new('RGBA', p.size, (0, 0, 0, 95)); put(p, overlay, (0, 0))
    rr(p, (218, 203, 812, 510), 20, fill=(31, 31, 37), outline=(93, 77, 70), width=2)
    txt(p, (515, 247), '广告', 23, GRAY, 'm', 'mm')
    txt(p, (515, 326), f'{max(1, 15-int(t))} 秒', 76, WHITE, 's', 'mm')
    rr(p, (365, 414, 665, 468), 12, fill=(53, 50, 54))
    txt(p, (515, 441), '观看后继续', 24, (132, 125, 123), 'm', 'mm')
    card(im, p, 798, 210, 1030)
    return im


def reveal(t):
    im = BG.copy()
    txt(im, (960, 355), '换个简单的方式。', 42, GRAY, 'm', 'mm')
    txt(im, (960, 535), '用 Glance。', 130, WHITE, 's', 'mm')
    return im


@lru_cache(None)
def base_screen(kind):
    return ui.inspect_screen(kind, ui.TILES_BEFORE if kind == 'soft' else ui.TILES_AFTER)


def demo(t):
    im = BG.copy(); header(im)
    screen = base_screen('soft').copy()
    screen_x, screen_y, width = 736, 176, 1092
    card(im, screen, screen_x, screen_y, width)
    a = ease(t/.2)
    copy(im, '右键。', '高清放大。', 'Widget → 高清放大', a)
    # Zoomed menu exports retain the current Figma design exactly.
    main_a = ease((t-.25)/.16)
    sub_a = ease((t-.65)/.18)
    put(im, ui.shadow(menu_main.size, 20, 160), (911-60, 458-60), main_a)
    put(im, menu_main, (911, 458), main_a)
    put(im, ui.shadow(menu_sub.size, 20, 160), (1205-60, 458-60), sub_a)
    put(im, menu_sub, (1205, 458), sub_a)
    if t < .4:
        cx, cy = 910, 458
    elif t < .85:
        cx, cy = ui.move((944, 484), (1335, 556), (t-.4)/.45)
    else:
        cx, cy = 1335, 556
    ui.cursor(im, cx, cy, clamp((t-1.25)/.34) if 1.25 < t < 1.59 else 0)
    bottom(im, '需已安装高清放大 Widget')
    return im


def wait(t):
    im = BG.copy(); header(im)
    progress = round(12 + smooth(t/1.6)*85)
    screen = ui.inspect_screen('soft', ui.tiles_running(progress)).copy()
    ui.running_border(screen, .55 + .4*math.sin(t*4)**2)
    card(im, screen, 736, 176, 1092)
    copy(im, '然后，', '等它完成。', '处理交给 Glance。', ease(t/.2))
    x, y = 110, 742
    rr(im, (x, y, x+404, y+6), 3, fill=(51, 44, 42))
    rr(im, (x, y, x+max(6, round(404*progress/100)), y+6), 3, fill=WARM)
    txt(im, (x, y+33), '处理中', 22, GRAY, 'm')
    bottom(im, '产品动效示意 · 处理时间已压缩')
    return im


@lru_cache(None)
def result_images():
    # Same illustrative source/result pair used in the existing tutorial.
    crop = (100, 0, 850, 640)
    return (ImageOps.fit(ui.portrait_soft.crop(crop), (1010, 680), centering=(.5, 0)),
            ImageOps.fit(ui.portrait.crop(crop), (1010, 680), centering=(.5, 0)))


def result(t):
    im = BG.copy(); header(im)
    copy(im, '放大。', '清晰。', '结果自动保存。', ease(t/.2))
    soft, sharp = result_images()
    pic = soft.copy().convert('RGBA')
    q = smooth((t-.12)/.65)
    split = round(1010*(1-q))
    pic.paste(sharp.crop((split, 0, 1010, 680)), (split, 0))
    if 0 < split < 1010:
        ImageDraw.Draw(pic).line((split, 0, split, 680), fill=WARM, width=4)
    card(im, pic, 818, 193, 1010)
    badge = Image.new('RGBA', (195, 48)); rr(badge, (0, 0, 194, 47), 12, fill=(24, 31, 28, 240))
    txt(badge, (97, 24), '✓  高清放大完成', 22, ui.GREEN, 'm', 'mm')
    put(im, badge, (1605, 220), ease(t/.2))
    txt(im, (1323, 914), '从模糊，到更清晰。', 29, WHITE, 'm', 'mm')
    bottom(im, '画质效果示意')
    return im


def end(t):
    im = BG.copy()
    a = ease(t/.22)
    layer = Image.new('RGBA', (W, H))
    icon = ui.rounded(ui.logo, (164, 164), 40)
    put(layer, icon, (878, 184))
    txt(layer, (960, 466), 'Glance', 132, WHITE, 'en', 'mm')
    txt(layer, (960, 639), '右键一下，静待清晰。', 64, WARM, 's', 'mm')
    txt(layer, (960, 756), '高清放大 Widget', 29, GRAY, 'm', 'mm')
    txt(layer, (960, 943), '为 macOS 而生', 22, GRAY, 'r', 'mm')
    put(im, layer, (0, 15*(1-a)), a)
    return im


SCENES = [(0, workflow), (1.55, ads), (3.05, reveal), (3.6, demo), (5.35, wait), (6.95, result), (8.45, end)]


def frame(t):
    i = max(i for i, (start, _) in enumerate(SCENES) if start <= t)
    start, fn = SCENES[i]
    im = fn(t-start)
    # Crisp cuts establish the contrast; short dissolves connect operation/result.
    if i in (4, 5, 6) and t-start < .15:
        prevstart, prev = SCENES[i-1]
        im = Image.blend(prev(t-prevstart), im, smooth((t-start)/.15))
    return im.convert('RGB')


def soundtrack():
    sr = 48000; n = sr*DURATION; sig = np.zeros((n, 2))
    rng = np.random.default_rng(128)

    def tone(at, dur, hz, amp, soft=False, pan=0):
        b = round(at*sr); count = min(round(dur*sr), n-b)
        if count <= 0: return
        ts = np.arange(count)/sr
        env = (1-np.exp(-ts/(.16 if soft else .004)))*np.exp(-ts/(1.9 if soft else .28))*np.clip((dur-ts)/.12, 0, 1)
        val = (np.sin(2*np.pi*hz*ts)+.12*np.sin(4*np.pi*hz*ts))*env*amp
        sig[b:b+count] += val[:, None]*np.array([1-pan*.3, 1+pan*.3])

    def noise(at, dur, amp, sweep=False):
        b = round(at*sr); count = min(round(dur*sr), n-b); ts = np.arange(count)/sr
        val = rng.normal(size=count)
        val = np.convolve(val, np.ones(16)/16, mode='same')
        val *= (np.sin(np.pi*ts/dur)**2 if sweep else np.exp(-ts*100))*amp
        sig[b:b+count] += val[:, None]

    # First half feels busy. The brand entrance resolves into a warm major chord.
    for j in range(9):
        tone(.12+j*.32, .25, [164.81, 174.61, 185][j%3], .05)
        noise(.12+j*.32, .045, .085)
    noise(1.48, .20, .12, True)
    noise(2.94, .30, .16, True)
    for at in (3.08, 5.35, 6.95, 8.45):
        for k, hz in enumerate((130.81, 164.81, 196, 246.94)):
            tone(at, 2.7, hz, .042, True, (-1)**k*.4)
    for at, hz in [(3.15, 523.25), (3.63, 659.25), (4.27, 783.99), (5.43, 659.25),
                   (7.00, 1046.5), (7.14, 1318.5), (8.50, 523.25), (8.65, 659.25), (8.80, 783.99)]:
        tone(at, 1, hz, .052)
    for at in (3.86, 4.85): noise(at, .065, .26)
    noise(6.85, .27, .09, True)
    time = np.arange(n)/sr
    sig *= (np.clip(time/.025, 0, 1)*np.clip((DURATION-time)/.4, 0, 1))[:, None]
    sig *= .83/max(.01, np.max(np.abs(sig)))
    with wave.open(str(OUT/'soundtrack.wav'), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(sr)
        f.writeframes((sig*32767).astype('<i2').tobytes())


SAMPLES = [.8, 2.3, 3.3, 4.65, 6.15, 7.75, 9.2]


def previews():
    board = Image.new('RGB', (1920, 660), (12, 12, 16))
    for i, t in enumerate(SAMPLES):
        im = frame(t); im.save(OUT/f'frame-{t:.2f}s.jpg', quality=93)
        x, y = (i%4)*480, (i//4)*330
        board.paste(im.resize((480, 270), Image.Resampling.LANCZOS), (x, y))
        txt(board, (x+16, y+295), f'{t:.2f}s', 22, GRAY, 'en', 'lm')
    board.save(OUT/'storyboard.jpg', quality=95)
    frame(9.2).save(OUT/'poster.jpg', quality=95)


def frame_bytes(i): return frame(i/FPS).tobytes()


def main(preview):
    previews()
    if preview: return
    soundtrack()
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0', '-i', str(OUT/'soundtrack.wav'),
           '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION),
           '-movflags', '+faststart', str(OUT/'glance-upscale-10s.mp4')]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(4) as pool:
        for i, data in enumerate(pool.imap(frame_bytes, range(FPS*DURATION), chunksize=3)):
            enc.stdin.write(data)
            if i%60 == 0: print(f'Rendered {i}/{FPS*DURATION}', flush=True)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('Encoding failed')
    print(OUT/'glance-upscale-10s.mp4', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--preview', action='store_true')
    main(parser.parse_args().preview)
