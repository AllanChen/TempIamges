"""Daily Glance Widget spotlight, 15 s. One run = PC 16:9 + phone 9:16 (both with voice).

Run from the repo root: .venv/bin/python design/marketing/videos/widget-daily/render.py --lang zh --widget bgpro [--no-url] [--preview]
Reuses ../glance-intro-30s/render.py (and through it ../glance-ai-intro-43s/render.py).
Add a widget by adding an entry to WIDGETS.
"""
import importlib.util
import multiprocessing as mp
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
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
}
S = WIDGETS[KEY]
VOICE_AT = S.get('voice_at', [0.2, 4.1, 8.8, 12.2])
SCENES_AT = S.get('scenes_at', [0, 3.9, 8.6, 12.0])
NOTE = L('Product animation · example result', '产品动效示意 · 示例效果')
DEMO = g.demo_scene(dict({k: v for k, v in S.items() if k not in ('scenes_at', 'voice_at')}, detail=None, first=S['demo'][0], second=S['demo'][1], note=NOTE))
ease, smooth, clamp = g.ease, g.smooth, g.clamp


def hook(t):
    im = h.BG.copy(); g.header(im)
    a = ease(t / .35)
    g.copy_block(im, *S['hook'], None, a)
    g.place_window(im, g.window(S['before'], tiles=(('sel', S['before'], None),)), ease((t - .2) / .4), 20 * (1 - a))
    return im


def result(t):
    im = h.BG.copy(); g.header(im)
    g.copy_block(im, *S['result'], S['detail'], ease(t / .3))
    # show result -> back to original -> result again, ending on the result
    q = 1 - smooth((t - .5) / .9) + smooth((t - 1.8) / 1.0)
    tiles = (('plain', S['before'], None), ('sel', S['after'], 'NEW'))
    g.place_window(im, g.window(S['before'], S['after'], q, S.get('mode', 'wipe'), tiles), 1)
    g.done_badge(im, S['done'], 1)
    g.footnote(im, NOTE)
    return im


def ending(t):
    im = h.BG.copy(); a = ease(t / .3)
    layer = Image.new('RGBA', (W, H))
    put(layer, ui.rounded(g.LOGO, (150, 150), 38), (885, 150))
    txt(layer, (960, 400), 'Glance', 120, h.WHITE, 'b', 'mm', 'en')
    txt(layer, (960, 540), S['tagline'], 66, h.WARM, 's', 'mm')
    txt(layer, (960, 630), f"Widget · {S['menu_label']}", 30, h.GRAY, 'm', 'mm')
    put(im, layer, (0, 16 * (1 - a)), a)
    c = ease((t - .7) / .35)
    s = L('Made for Mac', 'Mac 电脑软件 · 为 Mac 打造') if h.NO_URL else 'glancepreview.com'
    fam = None if h.NO_URL else 'en'
    w = tw(s, 34, 's', fam) + 90
    cta = Image.new('RGBA', (W, 100))
    rr(cta, (960 - w / 2, 10, 960 + w / 2, 84), 37, fill=h.WARM)
    txt(cta, (960, 47), s, 34, h.INK, 's', 'mm', fam)
    put(im, cta, (0, 760 + 10 * (1 - c)), c)
    return im


