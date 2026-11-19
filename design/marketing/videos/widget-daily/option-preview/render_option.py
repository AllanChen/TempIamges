"""Glance「选中文件名，按 Option 直接预览」, 15 s, built on the user's own screen recording.

Run from the repo root:
  .venv/bin/python design/marketing/videos/widget-daily/option-preview/render_option.py --lang zh|en [--preview] [--pc-only|--phone-only]
Voice: option-preview/voice/<lang>-1..4.wav (user's voice, local F5-TTS, made by 「每日发布」). Voiced cut only.

Privacy (user rule): only the terminal file list + preview card are used (crop x 2160-3840, y 1104-1704 of the 4K
recording). Sidebar, menu bar and the chat pane are outside the crop. The folder name `clip_preview-12-20s`, the
prompt lines (`→ work …`, the folder name) and the card's path line are painted over / blurred.
No-landscape rule: the card thumbnails are 3D-rendered grass close-ups, so the image areas are blurred.
"""
from concurrent.futures import ThreadPoolExecutor
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import shizuka as z  # noqa: E402

args = sys.argv[1:]
LANG = args[args.index('--lang') + 1] if '--lang' in args else 'zh'
z.LANG = LANG
def L(en, zh): return zh if LANG == 'zh' else en

REC = Path('/Users/allan/OpenBot/Shared/glance-video/recordings/option-preview-2026-11-17.mov')
CACHE = Path('/tmp/glance-option-preview-frames')
OX, OY, CW, CH = 2160, 1104, 1680, 600          # crop of the 3840x2160 recording
R0, FPS_REC = 0.4, 60                          # cached frame k = recording time R0 + k / 60
W, H, VW, VH, FPS, DURATION, SR = 1920, 1080, 1080, 1920, 30, 15, 48000
SCENES_AT = [0, 3.6, 8.4, 12.0]
VOICE_AT = [0.2, 3.8, 8.6, 12.2]
TERM_BG = (38, 44, 54)

COPY = [
    (L('An image filename', '终端里的图片名，'), L('in Terminal?', '想看看？'), None),
    (L('Select it.', '选中它，'), L('Press Option.', '按一下 Option。'), None),
    (L('No Space bar.', '不按空格，'), L('No folder to open.', '也不开文件夹。'),
     L('Select several names, flip through them', '选中多个文件名，也能逐张翻看')),
]
KEYPATH = L('Select filename  →  ⌥ Option', '选中文件名  →  按 Option 键')
NOTE = L('Screen recording', '实际操作录屏')
TAGLINE = z.OUTRO_VOICE[LANG]
OUTRO_SUB = L('Option Preview · select a filename, press Option', '选中文件名 · 按 Option 预览')
OUTDIR = HERE


def extract():
    if CACHE.exists() and len(list(CACHE.glob('*.jpg'))) > 580: return
    CACHE.mkdir(exist_ok=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(R0), '-i', str(REC), '-t', '9.9', '-vf',
                    f'fps={FPS_REC},crop={CW}:{CH}:{OX}:{OY}', '-q:v', '2', str(CACHE / '%04d.jpg')], check=True)


def rect(x0, y0, x1, y1): return (x0 - OX, y0 - OY, x1 - OX, y1 - OY)   # full-res -> crop coords
CARD1 = (3.72, 5.55)            # first card (a1.jpg) on screen
CARD2 = (8.46, 10.3)            # multi-file card (a2.jpg, 1 of 4)
DIRNAME = rect(2536, 1102, 2868, 1142)          # cyan folder name clip_preview-12-20s
PROMPTS = rect(2222, 1246, 2480, 1484)          # "work open ./", "work" prompt lines (folder name)
CARD1_IMG = rect(2257, 1167, 2838, 1494)
CARD2_IMG = rect(3221, 1205, 3802, 1450)
CARD2_PATH = rect(3440, 1498, 3700, 1546)       # "~/Desktop/side_p…"


def blur(im, box, r=38):
    box = tuple(round(v) for v in box)
    reg = im.crop(box).filter(ImageFilter.GaussianBlur(r)).filter(ImageFilter.GaussianBlur(r))
    im.paste(reg, box[:2])


