"""20s Glance product film, composed from the current Figma UI exports.
Run: /private/tmp/glance-promo-venv/bin/python outputs/glance-promo-20s/render.py
"""
from pathlib import Path
from functools import lru_cache
import math, subprocess, wave, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps, ImageEnhance

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
ASSETS = OUT / 'assets'
LANG = 'zh'
W, H, FPS, DURATION = 1920, 1080, 30, 20
WHITE = (246, 243, 239)
WARM = (236, 174, 127)
GRAY = (156, 157, 166)
FONT_PATHS = {'cn':'/System/Library/Fonts/Hiragino Sans GB.ttc', 'en':'/System/Library/Fonts/SFNS.ttf', 'mono':'/System/Library/Fonts/Menlo.ttc'}

def clamp(v): return max(0, min(1, v))
def ease(v): return 1-(1-clamp(v))**3
def smooth(v):
    v=clamp(v)
    return v*v*(3-2*v)
@lru_cache(None)
def font(size, family='cn'): return ImageFont.truetype(FONT_PATHS[family], size)
def txt(im, xy, value, size, color=WHITE, family='cn', anchor=None):
    ImageDraw.Draw(im).text(xy, value, font=font(size,family),fill=color,anchor=anchor)
def tr(zh, en): return en if LANG == 'en' else zh
def fit_size(value, maximum, width, family):
    size=maximum
    while size>18 and ImageDraw.Draw(Image.new('RGB',(1,1))).textbbox((0,0),value,font=font(size,family))[2]>width:
        size-=1
    return size
def put(im, layer, xy, alpha=1):
    if alpha<=0:return
    if alpha<1:
        layer=layer.copy()
        layer.putalpha(layer.getchannel('A').point(lambda v:round(v*alpha)))
    im.alpha_composite(layer,(round(xy[0]),round(xy[1])))
def rounded(source, size, radius=22):
    p=ImageOps.fit(source,size,method=Image.Resampling.LANCZOS).convert('RGBA')
    mask=Image.new('L',size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,size[0]-1,size[1]-1),radius,fill=255)
    p.putalpha(mask)
    return p
@lru_cache(None)
def shadow(size):
    p=Image.new('RGBA',(size[0]+120,size[1]+120))
    ImageDraw.Draw(p).rounded_rectangle((60,70,size[0]+60,size[1]+70),24,fill=(0,0,0,150))
    return p.filter(ImageFilter.GaussianBlur(26))

focus=Image.open(ROOT/'layout/brand-assets/focus-alpine.png').convert('RGBA')
compare=Image.open(ROOT/'layout/brand-assets/compare-alpine.png').convert('RGBA').crop((48,30,1602,1042))
video=Image.open(ASSETS/'video.png').convert('RGBA')
capture=Image.open(ASSETS/'capture.png').convert('RGBA')
widget_input=Image.open(ASSETS/'widget-input.png').convert('RGBA')
widget_result=Image.open(ASSETS/'widget-result.png').convert('RGBA')
logo=Image.open(ASSETS/'logo-character.png').convert('RGBA')
lake=Image.open(ROOT/'layout/brand-assets/glance-alpine-after.png').convert('RGB')
sample_before=Image.open(ROOT/'layout/brand-assets/glance-alpine-before.png').convert('RGB')
sample_after=lake
small_logo=rounded(logo,(56,56),15)

# Sample media fills replace only the exported placeholder imagery. UI chrome is
# taken from Figma, including its real toolbars, crop handles and input controls.
def video_ui(t):
    p=video.copy()
    media=ImageOps.fit(lake,(1118,630),method=Image.Resampling.LANCZOS,centering=(.5+.025*math.sin(t*.7),.5)).convert('RGBA')
    put(p,media,(1,35))
    for box in [(424,24,697,79),(25,613,1096,678),(459,496,556,593),(565,496,661,593)]:
        put(p,video.crop(box),box[:2])
    for box in [(460,517,554,572),(566,517,659,572)]:
        put(p,rounded(lake,(box[2]-box[0],box[3]-box[1]),1),box[:2])
    # A captured still appears after the camera action.
    q=smooth((t-1.2)/.28)
    thumb=video.crop((876,462,1096,589))
    put(thumb,rounded(lake,(177,100),2),(21,1))
    put(p,thumb,(876,462+24*(1-q)),q)
    if 1.15<t<1.32:
        flash=Image.new('RGBA',p.size,(255,255,255,round(65*(1-(t-1.15)/.17))))
        put(p,flash,(0,0))
    return p

