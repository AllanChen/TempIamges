"""Phone-first 9:16 cut: product window on top, headline below, bottom ~300 px kept clear
for the 小红书 / 抖音 caption overlay. Audio is taken from an existing edited vertical video.

Run from the repo root: .venv/bin/python design/marketing/videos/glance-intro-30s/mobile.py --lang zh --no-url --audio <video.mp4> [--preview]
"""
import subprocess
import sys
import multiprocessing as mp
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent
args = sys.argv[1:]
audio = args[args.index('--audio') + 1] if '--audio' in args else None
import importlib.util
spec = importlib.util.spec_from_file_location('v', OUT / 'vertical.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
h = v.h

COPY_BOX = (60, 330, 755, 840)
PAIN_COPY = (60, 330, 740, 840)
SHOT_BOX, PAIN_SHOT = v.SHOT_BOX, v.PAIN_SHOT


def mframe(t):
    src = h.frame(t)
    i = max(i for i, s in enumerate(h.SCENES) if s[0] <= t)
    im = v.BG_V.copy().convert('RGBA')
    if i in v.CENTERED:
        v.paste_scaled(im, src, (300, 60, 1620, 1020), v.VW, 420)
    else:
        v.header(im)
        copy_box, shot_box = (PAIN_COPY, PAIN_SHOT) if i == 0 else (COPY_BOX, SHOT_BOX)
        v.paste_scaled(im, src, shot_box, 1040, 190)
        v.paste_scaled(im, src, copy_box, 860, 1060)
    return im.convert('RGB')


def frame_bytes(n):
    return mframe(n / h.FPS).tobytes()


def main():
    name = f'glance-intro-30s-{h.LANG}-mobile'
    times = [2.5, 6.8, 9.6, 14.2, 16.6, 19.2, 21.6, 24.6, 27.8]
    board = Image.new('RGB', (360 * 9, 640), (12, 12, 16))
    for k, t in enumerate(times):
        board.paste(mframe(t).resize((360, 640), Image.Resampling.LANCZOS), (360 * k, 0))
    board.save(OUT / f'storyboard-{h.LANG}-mobile.jpg', quality=90)
    if '--preview' in args:
        return
    out = OUT / f'{name}.mp4'
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{v.VW}x{v.VH}', '-r', str(h.FPS), '-i', 'pipe:0', '-i', audio or str(OUT / f'soundtrack{h.TAG}-voice.wav'),
           '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'medium', '-crf', '19',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-t', str(h.DURATION), '-movflags', '+faststart', str(out)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with mp.get_context('fork').Pool(6) as pool:
        for n, data in enumerate(pool.imap(frame_bytes, range(h.FPS * h.DURATION), chunksize=4)):
            enc.stdin.write(data)
    enc.stdin.close()
    if enc.wait(): raise RuntimeError('encode failed')
    print('done', out)


if __name__ == '__main__':
    main()