SCENES = list(zip(SCENES_AT, [hook, DEMO, result, ending]))


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
BG_V = h.BG.resize((VH * 16 // 9, VH)).crop(((VH * 16 // 9 - VW) // 2, 0, (VH * 16 // 9 + VW) // 2, VH))


def paste_scaled(dst, src, box, width, y):
    s = width / (box[2] - box[0]); size = (width, round((box[3] - box[1]) * s))
    crop = np.asarray(src.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    bg = np.asarray(h.BG.crop(box).resize(size, Image.Resampling.LANCZOS).convert('RGB'), np.int16)
    x0, y0 = (VW - width) // 2, round(y)
    reg = np.asarray(dst.crop((x0, y0, x0 + size[0], y0 + size[1])).convert('RGB'), np.int16)
    dst.paste(Image.fromarray(np.clip(reg + crop - bg, 0, 255).astype(np.uint8)).convert('RGBA'), (x0, y0))


def vframe(t):
    src, i = frame(t)
    im = BG_V.copy().convert('RGBA')
    if i == 3:
        paste_scaled(im, src, (300, 100, 1620, 900), VW, 520)
    else:
        put(im, ui.rounded(g.LOGO, (64, 64), 18), (60, 70))
        txt(im, (142, 102), 'Glance', 40, h.WHITE, 's', 'lm', 'en')
        paste_scaled(im, src, (760, 120, 1910, 1050), 1040, 190)
        paste_scaled(im, src, (60, 330, 755, 840), 860, 1060)
    return im.convert('RGB')


# ---------- audio ----------
def soundtrack(path, music_path=None):
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
    for k, at in enumerate(VOICE_AT):
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(VDIR / f'{k}.aiff'), '-ac', '1', '-ar', str(SR), '-f', 's16le', '-'],
                             capture_output=True, check=True).stdout
        x = np.frombuffer(raw, '<i2').astype(float) / 32768; b = round(at * SR); x = x[:n - b]; v[b:b + len(x)] += x
    m /= np.max(np.abs(m)); v /= np.max(np.abs(v))
    env = np.convolve((np.abs(v) > .02).astype(float), np.ones(SR // 4) / (SR // 4), mode='same')
    fade = (np.clip(tm / .03, 0, 1) * np.clip((DURATION - tm) / 1.0, 0, 1))[:, None]
    if music_path:
        mm = m * fade; mm *= .89 / np.max(np.abs(mm))
        _wav(music_path, mm)
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
VDIR = OUTDIR / f'voice-{h.LANG}'


def main():
    OUTDIR.mkdir(exist_ok=True); VDIR.mkdir(exist_ok=True)
    times = [1.8, 5.1, 7.6, 9.4, 11.0, 13.5]
    pc = Image.new('RGB', (480 * 3, 270 * 2)); ph = Image.new('RGB', (270 * 6, 480))
    for k, t in enumerate(times):
        pc.paste(frame(t)[0].resize((480, 270)), (480 * (k % 3), 270 * (k // 3)))
        ph.paste(vframe(t).resize((270, 480)), (270 * k, 0))
    tag = f'{KEY}-{h.LANG}'
    pc.save(OUTDIR / f'storyboard-{tag}-pc.jpg', quality=90); ph.save(OUTDIR / f'storyboard-{tag}-phone.jpg', quality=90)
    if '--preview' in args: return
    voice, rate = ('Tingting', '200') if h.LANG == 'zh' else ('Samantha', '185')
    for k, line in enumerate(S['voice']):
        subprocess.run(['say', '-v', voice, '-r', rate, '-o', str(VDIR / f'{k}.aiff'), line], check=True)
    audio, music = OUTDIR / f'soundtrack-{tag}.wav', OUTDIR / f'soundtrack-{tag}-novoice.wav'
    soundtrack(audio, music)
    for fn, size, kind in ((pc_bytes, (W, H), 'pc'), (phone_bytes, (VW, VH), 'phone')):
        out = OUTDIR / f'glance-widget-{tag}-{kind}.mp4'
        encode(fn, size, audio, out)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(out), '-i', str(music), '-map', '0:v', '-map', '1:a', '-c:v', 'copy',
                        '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart',
                        str(OUTDIR / f'glance-widget-{tag}-{kind}-novoice.mp4')], check=True)
    lines = [f"{h.L('Glance Widget daily', 'Glance Widget 日更')} · {S['menu_label']} · {DURATION}s",
             h.L('Voice: Samantha, rate 185', '原配音：Mac 婷婷，语速 200'), '']
    for k, (at, line) in enumerate(zip(VOICE_AT, S['voice'])):
        end = SCENES_AT[k + 1] if k + 1 < len(SCENES_AT) else DURATION
        lines.append(f'{k + 1}. {at:05.2f}s – {end:05.2f}s  {line}')
    lines += ['', h.L('On-screen text:', '画面大字：'), f"{S['hook'][0]}{S['hook'][1]}", f"{S['demo'][0]}{S['demo'][1]}",
              f"{S['result'][0]}{S['result'][1]}（{S['detail']}）", S['tagline']]
    (OUTDIR / 'narration.txt').write_text('\n'.join(lines) + '\n')
    print('done')


if __name__ == '__main__':
    main()
