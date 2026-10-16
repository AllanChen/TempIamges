"""Render a ten-second Glance product film using existing project assets.

Usage: /private/tmp/glance-promo-venv/bin/python outputs/glance-promo-10s/render.py
Dependencies: Pillow, NumPy, ffmpeg. No application UI automation.
"""
from pathlib import Path
from functools import lru_cache
import math
import subprocess
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
W, H, FPS, SECONDS = 1920, 1080, 30, 10
INK = (247, 244, 240)
PEACH = (236, 174, 127)
MUTED = (158, 157, 164)
CN = '/System/Library/Fonts/Hiragino Sans GB.ttc'
EN = '/System/Library/Fonts/SFNS.ttf'
MONO = '/System/Library/Fonts/Menlo.ttc'

@lru_cache(None)
def font(size, family='cn'):
    return ImageFont.truetype({'cn': CN, 'en': EN, 'mono': MONO}[family], size)

def clamp(x):
    return max(0.0, min(1.0, x))

def ease(x):
    return 1 - (1 - clamp(x)) ** 3

def smooth(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)

def text(im, xy, content, size, color=INK, family='cn', anchor=None):
    ImageDraw.Draw(im).text(xy, content, font=font(size, family), fill=color, anchor=anchor)

def place(im, layer, xy, alpha=1):
    if alpha <= 0:
        return
    if alpha < 1:
        layer = layer.copy()
        layer.putalpha(layer.getchannel('A').point(lambda p: round(p * alpha)))
    im.alpha_composite(layer, (round(xy[0]), round(xy[1])))

def rounded_image(source, size, radius):
    im = ImageOps.fit(source, size, method=Image.Resampling.LANCZOS).convert('RGBA')
    mask = Image.new('L', size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0]-1, size[1]-1), radius, fill=255)
    im.putalpha(mask)
    return im

def panel(size, radius=28):
    im = Image.new('RGBA', size)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, size[0]-1, size[1]-1), radius, fill=(26, 27, 32, 255), outline=(73, 69, 67, 255), width=2)
    return im

def shadow(layer):
    im = Image.new('RGBA', (layer.width+160, layer.height+160))
    mask = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    mask.putalpha(layer.getchannel('A').point(lambda p: int(p*.6)))
    im.alpha_composite(mask, (80, 90))
    return im.filter(ImageFilter.GaussianBlur(35))

logo = Image.open(ROOT/'logo.png').convert('RGBA')
inspect = Image.open(ROOT/'layout/brand-assets/focus-alpine.png').convert('RGBA')
lake = Image.open(ROOT/'layout/brand-assets/glance-alpine-before.png').convert('RGB')
small_logo = logo.resize((52, 52), Image.Resampling.LANCZOS)

# Static atmosphere: deep graphite, a warm pool of light, subtle film grain.
yy, xx = np.mgrid[0:H, 0:W]
glow = np.exp(-(((xx-1320)/650)**2 + ((yy-495)/600)**2))
warm = np.exp(-(((xx-1900)/620)**2 + ((yy-880)/450)**2))
rng = np.random.default_rng(21)
grain = rng.normal(0, .52, (H, W))
bg = np.stack([11+12*glow+9*warm+grain, 12+9*glow+4*warm+grain, 16+8*glow+2*warm+grain], axis=-1)
BG = Image.fromarray(np.uint8(np.clip(bg, 0, 255))).convert('RGBA')

def chrome(im):
    place(im, small_logo, (115, 66))
    text(im, (182, 69), 'Glance', 36, family='en')
    text(im, (1790, 82), 'FOR macOS', 18, MUTED, 'en', 'ra')
    d = ImageDraw.Draw(im)
    d.line((115, 990, 1805, 990), fill=(54, 50, 49), width=1)
    text(im, (115, 1010), 'QUICK PREVIEW. DEEPER WORK.', 18, MUTED, 'en')
    text(im, (1805, 1010), '01  /  GLANCE', 18, MUTED, 'en', 'ra')

def keys(im, xy, amount=0, alpha=1):
    p = panel((348, 76), 17)
    d = ImageDraw.Draw(p)
    if amount:
        d.rounded_rectangle((1, 1, 347, 75), 17, fill=(round(42+30*amount), round(36+16*amount), 32), outline=PEACH, width=2)
    text(p, (33, 18), '⌥', 36, PEACH, 'en')
    text(p, (91, 25), 'Option', 25, family='en')
    text(p, (192, 27), '+', 22, MUTED, 'en')
    text(p, (231, 25), 'Space', 25, family='en')
    place(im, p, xy, alpha)