def rec_frame(rt):
    k = int(round((rt - R0) * FPS_REC))
    im = Image.open(CACHE / f'{min(max(k, 0), 593) + 1:04d}.jpg').convert('RGB')
    d = ImageDraw.Draw(im)
    def fill(box, at): d.rectangle(box, fill=im.getpixel(tuple(round(v) for v in at)))   # colour of the neighbouring background
    fill(DIRNAME, (DIRNAME[0] - 8, DIRNAME[3] - 4))
    if not CARD1[0] <= rt <= CARD1[1]: fill(PROMPTS, (PROMPTS[2] + 30, PROMPTS[1] + 6))
    if CARD1[0] <= rt <= CARD1[1]: blur(im, CARD1_IMG)
    if CARD2[0] <= rt <= CARD2[1]:
        blur(im, CARD2_IMG)
        fill(CARD2_PATH, (CARD2_PATH[0] + 20, CARD2_PATH[1] - 8))
    return im


def footage(t):
    """Scene time -> (rec time, crop box in cached-frame coords)."""
    if t < SCENES_AT[1]:                                    # before selecting
        return R0 + .2 + .6 * t, (0, 0, 1200, 600)
    if t < SCENES_AT[2]:
        u = t - SCENES_AT[1]
        rt = 2.6 + .8 * u
        if rt < 5.28: return rt, (0, 0, 1200, 600)
        q = z.smooth((rt - 5.28) / .8 / 1.0)                # freeze on the card and push in on its info
        a, b = (0, 0, 1200, 600), (0, 85, 923, 547)
        return 5.28, tuple(a[i] + (b[i] - a[i]) * q for i in range(4))
    u = t - SCENES_AT[2]
    return min(8.1 + .6 * u, 10.02), (480, 0, 1680, 600)


