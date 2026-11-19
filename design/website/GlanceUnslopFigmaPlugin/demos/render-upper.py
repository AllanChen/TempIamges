"""Four upper-homepage content films, using supplied photos and native Figma chrome.

No Glance launch, synthetic AI result, or paid cloud task. Image placement, zoom,
menu selection and comparison are explanatory animation. Unslop: Damir
Sokolovsky, CC BY 4.0.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
from concurrent.futures import ThreadPoolExecutor
import json, math, subprocess

ROOT = Path(__file__).resolve().parent
INPUT = ROOT.parents[2] / 'marketing/brand-assets/website-photos'
OUT = ROOT / 'media-upper'
OUT.mkdir(exist_ok=True)
PHOTOS = sorted(p for p in INPUT.iterdir() if p.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp'))
assert len(PHOTOS) == 8, 'Expected the eight supplied portraits'
IMAGES = [ImageOps.exif_transpose(Image.open(p)).convert('RGB') for p in PHOTOS]
BEFORE = Image.open(ROOT / 'source/person.png').convert('RGB')
AFTER = Image.open(ROOT / 'source/person-clean.png').convert('RGB')
FONT = ROOT.parent / 'reference/fonts/Inter.ttf'
ZH_FONT = Path('/System/Library/Fonts/STHeiti Medium.ttc')
FPS, N = 8, 64
PALETTES = {
 'sumi': dict(bg='#0f0f0e', surface='#1b1b1a', raised='#242422', ink='#eae7e0', sub='#a19d94', line='#34342f', accent='#c65a40'),
 'washi': dict(bg='#efede6', surface='#faf9f5', raised='#eae7df', ink='#1c1b19', sub='#5c5952', line='#d5d1c6', accent='#b5462e')}
COPY = {
 'hero': {'zh':['打开照片，即刻查看','切换人物，浏览整组照片','图片始终留在眼前'], 'en':['Open a photo. See it clearly.','Move through the whole collection.','Keep the image in view.']},
 'view': {'zh':['先看完整构图','放大到脸部，检查细节','移动视口，继续查看'], 'en':['Start with the whole frame.','Zoom in to inspect the details.','Pan across the image.']},
 'edit': {'zh':['右键，打开图片工具','选择人物背景分离','确认输入与点数，再运行'], 'en':['Right-click to open image tools.','Choose Background Remover Pro.','Check the input and credits first.']},
 'compare': {'zh':['原图与结果，并排看','拖动滑杆，检查变化','手包移除效果，一眼确认'], 'en':['Keep the original beside the result.','Drag the divider to see the change.','Inspect the handbag-removal result.']}}

def ft(size, lang='en'): return ImageFont.truetype(str(ZH_FONT if lang == 'zh' else FONT), size)
def label(im, xy, s, size, color, lang='en', anchor=None):
 ImageDraw.Draw(im).text(xy, s, font=ft(size,lang), fill=color, anchor=anchor)
def rect(im, bounds, color, radius=8, outline=None, width=1):
 ImageDraw.Draw(im).rounded_rectangle(tuple(round(v) for v in bounds), radius, fill=color, outline=outline, width=width)
def fit(im, image, bounds, crop=False):
 x,y,w,h=map(round,bounds)
 p=(ImageOps.fit if crop else ImageOps.contain)(image,(w,h),Image.Resampling.LANCZOS)
 im.paste(p,(x+(w-p.width)//2,y+(h-p.height)//2))
def ease(t): return 1-(1-max(0,min(1,t)))**3
def pointer(im,x,y,c):
 d=ImageDraw.Draw(im); d.polygon([(x,y),(x+2,y+22),(x+8,y+16),(x+14,y+29),(x+20,y+26),(x+14,y+14),(x+24,y+14)], fill=c['ink'],outline=c['bg'],width=2)
def wrap(s,w,size,lang):
 f=ft(size,lang); words=list(s) if lang=='zh' else s.split(); lines=[]; line=''
 for word in words:
  n=line+(' ' if line and lang=='en' else '')+word
  if f.getlength(n)>w and line: lines.append(line);line=word
  else:line=n
 if line:lines.append(line)
 return lines

def frame(key,lang,theme,kind,t):
 mobile=kind=='mobile'; w,h=(480,440) if mobile else (720,400); c=PALETTES[theme]
 im=Image.new('RGB',(w,h),c['bg']); d=ImageDraw.Draw(im)
 phase=min(2,int(t/2.667)); prog=(t-phase*2.667)/2.667
 footer=90 if mobile else 68; ch=h-footer
 # These are only the photo/content viewport. Window chrome stays native in Figma.
 if key=='hero':
  people=[2,3,7]; active=min(2,int(t/2.667))
  if mobile:
   fit(im,IMAGES[people[active]],(80,8,320,ch-16))
   for i,idx in enumerate(people):
    x=12+i*43;fit(im,IMAGES[idx],(x,ch-60,36,48),True)
    if i==active:rect(im,(x-2,ch-62,x+38,ch-10),None,3,c['accent'],2)
  else:
   for i,idx in enumerate(people):
    x=36+i*228;fit(im,IMAGES[idx],(x,12,192,ch-30))
    if i==active:rect(im,(x-4,8,x+196,ch-14),None,5,c['accent'],2)
   pointer(im,133+active*228,270,c)
 elif key=='view':
  image=IMAGES[0]
  zoom=1 if phase==0 else 1+1.1*ease(prog) if phase==1 else 2.1
  base=ImageOps.fit(image,(round(280*zoom),round((ch-20)*zoom)),Image.Resampling.LANCZOS,centering=(.5,.35))
  cx=base.width//2+round((18*ease(prog)) if phase==2 else 0); cy=round(base.height*.42)
  l=max(0,min(base.width-280,cx-140)); top=max(0,min(base.height-(ch-20),cy-(ch-20)//2))
  visible=base.crop((l,top,l+280,top+ch-20));im.paste(visible,((w-280)//2,8))
  rect(im,(w-94,16,w-16,47),c['surface'],6,c['line'])
  label(im,(w-55,31),f'{round(zoom*100)}%',17,c['ink'],anchor='mm')
  if phase>0:pointer(im,w*.52,ch*.48,c)
 elif key=='edit':
  if mobile: fit(im,IMAGES[5],(10,8,250,ch-16))
  else: fit(im,IMAGES[5],(32,8,300,ch-16))
  mx,my,mw=(206,38,260) if mobile else (384,38,304)
  rect(im,(mx,my,mx+mw,my+204),c['surface'],8,c['line'])
  label(im,(mx+18,my+13),'AI Widgets',18,c['sub'])
  rows=[('人物背景分离' if lang=='zh' else 'Background remover',20),('智能扩图' if lang=='zh' else 'Expand image',30),('AI 换装' if lang=='zh' else 'Outfit swap',30)]
  for i,(s,cost) in enumerate(rows):
   yy=my+52+i*45
   if i==0 and phase>0:rect(im,(mx+8,yy-4,mx+mw-8,yy+33),c['raised'],5)
   label(im,(mx+16,yy),s,17,c['ink'],lang)
   label(im,(mx+mw-16,yy+11),str(cost),15,c['sub'],anchor='rm')
  if phase<2:pointer(im,mx+36,my+69+round((1-ease(prog))*38),c)
  else:
   dx=130 if mobile else 350; dy=70; dw=334
   rect(im,(dx,dy,dx+dw,dy+200),c['surface'],10,c['line'])
   label(im,(dx+20,dy+18),'人物背景分离' if lang=='zh' else 'Background remover',20,c['ink'],lang)
   label(im,(dx+20,dy+65),'已选择 1 张图片' if lang=='zh' else '1 image selected',18,c['sub'],lang)
   label(im,(dx+20,dy+99),'20 点 / 次' if lang=='zh' else '20 credits / run',18,c['sub'],lang)
   rect(im,(dx+18,dy+145,dx+dw-18,dy+184),c['raised'],6,c['line'])
   label(im,(dx+dw/2,dy+164),'开始处理' if lang=='zh' else 'Run Widget',18,c['ink'],lang,'mm')
  label(im,(16,ch-19),'操作示意' if lang=='zh' else 'Workflow illustration',12,c['sub'],lang)
 elif key=='compare':
  if phase==0:
   pw=196 if mobile else 208; gap=16; left=(w-2*pw-gap)//2
   for i,image in enumerate([BEFORE,AFTER]):fit(im,image,(left+i*(pw+gap),6,pw,ch-32))
   label(im,(left+pw/2,ch-17),'原图' if lang=='zh' else 'Original',16,c['sub'],lang,'mm')
   label(im,(left+1.5*pw+gap,ch-17),'结果' if lang=='zh' else 'Result',16,c['sub'],lang,'mm')
  else:
   pw=240; ph=ch-18; x=(w-pw)//2;y=6
   a=ImageOps.fit(BEFORE,(pw,ph),Image.Resampling.LANCZOS);b=ImageOps.fit(AFTER,(pw,ph),Image.Resampling.LANCZOS)
   split=round(pw*(.15+.7*ease(prog))) if phase==1 else round(pw*(.85-.35*ease(prog)))
   im.paste(b,(x,y));im.paste(a.crop((0,0,split,ph)),(x,y));d.line((x+split,y,x+split,y+ph),fill=c['ink'],width=2)
   d.ellipse((x+split-14,y+ph//2-14,x+split+14,y+ph//2+14),fill=c['surface'],outline=c['line'],width=1)
   label(im,(x+split,y+ph//2),'↔',18,c['ink'],anchor='mm')
   pointer(im,x+split+4,y+ph*.57,c)
 # Burnt-in explanation and progress markers are part of every MP4 and GIF.
 d.line((16,ch,w-16,ch),fill=c['line'],width=1)
 for i in range(3):rect(im,(16+i*26,ch+12,34+i*26,ch+15),c['accent'] if i==phase else c['line'],1)
 size=24 if mobile else 23
 for i,s in enumerate(wrap(COPY[key][lang][phase],w-32,size,lang)):
  label(im,(16,ch+25+i*28),s,size,c['ink'],lang)
 return im

def render(job):
 key,lang,theme,kind=job;name=f'{key}-{lang}-{theme}-{kind}'
 frames=[frame(key,lang,theme,kind,i/FPS) for i in range(N)]
 # A useful static poster still shows the selected photo and operation.
 poster_index={'hero':6,'view':30,'edit':30,'compare':8}[key]
 frames[poster_index].save(OUT/f'{name}-poster.jpg',quality=92)
 sheet=Image.new('RGB',(frames[0].width*4,frames[0].height))
 for i,n in enumerate([6,22,38,58]):sheet.paste(frames[n],(i*frames[0].width,0))
 palette=sheet.quantize(colors=224,method=Image.Quantize.MEDIANCUT)
 indexed=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
 indexed[0].save(OUT/f'{name}.gif',save_all=True,append_images=indexed[1:],duration=125,loop=0,optimize=True,disposal=2)
 proc=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{frames[0].width}x{frames[0].height}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/f'{name}.mp4')],stdin=subprocess.PIPE)
 for im in frames:proc.stdin.write(im.tobytes())
 proc.stdin.close()
 assert proc.wait()==0,name
 gif=Image.open(OUT/f'{name}.gif'); duration=0
 for n in range(gif.n_frames):gif.seek(n);duration+=gif.info.get('duration',0)
 assert gif.n_frames>=3 and duration>=7500 and (OUT/f'{name}.gif').stat().st_size<10_000_000
 return dict(key=key,lang=lang,theme=theme,kind=kind,width=frames[0].width,height=frames[0].height,gif=f'media-upper/{name}.gif',poster=f'media-upper/{name}-poster.jpg',mp4=f'media-upper/{name}.mp4',frames=gif.n_frames,durationMs=duration,bytes=(OUT/f'{name}.gif').stat().st_size)

if __name__=='__main__':
 jobs=[(key,lang,theme,kind) for key in COPY for lang in ['zh','en'] for theme in PALETTES for kind in ['desktop','mobile']]
 with ThreadPoolExecutor(max_workers=3) as pool:
  assets=[]
  for a in pool.map(render,jobs):assets.append(a);print(a['key'],a['lang'],a['theme'],a['kind'],a['frames'],'frames',round(a['bytes']/1024),'KB',flush=True)
 manifest=dict(date='2026-11-14',sourcePhotos=[{'index':i+1,'file':p.name,'width':im.width,'height':im.height} for i,(p,im) in enumerate(zip(PHOTOS,IMAGES))],scenePeople={'hero':[3,4,8],'view':[1],'edit':[6],'compare':['existing real handbag original/result']},sourceAppLaunched=False,cloudTasksSubmitted=0,assets=assets)
 (ROOT/'upper-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 print('Rendered four scenes in 32 localized/theme/size variants',flush=True)