def pointer(im, x, y, alpha=1, pulse=0):
    p = Image.new('RGBA', (140, 140))
    d = ImageDraw.Draw(p)
    if pulse > 0:
        rad = round(18+48*pulse)
        d.ellipse((70-rad,70-rad,70+rad,70+rad), outline=(*PEACH,round(190*(1-pulse))), width=2)
    d.polygon([(70,70),(70,108),(80,97),(89,114),(96,110),(87,93),(104,92)], fill=(248,247,245), outline=(20,20,22), width=2)
    place(im, p, (x-70,y-70), alpha)

def copy(im, label, line1, line2, sub, t, size=108):
    p = Image.new('RGBA', (650, 630))
    text(p, (0, 0), label, 21, PEACH, 'en')
    text(p, (0, 83), line1, size)
    text(p, (0, 211), line2, size, PEACH)
    text(p, (0, 376), sub, 29, MUTED)
    a = ease(t/.5)
    place(im, p, (130, 260+25*(1-a)), a)

def source_scene(t):
    im = BG.copy()
    chrome(im)
    copy(im, '01   SELECT', '选中。', '即将看见。', '从任何应用，选中路径或链接。', t, 96)
    p = panel((1020, 542))
    d = ImageDraw.Draw(p)
    for i,c in enumerate([(228,106,96),(228,178,86),(103,187,118)]):
        d.ellipse((30+i*28,27,43+i*28,40),fill=c)
    text(p,(510,34),'正在创作',22,MUTED,anchor='mm')
    d.line((1,66,1018,66), fill=(50,49,54), width=1)
    text(p,(55,119),'素材就在这段文字里。',32)
    text(p,(55,191),'打开之前，先看一眼。',27,MUTED)
    chosen=smooth((t-.32)/.54)
    path='~/Pictures/alpine-lake.jpg'
    pathfont=font(31,'mono')
    pw=round(ImageDraw.Draw(p).textlength(path,font=pathfont))
    d.rounded_rectangle((46,282,46+round((pw+22)*chosen),340),10,fill=(68,50,40))
    text(p,(57,292),path,31,PEACH,'mono')
    text(p,(55,429),'图片   /   视频   /   文档   /   网页',23,MUTED)
    a=ease(t/.65)
    y=242+36*(1-a)
    place(im, shadow(p),(690,y-80),a)
    place(im,p,(770,y),a)
    pointer(im, 852+pw*chosen, y+321, smooth((t-.2)/.25), clamp((t-1.18)/.4) if t<1.58 else 0)
    keys(im,(130,752),smooth((t-1.15)/.2),smooth((t-.85)/.3))
    return im

def preview_scene(t):
    im=BG.copy()
    chrome(im)
    copy(im,'02   PEEK','一按。','内容展开。','图片、视频、文档，随即展开。',t,96)
    keys(im,(130,752), .4)
    p=panel((1020,652))
    d=ImageDraw.Draw(p)
    place(p,small_logo.resize((31,31)),(24,23))
    text(p,(70,26),'Glance · Peek',25,family='en')
    text(p,(976,38),'×',27,MUTED,'en','mm')
    picture=rounded_image(lake,(968,521),16)
    place(p,picture,(26,79))
    text(p,(28,617),'alpine-lake.jpg',20,MUTED,'en')
    text(p,(991,617),'单击，查看细节  ↗',20,PEACH,anchor='ra')
    a=ease(t/.65)
    scale=.90+.10*a+.01*smooth(t/2.6)
    p=p.resize((round(p.width*scale),round(p.height*scale)),Image.Resampling.LANCZOS)
    x=1280-p.width/2
    y=525-p.height/2+30*(1-a)
    place(im,shadow(p),(x-80,y-80),a)
    place(im,p,(x,y),a)
    if t>1.55:
        mv=smooth((t-1.55)/.5)
        pointer(im,1670-85*mv,824-130*mv,smooth((t-1.55)/.3),clamp((t-2.2)/.35))
    return im

def inspect_scene(t):
    im=BG.copy()
    chrome(im)
    copy(im,'03   INSPECT + CREATE','看清细节。','继续创作。','缩放 · 图片比较 · Widget 工具',t,77)
    text(im,(132,805),'从快速预览，到下一步处理。',25,MUTED)
    a=ease(t/.5)
    iw=round(1132+12*smooth(t/3))
    ih=round(iw*inspect.height/inspect.width)
    p=rounded_image(inspect,(iw,ih),13)
    x=1206-iw/2
    y=557-ih/2+24*(1-a)
    place(im,shadow(p),(x-80,y-80),a)
    place(im,p,(x,y),a)
    # Attention ring around the real Widget button in the supplied design asset.
    if t>1.35:
        q=smooth((t-1.35)/.45)
        d=ImageDraw.Draw(im)
        r=iw/inspect.width
        box=(round(x+1407*r),round(y+73*r),round(x+1534*r),round(y+118*r))
        d.rounded_rectangle(box,8,outline=(*PEACH,round(220*q)),width=2)
        pointer(im,x+1464*r,y+103*r,q)
    return im