def panel(t, width):
    rt, box = footage(t)
    im = rec_frame(rt).crop(tuple(round(v) for v in box)).resize((width, width // 2), Image.Resampling.LANCZOS)
    m = Image.new('L', im.size); ImageDraw.Draw(m).rounded_rectangle((0, 0, im.width - 1, im.height - 1), 18, fill=255)
    out = Image.new('RGBA', im.size); out.paste(im, (0, 0), m)
    return out


def shadow(dst, xy, size, a=1):
    sh = Image.new('RGBA', (size[0] + 120, size[1] + 120))
    z.rr(sh, (60, 70, sh.width - 60, sh.height - 50), 18, fill=(0, 0, 0, 200))
    z.put(dst, sh.filter(ImageFilter.GaussianBlur(30)), (xy[0] - 60, xy[1] - 60), a)


def keypath(im, xy, a, size=23):
    w = z.tw(KEYPATH, size, 'm') + 44
    p = Image.new('RGBA', (round(w), round(size * 2.26)))
    z.rr(p, (0, 0, p.width - 1, p.height - 1), 8, fill=z.INK2, outline=z.LINE_STRONG)
    z.txt(p, (22, p.height / 2), KEYPATH, size, z.TEXT1, 'm', 'lm')
    z.put(im, p, (xy[0], xy[1] + 14 * (1 - a)), a)


def scene_of(t): return max(i for i, s in enumerate(SCENES_AT) if s <= t)


def body(t):
    i = scene_of(t); u = t - SCENES_AT[i]
    im = z.BG.copy()
    if i == 3: return ending(u)
    z.header(im)
    first, second, detail = COPY[i]
    z.copy_block(im, first, second, detail, z.ease(u / .3) if i else z.ease(u / .35))
    if i == 1: keypath(im, (110, 760), z.ease((u - .3) / .3))
    b = z.ease((t - .2) / .4)
    xy, wd = (790, 275 + round(20 * (1 - b))), 1060
    shadow(im, xy, (wd, wd // 2), b)
    z.put(im, panel(t, wd), xy, b)
    z.footnote(im, NOTE)
    return im


def ending(u):
    im = z.BG.copy(); a = z.ease(u / .3)
    layer = Image.new('RGBA', (W, H))
    z.put(layer, z.logo(150), (885, 150))
    z.txt(layer, (960, 400), 'Glance', 120, z.TEXT1, 's', 'mm', 'inter')
    z.txt(layer, (960, 540), TAGLINE, 66, z.SHU, 'b', 'mm', 'song')
    z.txt(layer, (960, 630), OUTRO_SUB, 30, z.TEXT2, 'r', 'mm')
    z.put(im, layer, (0, 16 * (1 - a)), a)
    c = z.ease((u - .7) / .35)
    s = L('Mac app · Made for Mac', 'Mac 电脑软件 · 为 Mac 打造')
    w = z.tw(s, 34, 's') + 90
    cta = Image.new('RGBA', (W, 100))
    z.rr(cta, (960 - w / 2, 10, 960 + w / 2, 84), 37, fill=z.TEXT1)
    z.txt(cta, (960, 47), s, 34, z.INK0, 's', 'mm')
    z.put(im, cta, (0, 760 + 10 * (1 - c)), c)
    return im


def fade(t, im, fn, size):
    i = scene_of(t)
    if i and t - SCENES_AT[i] < .2:
        im = Image.blend(fn(SCENES_AT[i] - .001).convert('RGBA'), im.convert('RGBA'), z.smooth((t - SCENES_AT[i]) / .2))
    if t > DURATION - .5:
        im = Image.blend(im.convert('RGBA'), Image.new('RGBA', size, (0, 0, 0, 255)), z.smooth((t - DURATION + .5) / .5) * .9)
    return im.convert('RGB')


def frame(t): return fade(t, body(t), body, (W, H))


# ---------- phone 9:16 ----------
BG_V = z.make_bg(VW, VH)


def vbody(t):
    i = scene_of(t); u = t - SCENES_AT[i]
    if i == 3:
        im = BG_V.copy(); src = ending(u)
        im.paste(src.crop((300, 100, 1620, 900)).resize((VW, round(800 * VW / 1320)), Image.Resampling.LANCZOS), (0, 520))
        return im
    im = BG_V.copy()
    z.put(im, z.logo(64), (60, 70))
    z.txt(im, (142, 102), 'Glance', 40, z.TEXT1, 's', 'lm', 'inter')
    b = z.ease((t - .2) / .4)
    xy, wd = (40, 250 + round(20 * (1 - b))), 1000
    shadow(im, xy, (wd, wd // 2), b)
    z.put(im, panel(t, wd), xy, b)
    z.txt(im, (1040, 790), NOTE, 22, z.TEXT3, 'r', 'rm')
    first, second, detail = COPY[i]
    z.copy_block(im, first, second, detail, z.ease(u / .3), x=80, y=920, size=96)
    if i == 1: keypath(im, (84, 1330), z.ease((u - .3) / .3), 30)
    return im


def vframe(t): return fade(t, vbody(t), vbody, (VW, VH))


# ---------- audio ----------
def tone(m, at, dur, hz, amp, soft=False):
    n = len(m); b = round(at * SR); c = min(round(dur * SR), n - b); ts = np.arange(c) / SR
    env = (1 - np.exp(-ts / (.18 if soft else .004))) * np.exp(-ts / (2.2 if soft else .3)) * np.clip((dur - ts) / .15, 0, 1)
    m[b:b + c] += ((np.sin(2 * np.pi * hz * ts) + .15 * np.sin(4 * np.pi * hz * ts)) * env * amp)[:, None]


def soundtrack(path):
    n = SR * DURATION; tm = np.arange(n) / SR; m = np.zeros((n, 2)); v = np.zeros(n)
    chords = [(130.81, 164.81, 196.0, 246.94), (110.0, 130.81, 164.81, 196.0), (87.31, 110.0, 130.81, 164.81), (98.0, 123.47, 146.83, 196.0)]
    for j, at in enumerate(np.arange(0, DURATION, 2.5)):
        for hz in chords[j % 4]: tone(m, at, 3.1, hz, .034, True)
        tone(m, at, .6, chords[j % 4][0] / 2, .045)
    for j, at in enumerate(np.arange(0, DURATION - 1.5, .625)):
        tone(m, at, .9, [523.25, 659.25, 783.99, 659.25][j % 4], .016)
    pop1 = SCENES_AT[1] + (CARD1[0] - 2.6) / .8; pop2 = SCENES_AT[2] + (CARD2[0] - 8.1) / .6
    for at in (pop1, pop2): tone(m, at, .08, 2400, .05)
    tone(m, 12.05, 1, 1046.5, .045); tone(m, 12.15, 1, 1318.5, .04)
    m /= np.max(np.abs(m))
    for k, at in enumerate(VOICE_AT):
        f = OUTDIR / 'voice' / f'{LANG}-{k + 1}.wav'
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(f), '-ac', '1', '-ar', str(SR), '-f', 's16le', '-'],
                             capture_output=True, check=True).stdout
        x = np.frombuffer(raw, '<i2').astype(float) / 32768; b = round(at * SR); x = x[:n - b]; v[b:b + len(x)] += x
    v /= np.max(np.abs(v))
    env = np.convolve((np.abs(v) > .02).astype(float), np.ones(SR // 4) / (SR // 4), mode='same')
    sig = m * .55 * (1 - .62 * np.clip(env * 3, 0, 1))[:, None] + v[:, None] * .95
    sig *= (np.clip(tm / .03, 0, 1) * np.clip((DURATION - tm) / 1.0, 0, 1))[:, None]
    sig *= .89 / np.max(np.abs(sig))
    import wave
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes((sig * 32767).astype('<i2').tobytes())


def check_voice():
    ends = SCENES_AT[1:] + [DURATION]
    bad = []
    for k, at in enumerate(VOICE_AT):
        f = OUTDIR / 'voice' / f'{LANG}-{k + 1}.wav'
        if not f.exists(): raise SystemExit(f'missing {f} — ask 每日发布 (F5-TTS)')
        d = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(f)],
                                 capture_output=True, text=True).stdout)
        if d > ends[k] - .2 - at + .05: bad.append(f'{f.name} {d:.2f}s > {ends[k] - .2 - at:.2f}s')
    if bad: raise SystemExit('voice too long: ' + '; '.join(bad))


def pc_bytes(n): return frame(n / FPS).tobytes()
def phone_bytes(n): return vframe(n / FPS).tobytes()


def encode(fn, size, audio, out):
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{size[0]}x{size[1]}',
           '-r', str(FPS), '-i', 'pipe:0', '-i', str(audio), '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-crf', '19',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION), '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with ThreadPoolExecutor(max_workers=3) as pool:
        for first in range(0, FPS * DURATION, 6):
            for data in pool.map(fn, range(first, min(first + 6, FPS * DURATION))):
                enc.stdin.write(data)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('encode failed')


def main():
    extract()
    times = [1.8, 4.6, 6.0, 7.8, 10.0, 13.5]
    pc = Image.new('RGB', (480 * 3, 270 * 2)); ph = Image.new('RGB', (270 * 6, 480))
    for k, t in enumerate(times):
        pc.paste(frame(t).resize((480, 270)), (480 * (k % 3), 270 * (k // 3)))
        ph.paste(vframe(t).resize((270, 480)), (270 * k, 0))
    pc.save(OUTDIR / f'storyboard-option-preview-{LANG}-pc.jpg', quality=90)
    ph.save(OUTDIR / f'storyboard-option-preview-{LANG}-phone.jpg', quality=90)
    if '--preview' in args: return
    check_voice()
    audio = OUTDIR / f'soundtrack-option-preview-{LANG}.wav'
    soundtrack(audio)
    if '--phone-only' not in args: encode(pc_bytes, (W, H), audio, OUTDIR / f'glance-option-preview-{LANG}-pc.mp4')
    if '--pc-only' not in args: encode(phone_bytes, (VW, VH), audio, OUTDIR / f'glance-option-preview-{LANG}-phone.mp4')
    voice = (['终端里的图片名，想看看？', '选中它，按一下 Option，预览就弹出来。', '不按空格，也不开文件夹。']
             if LANG == 'zh' else ['See an image filename in Terminal?', 'Select it, tap Option, and the preview pops up.',
                                   'No Space bar. No folder to open.']) + [z.OUTRO_VOICE[LANG]]
    ends = SCENES_AT[1:] + [DURATION]
    lines = [f"{L('Glance · Option Preview', 'Glance · 选中文件名按 Option 预览')} · {DURATION}s",
             L("Voice: user's voice (local F5-TTS)", '配音：用户指定音色（本地 F5-TTS）'),
             L('Footage: user screen recording option-preview-2026-11-17.mov (cropped; folder names/path masked; grass thumbnails blurred)',
               '画面：用户实操录屏 option-preview-2026-11-17.mov（已裁切；目录名和路径已遮挡；卡片草丛图已模糊）'), '']
    lines += [f'{k + 1}. {VOICE_AT[k]:05.2f}s – {ends[k]:05.2f}s  {v}' for k, v in enumerate(voice)]
    sp = ' ' if LANG == 'en' else ''
    lines += ['', L('On-screen text:', '画面大字：')]
    for k, (a, b, d) in enumerate(COPY):
        lines.append(f'{SCENES_AT[k]:05.2f}s – {ends[k]:05.2f}s  {a}{sp}{b}' + (f'  [{KEYPATH}]' if k == 1 else '') + (f'  ({d})' if d else ''))
    lines += [f"{SCENES_AT[3]:05.2f}s – {DURATION:05.2f}s  Glance · {TAGLINE} · {OUTRO_SUB} · {L('Mac app · Made for Mac', 'Mac 电脑软件 · 为 Mac 打造')}",
              L('Corner label: Screen recording', '角标：实际操作录屏')]
    (OUTDIR / f'narration-{LANG}.txt').write_text('\n'.join(lines) + '\n')
    print('done')


if __name__ == '__main__':
    main()