def crop_ui():
    p=capture.copy()
    box=(118,120,1434,842)
    media=ImageOps.fit(lake,(box[2]-box[0],box[3]-box[1]),method=Image.Resampling.LANCZOS).convert('RGBA')
    # Restore the Figma crop grid, handles and selection border above the media.
    put(p,media,box[:2])
    d=ImageDraw.Draw(p)
    d.rectangle(box,outline=(239,237,230,210),width=2)
    for n in (1,2):
        x=box[0]+(box[2]-box[0])*n/3
        y=box[1]+(box[3]-box[1])*n/3
        d.line((x,box[1],x,box[3]),fill=(239,237,230,65),width=1)
        d.line((box[0],y,box[2],y),fill=(239,237,230,65),width=1)
    for x,y in [(box[0],box[1]),(box[2],box[1]),(box[0],box[3]),(box[2],box[3])]:
        d.rectangle((x-4,y-4,x+4,y+4),fill=(245,245,243))
    return p

# Fill the current Widget media placeholders using one continuous sample image.
def fill_widget(p, box, warm=False):
    p=p.copy()
    size=(box[2]-box[0],box[3]-box[1])
    source=sample_after if warm else sample_before
    media=ImageOps.fit(source,size,method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(24))
    full=ImageOps.contain(source,size,method=Image.Resampling.LANCZOS)
    media.paste(full,((size[0]-full.width)//2,(size[1]-full.height)//2))
    put(p,rounded(media,media.size,7),box[:2])
    return p

# Coordinates are the unchanged image-fill bounds in the exported current UI.
widget_in=fill_widget(widget_input,(382,283,1172,622))
ImageDraw.Draw(widget_in).rectangle((382,632,570,658),fill=(22,23,28))
txt(widget_in,(382,637),'alpine-lake.jpg  ·  6.8 MB',13,(153,151,151),'en')
widget_out=fill_widget(widget_result,(240,63,1313,879),True)
widget_out=fill_widget(widget_out,(673,893,761,957))
widget_out=fill_widget(widget_out,(795,893,881,957),True)
crop=crop_ui()
UIS={'focus':focus,'compare':compare,'capture':crop,'widget-in':widget_in,'widget-out':widget_out}

yy,xx=np.mgrid[:H,:W]
g=np.exp(-(((xx-1330)/720)**2+((yy-550)/720)**2))
g2=np.exp(-(((xx-80)/950)**2+((yy-1100)/720)**2))
grain=np.random.default_rng(45).normal(0,.36,(H,W))
background=np.stack([9+12*g+3*g2+grain,10+8*g+3*g2+grain,14+7*g+5*g2+grain],axis=-1)
BG=Image.fromarray(np.uint8(np.clip(background,0,255))).convert('RGBA')

def shell(im, phase):
    put(im,small_logo,(104,58))
    txt(im,(178,66),'Glance',35,family='en')
    txt(im,(1816,84),'FOR macOS',19,GRAY,'en','ra')
    d=ImageDraw.Draw(im)
    d.line((104,1017,1816,1017),fill=(49,46,47),width=1)
    txt(im,(104,1031),tr('看见内容 · 继续创作','See it. Keep creating.'),18,GRAY,'en' if LANG=='en' else 'cn')
    for i in range(5):
        d.rounded_rectangle((1654+i*33,1038,1672+i*33,1042),2,fill=WARM if i==phase else (70,66,65))

def copy(im, label, lines, sub, t, tags=None):
    p=Image.new('RGBA',(560,630))
    txt(p,(0,0),label,21,WARM,'en')
    family='en' if LANG=='en' else 'cn'
    for i,line in enumerate(lines):txt(p,(0,73+i*105),line,fit_size(line,78,548,family),WARM if i==1 else WHITE,family)
    for i,line in enumerate(sub.split('\n')):txt(p,(0,332+i*42),line,fit_size(line,27,548,family),GRAY,family)
    if tags:
        txt(p,(0,459),tags,22,WHITE)
    a=ease(t/.48)
    put(im,p,(112,290+24*(1-a)),a)

@lru_cache(64)
def resized_ui(name,width):
    source=UIS[name]
    return rounded(source,(width,round(width*source.height/source.width)),18)

def ui(im,name,t,width=1160,cx=1240,cy=583,alpha=1):
    a=ease(t/.56)
    width=round(width*(1+.015*smooth(t/3.2)))
    p=resized_ui(name,width)
    x=cx-p.width/2
    y=cy-p.height/2+26*(1-a)
    put(im,shadow(p.size),(x-60,y-60),a*alpha)
    put(im,p,(x,y),a*alpha)
    return (x,y,p.width/source_width(name),p.height)
def source_width(name):return UIS[name].width

def cursor(im,x,y,pulse=0,alpha=1):
    p=Image.new('RGBA',(160,160))
    d=ImageDraw.Draw(p)
    if pulse:
        r=round(16+50*pulse)
        d.ellipse((80-r,80-r,80+r,80+r),outline=(*WARM,round(190*(1-pulse))),width=2)
    d.polygon([(80,80),(80,117),(91,107),(100,125),(107,121),(98,103),(117,103)],fill=WHITE,outline=(12,13,16),width=2)
    put(im,p,(x-80,y-80),alpha)

def intro(t):
    im=BG.copy();shell(im,0)
    copy(im,'01  /  QUICK PREVIEW',tr(['选中。','一眼即见。'],['Select.','See instantly.']),tr('文本里的路径与链接，\n随手打开。','Open paths and links\nfrom any app.'),t)
    p=Image.new('RGBA',(1100,700))
    d=ImageDraw.Draw(p)
    d.rounded_rectangle((40,74,1050,334),28,fill=(23,24,30),outline=(65,58,53),width=2)
    txt(p,(82,106),tr('从你正在使用的应用','From your current app'),24,GRAY,'en' if LANG=='en' else 'cn')
    d.rounded_rectangle((78,187,1020,255),11,fill=(66,48,37))
    txt(p,(99,202),'~/Pictures/creative-reference.jpg',32,WARM,'mono')
    key=Image.new('RGBA',(372,84))
    kd=ImageDraw.Draw(key)
    amount=smooth((t-.7)/.3)
    kd.rounded_rectangle((0,0,371,83),18,fill=(round(25+35*amount),round(25+18*amount),28),outline=WARM,width=2)
    txt(key,(42,23),'⌥',35,WARM,'en');txt(key,(100,27),'Option  +  Space',25,family='en')
    put(p,key,(352,580))
    a=ease(t/.55)
    put(im,p,(660,260+25*(1-a)),a)
    # Real current UI miniatures establish the preview's destination.
    q=smooth((t-1.1)/.5)
    f=rounded(focus,(292,190),11)
    c=rounded(compare,(292,190),11)
    put(im,f,(744,640-36*q),q)
    put(im,c,(1118,640-36*q),q)
    cursor(im,1660,490,clamp((t-.75)/.38) if t<1.13 else 0,smooth((t-.25)/.3))
    return im

def focus_scene(t):
    im=BG.copy();shell(im,1)
    copy(im,'02  /  IMAGE INSPECT',tr(['看清。','每一处细节。'],['See clearly.','Every detail.']),tr('缩放、平移、多图浏览，\n让素材更容易判断。','Zoom, pan and browse.\nInspect every image.'),t,'100%   ·   ZOOM   ·   BROWSE')
    ui(im,'focus',t)
    return im

def compare_scene(t):
    im=BG.copy();shell(im,2)
    copy(im,'03  /  COMPARE',tr(['并排一看。','差异更清楚。'],['Side by side.','Spot the change.']),tr('两张图片，放在一起。\n选出你想继续的那一张。','Compare two images.\nChoose what works.'),t,'SIDE BY SIDE   ·   COMPARE')
    x,y,s,h=ui(im,'compare',t)
    q=smooth((t-.7)/.45)
    cursor(im,x+725*s,y+54*s,clamp((t-1.05)/.45) if t<1.5 else 0,q*(1-smooth((t-1.8)/.5)))
    return im

def video_scene(t):
    im=BG.copy();shell(im,3)
    copy(im,'04  /  VIDEO + CAPTURE',tr(['停在此刻。','留下这一帧。'],['Pause here.','Keep this frame.']),tr('预览视频，截取画面。\n裁剪后继续使用。','Play, capture and crop.\nSave the perfect frame.'),t,'PLAY   ·   CAPTURE   ·   CROP')
    q=smooth((t-2.05)/.42)
    a=ease(t/.55)
    p=rounded(video_ui(t),(1160,725),18)
    x,y=660,224+26*(1-a)
    put(im,shadow(p.size),(x-60,y-60),a*(1-q))
    put(im,p,(x,y),a*(1-q))
    if t<2.2:
        cursor(im,x+455*1160/1120,y+51*1160/1120,clamp((t-1.15)/.42) if t<1.57 else 0,smooth((t-.55)/.35)*(1-q))
    ui(im,'capture',max(.56,t),alpha=q)
    return im

def widget_scene(t):
    im=BG.copy();shell(im,4)
    q=smooth((t-2.25)/.5)
    copy(im,'05  /  WIDGET',tr(['把预览，','变成下一步。'],['From preview','to what’s next.']),tr('图片、文本与蒙版输入，\n用 Widget 继续处理。','Add an image and prompt.\nLet a Widget take it further.'),t,'INPUT   →   RUN   →   RESULT')
    x,y,s,h=ui(im,'widget-in',t,alpha=1-q)
    ui(im,'widget-out',max(.56,t),alpha=q)
    if .8<t<2.6:
        cursor(im,x+1138*s,y+855*s,clamp((t-1.9)/.4) if t<2.3 else 0,smooth((t-.8)/.35)*(1-q))
    return im

def ending(t):
    im=BG.copy()
    a=ease(t/.6)
    icon=rounded(logo,(206,206),48)
    put(im,shadow(icon.size),(797,125+20*(1-a)),a)
    put(im,icon,(857,185+20*(1-a)),a)
    layer=Image.new('RGBA',(W,H))
    txt(layer,(960,504),'Glance',126,WHITE,'en','mm')
    txt(layer,(960,642),tr('一眼即见，继续创作。','See it. Keep creating.'),54,WARM,'en' if LANG=='en' else 'cn','mm')
    txt(layer,(960,722),tr('你的 macOS 预览与处理入口','Your macOS viewer and creative workspace'),27,GRAY,'en' if LANG=='en' else 'cn','mm')
    txt(layer,(960,841),'⌥  Option + Space',29,WHITE,'en','mm')
    put(im,layer,(0,18*(1-a)),a)
    return im

SCENES=[(0,intro),(3,focus_scene),(6.2,compare_scene),(9.2,video_scene),(12.7,widget_scene),(17.5,ending)]
def frame(t):
    idx=max(i for i,(s,_) in enumerate(SCENES) if s<=t)
    start,fn=SCENES[idx]
    im=fn(t-start)
    if idx and t-start<.38:
        ps,pf=SCENES[idx-1]
        # A fast lateral dissolve keeps UI transitions readable.
        im=Image.blend(pf(t-ps),im,smooth((t-start)/.38))
    return im.convert('RGB')

def audio():
    sr=48000;n=sr*DURATION
    signal=np.zeros((n,2),dtype=np.float64)
    rng=np.random.default_rng(8)
    def note(at,dur,hz,amp,pan=0,pad=False):
        begin=int(at*sr);length=min(int(dur*sr),n-begin)
        if length<=0:return
        tt=np.arange(length)/sr
        env=(1-np.exp(-tt/(.25 if pad else .009)))*np.exp(-tt/(2.4 if pad else .55))*np.clip((dur-tt)/.25,0,1)
        v=(np.sin(2*np.pi*hz*tt)+.11*np.sin(4*np.pi*hz*tt)+.025*np.sin(6*np.pi*hz*tt))*env*amp
        signal[begin:begin+length,0]+=v*(1-pan*.25)
        signal[begin:begin+length,1]+=v*(1+pan*.25)
    chords=[(130.8128,164.8138,195.9977,246.9417),(110,130.8128,164.8138,195.9977),(87.307,130.8128,174.614,220),(97.999,146.832,195.998,246.942)]
    for bar in range(8):
        at=bar*2.4
        chord=chords[bar%4]
        for k,hz in enumerate(chord):note(at,3,hz,.022,(-1)**k*.55,True)
        for step in range(8):
            note(at+step*.3,.8,chord[(step+bar)%4]*4,.032,math.sin(step))
        for beat in range(4):
            start=int((at+beat*.6)*sr);length=min(int(.18*sr),n-start)
            tt=np.arange(length)/sr
            kick=np.sin(2*np.pi*(53*tt+35*.025*(1-np.exp(-tt/.025))))*np.exp(-tt*25)*.075
            signal[start:start+length]+=kick[:,None]
    for at in (1,7.25,10.35,14.6):
        i=int(at*sr);tt=np.arange(int(.065*sr))/sr
        click=rng.normal(size=len(tt))*np.exp(-tt*95)*.04
        signal[i:i+len(tt)]+=click[:,None]
    for at in (3,6.2,9.2,12.7,17.5):
        i=int((at-.15)*sr);tt=np.arange(int(.36*sr))/sr
        noise=rng.normal(size=len(tt))
        soft=np.convolve(noise,np.ones(40)/40,mode='same')*np.sin(np.pi*tt/.36)**2*.035
        signal[i:i+len(tt)]+=soft[:,None]
    for k,hz in enumerate(chords[0]):note(17.55+k*.06,2.3,hz*4,.048,(-1)**k*.3)
    tt=np.arange(n)/sr
    signal*=np.clip(tt/.15,0,1)[:,None]*np.clip((DURATION-tt)/.7,0,1)[:,None]
    peak=np.max(np.abs(signal));signal*=.75/max(peak,.01)
    with wave.open(str(OUT/'soundtrack.wav'),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
        f.writeframes((signal*32767).astype('<i2').tobytes())

SAMPLES=[1.8,4.7,7.8,10.9,11.9,14.4,16.4,18.8]
def previews():
    if LANG=='en':
        frame(4.7).resize((1280,720),Image.Resampling.LANCZOS).save(OUT/'poster-en.jpg',quality=93)
        return
    board=Image.new('RGB',(1920,1080),(10,11,15))
    for i,t in enumerate(SAMPLES):
        im=frame(t);im.save(OUT/f'frame-{t:.1f}s.jpg',quality=94)
        card=im.resize((480,270),Image.Resampling.LANCZOS)
        board.paste(card,((i%4)*480,(i//4)*540+80))
        d=ImageDraw.Draw(board)
        d.text(((i%4)*480+20,(i//4)*540+370),f'{t:.1f}s',font=font(22,'en'),fill=GRAY)
    board.save(OUT/'storyboard.jpg',quality=95)
    frame(18.8).save(OUT/'poster.jpg',quality=95)

def main(preview=False):
    previews()
    if preview:return
    audio()
    output=OUT/('glance-20s-en.mp4' if LANG=='en' else 'glance-20s.mp4')
    cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(OUT/'soundtrack.wav'),'-map','0:v','-map','1:a','-c:v','libx264','-preset','medium','-crf','17','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-t',str(DURATION),'-movflags','+faststart',str(output)]
    encoder=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    for i in range(FPS*DURATION):
        encoder.stdin.write(frame(i/FPS).tobytes())
        if i%60==0:print(f'Rendered {i}/{FPS*DURATION}',flush=True)
    encoder.stdin.close()
    if encoder.wait()!=0:raise RuntimeError('Encoding failed')
    print(output,flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--preview',action='store_true');parser.add_argument('--lang',choices=('zh','en'),default='zh')
    LANG=parser.parse_args().lang
    main(parser.parse_args().preview)