def end_scene(t):
    im=BG.copy()
    a=ease(t/.6)
    icon=logo.resize((176,176),Image.Resampling.LANCZOS)
    place(im,shadow(icon),(792,151+20*(1-a)),a)
    place(im,icon,(872,231+20*(1-a)),a)
    p=Image.new('RGBA',(W,H))
    text(p,(960,498),'Glance',120,INK,'en','mm')
    text(p,(960,637),'一眼即见，灵感不断。',51,PEACH,anchor='mm')
    text(p,(960,708),'你的 macOS 预览与创作入口',27,MUTED,anchor='mm')
    keys(p,(786,798))
    place(im,p,(0,0),a)
    return im

# Smooth scene changes keep the path → preview → inspection narrative continuous.
SCENES=[(0,source_scene),(2.05,preview_scene),(4.65,inspect_scene),(7.75,end_scene)]
def frame(t):
    index=max(i for i,(start,_) in enumerate(SCENES) if start<=t)
    start,fn=SCENES[index]
    im=fn(t-start)
    if index and t-start<.35:
        prevstart,prev=SCENES[index-1]
        im=Image.blend(prev(t-prevstart),im,smooth((t-start)/.35))
    return im.convert('RGB')

def audio():
    sr=48000
    n=sr*SECONDS
    left=np.zeros(n,dtype=np.float64)
    right=np.zeros(n,dtype=np.float64)
    def note(start,duration,hz,volume,pan=0,soft=False):
        length=min(int(duration*sr),n-int(start*sr))
        if length<=0:return
        tt=np.arange(length)/sr
        attack=1-np.exp(-tt/(.18 if soft else .009))
        decay=np.exp(-tt/(1.45 if soft else .5))
        tail=np.clip((duration-tt)/.22,0,1)
        tone=np.sin(2*np.pi*hz*tt)+.17*np.sin(2*np.pi*2*hz*tt)+.045*np.sin(2*np.pi*3*hz*tt)
        v=volume*tone*attack*decay*tail
        begin=int(start*sr)
        left[begin:begin+length]+=v*(1-pan*.35)
        right[begin:begin+length]+=v*(1+pan*.35)
    # Original soft major-seventh harmony, keyed to scene transitions.
    for start in (0,2.05,4.65,7.75):
        for k,hz in enumerate((130.8128,164.8138,195.9977,246.9417)):
            note(start,2.6,hz,.017,(-1)**k*.5,True)
    for start,hz in ((.25,523.251),(1.2,659.255),(2.10,783.991),(2.4,1046.502),(4.7,659.255),(5.05,783.991),(6.15,987.767),(7.8,523.251),(8.05,659.255),(8.3,783.991)):
        note(start,1.3,hz,.045,math.sin(start))
    # Subtle tactile key click and airy transition swells.
    for start in (1.18,4.55):
        length=int(.065*sr)
        tt=np.arange(length)/sr
        click=rng.normal(size=length)*np.exp(-tt*90)*.024
        at=int(start*sr)
        left[at:at+length]+=click
        right[at:at+length]+=click
    fade=np.clip(np.arange(n)/sr/.15,0,1)*np.clip((SECONDS-np.arange(n)/sr)/.55,0,1)
    signal=np.stack((left*fade,right*fade),axis=1)*3.2
    with wave.open(str(OUT/'soundtrack.wav'),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
        f.writeframes((np.clip(signal,-1,1)*32767).astype('<i2').tobytes())

def main():
    audio()
    command=['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(OUT/'soundtrack.wav'),'-map','0:v','-map','1:a','-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-t',str(SECONDS),'-movflags','+faststart',str(OUT/'glance-10s.mp4')]
    encoder=subprocess.Popen(command,stdin=subprocess.PIPE)
    montage=Image.new('RGB',(1280,720),(11,12,16))
    samples={24:(0,.8),93:(1,3.1),189:(2,6.3),273:(3,9.1)}
    for i in range(FPS*SECONDS):
        im=frame(i/FPS)
        encoder.stdin.write(im.tobytes())
        if i in samples:
            slot,t=samples[i]
            # A compact two-by-two storyboard, each frame at 640x360.
            montage.paste(im.resize((640,360),Image.Resampling.LANCZOS),((slot%2)*640,(slot//2)*360))
            im.save(OUT/f'frame-{t:.1f}s.jpg',quality=94)
        if i==273:
            im.save(OUT/'poster.jpg',quality=95)
        if i%60==0:
            print(f'Rendered {i}/{FPS*SECONDS} frames',flush=True)
    encoder.stdin.close()
    if encoder.wait()!=0:
        raise RuntimeError('ffmpeg encoding failed')
    montage.crop((0,0,1280,720)).save(OUT/'storyboard.jpg',quality=95)
    print(OUT/'glance-10s.mp4',flush=True)

if __name__=='__main__':
    main()
